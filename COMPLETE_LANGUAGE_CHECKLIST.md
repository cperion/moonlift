# Moonlift Complete Language / Hosting / FFI Checklist

Status: end-to-end checklist from the **current reboot state** to a **complete Moonlift language implementation**, including:

- full language/compiler implementation
- open-code / quote / meta layer
- deferred future hosted integration
- plain FFI layer

This document is intentionally a **checklist**, not a narrative status report.
It is a **living document** and should be updated eagerly whenever implementation reality changes.
Boxes should only be checked when the implementation is real and architecturally correct under the ASDL-first rules in:

- `moonlift/CONTRIBUTING.md`

For the frozen closed-language semantic target, see:

- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`

For the current implementation inventory, see:

- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`

For the open-code / quoting design target, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Definition of “complete”

This checklist treats Moonlift as complete only when all of the following are true:

- authored source code can define and compile real programs/modules
- the full intended language surface is implemented, not just manual IR construction
- the compiler pipeline is coherent from authored source to machine code
- the open-code / quote / fragment system exists and closes into the ordinary compiler path
- the hosted integration path exists for the richer future user experience, if that path is still pursued
- the plain FFI layer exists as a stable first-class public path for library/embed/LuaJIT users
- the backend/runtime model can handle the language’s core value categories, not only scalars

So “complete” here means:

- **language complete**
- **compiler complete**
- **meta layer complete**
- **FFI layer complete**
- **hosted layer complete, if/when that deferred path is taken on**

---

# 2. Current checkpoint

The current reboot already has:

- a real ASDL stack:
  - `Surface`
  - `Elab`
  - `Sem`
  - `Back`
- real local expr/stmt/loop/domain lowering
- real `Elab -> Sem`
- real `Sem` layout resolution
- real `Sem -> Back`
- real `Back -> Cranelift`
- real FFI replay of `BackCmd`
- a thin plain FFI path already usable today:
  - opaque `jit/program/artifact` handles
  - `BackProgram -> Artifact` compilation
  - function-pointer lookup
  - explicit free APIs

But it is still missing major authored-language, meta, and FFI-completion pieces, while hosted work is intentionally deferred until after the language and FFI path are complete.

Use this file as the forward checklist from that state.

When checking a box, prefer updating this file in the same change that updates the implementation.
If the implementation required an architectural correction, update the wording here too rather than preserving stale milestones.

Current delivery priority order is:

1. close the language/compiler path
2. stabilize and complete the public FFI path
3. only then revisit hosted/state-aware integration

## 2.1 Immediate codegen-guided priorities from `CODEGEN_FINDINGS.md`

These are the current near-term priorities for the closed compiler path.
They should be treated as **ASDL/phase design work first**, not as backend-only peephole tweaking.

### A. Refactor binding/addressability semantics so value, place, and storage are no longer conflated

- [x] add explicit `ElabPlace` / `SemPlace`-style ASDL for addressable computations instead of representing `ref` targets only as generic exprs
- [x] stop encoding storage decisions directly in early/source-facing binding forms when that choice is really machine-facing
- [x] add a dedicated storage/addressability classification phase boundary rather than forcing `let`/arg/loop binders into stored forms up front
- [x] add an explicit `Sem -> Back` binding-class result shape so backend lowering consumes pure/stored/cell distinctions through ASDL rather than ad hoc residence branching
- [x] split `Sem` binding classes — decided: keep `SemBackBinding` as the machine-facing split; `SemBinding` stays as semantic categories; `SemResidencePlan` is the phase boundary that classifies pure vs stored; no further split needed in `SemBinding` itself
- [x] make `ref` / `deref` / field-address / index-address semantics flow through explicit place nodes instead of hidden storage assumptions

### B. Refactor loop semantics so loop state/exit are explicit, not implied by stmt-list lowering accidents

- [x] distinguish ordinary locals from loop-state ports explicitly in ASDL
- [x] make loop carry ports and loop index ports explicit semantic nouns instead of reusing generic local-binding shapes
- [x] add an explicit loop early-exit result story for expr loops (e.g. `break value`) if early-exit search/probe kernels are intended
- [x] add an explicit loop-body control/result shape — Cranelift's block-param CFG handles branchy bodies naturally; no additional ASDL abstraction needed unless concrete lowering bugs surface
- [x] make shared latch values and loop-invariant values — Cranelift preserves SSA sharing; `let out = expr` is one value; invariants are recognized by Cranelift's loop analysis; no Moonlift-level ASDL needed

### C. Split pure compile-time consts from addressable static data

- [x] stop conflating “compile-time value that should inline/fold” with “global addressable data object” in the item/binding story
- [x] add explicit ASDL distinction between pure const items and addressable static/global data if both are intended
- [x] remove hidden semantic booleans from the ASDL core: function visibility is variant-shaped, and struct/union type declarations are variant-shaped
- [x] route typed numeric / `index` constants through the pure-const path so trivial constants do not become data loads by accident

### D. Strengthen the view/index model so it can represent real kernels

- [x] replace or extend the current simple slice/view story with explicit view forms that can carry at least base + length + stride (and offset/windowing if needed)
- [x] make bounded/zip loops consume those explicit views rather than rediscovering shape from arbitrary exprs late in `Sem -> Back`
- [x] make restrided/interleaved views from existing views representable as ASDL values instead of peeling raw variant fields in lowering
- [x] make row-base sharing representable as ASDL (`SemViewRowBase`) and wire it through residence/layout/const-fold/backend view lowering
- [ ] make segment-base / richer interleaved-base sharing representable in ASDL instead of hoping later lowering rediscovers repeated scalar arithmetic

### E. Preserve code-shape-sensitive control/math structure explicitly

- [x] preserve first-class switch structure longer so dense/sparse dispatch is not collapsed too early into compare chains
- [x] add a first-class authored/semantic scalar choose/select form when branchless lowering is intended, instead of expecting generic `if` exprs to imply it
- [ ] keep code-shape-sensitive math/data-parallel work ASDL-first:
  - [x] first-class frontend intrinsic surface for operations like `fma`
  - [x] initial `MoonliftVec` ASDL fact/plan vocabulary for counted-loop add-reduction vectorization detection
  - [x] initial explicit vector `Back` commands plus LuaJIT FFI replay and Cranelift vector smoke test, including vector add/sub/mul/bit-and/bit-or/bit-xor
  - [x] coherent `MoonliftVec.VecLoopFacts` / `VecLoopDecision` ASDL replaces the old shallow `VecPlan` ladder for vector add-reduction detection
  - [x] initial `VecLoopDecision` / `VecModule -> BackProgram` lowering for simple counted reductions with scalar tail
  - [x] ordinary/unrolled add-reduction path materializes explicit `VecBlock` / `VecCmd` skeletons before `BackProgram`
  - [x] explicit unrolled add-reduction and bounded chunked `i32x4` decisions/lowerings
  - [x] bounded chunked `i32x4` path materializes explicit `VecBlock` / `VecCmd` skeletons before `BackProgram`
  - [x] initial contiguous pointer-backed view loads flow through `VecMemoryAccess` / `VecExprLoad` / `VecCmdLoad` to `BackCmdVecLoad`
  - [x] initial contiguous pointer-backed view stores flow through `VecStoreFact` / `VecCmdStore` to `BackCmdVecStore`
  - [x] initial load-store map loop support for same-base/same-lane in-place maps with explicit `VecNoDependence`; unknown alias pairs remain scalar fallback
  - [ ] broaden vector decision/lowering beyond add-reduction/narrow-bounded reduction shapes
  - [ ] later explicit SIMD/vector source forms if the language wants more than scalar backend recovery

### F. Complete remaining realism gaps exposed by codegen probing

- [ ] strengthen typed literal elaboration and typed const/immediate propagation for unsigned / `index` code (now frozen as a `Surface -> Elab` lowering rule)
  - [x] intrinsic-specific argument elaboration is phase-driven; rotate shift literals and `assume` conditions no longer require authored helper casts
  - [x] `return expr` elaborates `expr` with the function result type, including nested returns in if/switch/loop/block statement bodies
  - [x] arithmetic/bitwise binary expressions elaborate their left operand from the expected result type, then elaborate the right operand from the left operand type (`return 1 + 2` in `-> u32` is `u32`)
  - [x] comparisons use an explicit operand-context phase so contextual left operands like `1 < x_u32` / `1 + 2 < x_u32` elaborate against the typed right operand instead of defaulting to `i32`
  - [x] `for` range bounds elaborate literal bounds as `index` (`for i in 1..5` needs no helper casts/globals)
  - [x] view-constructor descriptor operands elaborate as `index` (`view_from_ptr(p, 4)`, `view(v, 0, n)`, `view_strided(v, 2)`, `view_interleaved(v, 2, 1)`)
  - [ ] remaining contextual literal typing gaps and broader inference ergonomics still need completion
- [ ] fill remaining cast-heavy lowering gaps exposed by realistic kernels
  - [x] explicit scalar `trunc` / `zext` / `sext` / `bitcast` expressions lower in the canonical `Sem -> Back` value path
- [x] make expression-in-loop lowering consistent — new `for`/`while` syntax eliminates old loop-expr/stmt split; carries survive naturally

---

# 3. Phase A — Complete the closed compiler path

Goal:

- make the ordinary closed compiler path complete before layering on the full meta/hosting surface

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

## 3.1 Top-level frontend lowering

### Surface -> Elab top-level

- [x] implement `SurfParam -> ElabParam`
- [x] implement `SurfFunc -> ElabFunc`
- [x] define `export func` vs plain `func` visibility — frozen; `export func` visible to importers, `func` is module-local
- [x] implement `export func` vs plain `func` lowering through explicit `SurfFuncLocal` / `SurfFuncExport`, `ElabFuncLocal` / `ElabFuncExport`, and `SemFuncLocal` / `SemFuncExport` variants
- [x] implement `SurfExternFunc -> ElabExternFunc`
- [x] implement `SurfConst -> ElabConst`
- [x] implement `SurfStatic -> ElabStatic`
- [x] implement `SurfImport -> ElabImport`
- [x] implement `SurfTypeDecl -> ElabTypeDecl`
- [x] implement `SurfItemFunc -> ElabItemFunc`
- [x] implement `SurfItemExtern -> ElabItemExtern`
- [x] implement `SurfItemConst -> ElabItemConst`
- [x] implement `SurfItemStatic -> ElabItemStatic`
- [x] implement `SurfItemImport -> ElabItemImport`
- [x] implement `SurfItemType -> ElabItemType`
- [x] implement `SurfModule -> ElabModule`

### Elab -> Sem top-level

- [x] implement `ElabParam -> SemParam`
- [x] implement `ElabFunc -> SemFunc`
- [x] implement `ElabExternFunc -> SemExternFunc`
- [x] implement `ElabConst -> SemConst`
- [x] implement `ElabStatic -> SemStatic`
- [x] implement `ElabImport -> SemImport`
- [x] implement `ElabTypeDecl -> SemTypeDecl`
- [x] implement `ElabItemFunc -> SemItemFunc`
- [x] implement `ElabItemExtern -> SemItemExtern`
- [x] implement `ElabItemConst -> SemItemConst`
- [x] implement `ElabItemStatic -> SemItemStatic`
- [x] implement `ElabItemImport -> SemItemImport`
- [x] implement `ElabItemType -> SemItemType`
- [x] implement `ElabModule -> SemModule`

## 3.2 Environment and namespace synthesis

### Value environments

- [x] synthesize function arg envs automatically from params
- [x] synthesize module item envs automatically from sibling items
- [x] support sibling function references in module scope
- [x] support sibling const references in module scope
- [x] support sibling extern references in module scope
- [x] support sibling static references in module scope
- [x] synthesize imported qualified module envs through the real named-module package path

### Type environments

- [x] actually wire `ElabEnv.types` into frontend type resolution
- [x] support named type lookup through the real env path
- [x] support module-qualified type lookup

### Layout environments

- [x] define the current real source of layout information in the reboot
- [x] synthesize `ElabTypeLayout` from that source
- [x] synthesize `SemLayoutEnv` automatically for downstream passes
- [x] make field access and aggregate construction work without manual test-only env injection along the real module compile path

## 3.3 Qualified name/path resolution

- [x] implement `SurfPathRef` value resolution
- [x] support module-qualified value references
- [x] support module-qualified function references
- [x] support module-qualified const references
- [x] support module-qualified type references
- [x] define the current shadowing/lookup rule set clearly enough for the current reboot path

## 3.4 Type-system completion in current language shape

- [x] implement `SurfTArray` lowering fully
- [x] support non-literal array-count elaboration if intended
- [x] fix/complete `ref` typing (`T -> ptr(T)`) in `Surface -> Elab`
- [x] fix/complete `deref` typing (`ptr(T) -> T`) in `Surface -> Elab`
- [ ] define/addressability rules for all referenceable lvalues
- [x] add explicit place/lvalue ASDL in `Elab` and `Sem` instead of relying on generic exprs for all addressable operations
- [x] move storage classification later than raw frontend elaboration so source-facing binders do not pretend to know final machine storage too early
- [x] split pure-value params from address-taken params explicitly instead of treating every param as stored by default
- [x] split pure loop-carried/index values from address-taken loop bindings explicitly instead of forcing storage for every carried/index binding
- [ ] improve type-directed integer literal elaboration for unsigned / `index` authored code
- [ ] make typed literal elaboration strong enough that ordinary unsigned / `index` benchmarks do not require helper const globals just to type-check cleanly
- [x] finalize whether `bool and/or` are strict scalar ops or short-circuit operators
- [x] if short-circuiting is intended, implement CFG lowering for them

## 3.5 Complete authored top-level type/layout story
This depends on the intended reboot language surface.

### If the reboot keeps named types/layouts as imported-only for now

- [ ] document that clearly
- [x] provide a real import/registration mechanism
- [x] wire it into normal module compilation

### If the reboot grows authored type definitions

- [x] add `Surface` type-definition items
- [x] add `Elab` type-definition items
- [x] add `Sem` type-definition items or equivalent layout-carrying path
- [x] add layout synthesis from authored type definitions
- [x] add module/type namespace integration for the current named-module import path

### Newly frozen type families

- [x] implement enum desugaring (`type Color = enum { red, green, blue }` → const declarations)
- [x] implement tagged union desugaring (`type Result = ok(i32) | err(i32)` → discriminant struct + tag constants)
- [x] implement untagged union desugaring (`type U = union { x: i32, y: f32 }` → overlapping-offset struct)
- [x] add closure type: `closure(T) -> R` distinct from `func(T) -> R`

## 3.6 Control-flow and loop completion

- [x] validate final semantics of `while` loops — frozen: `while cond with carries do ... next name = expr ... end`
- [x] validate final semantics of `over range(...)` — replaced by `for i in 0..n` and `for i in start..stop`
- [x] validate final semantics of `over range(start, stop)` — same
- [x] implement array-backed `over value/view` lowering
- [x] implement full slice/view-backed `over value/view` lowering
- [x] implement array-backed `over zip_eq(...)` lowering
- [x] implement full slice/view-backed `over zip_eq(...)` lowering
- [x] define/runtime-check equal-length behavior for zip traversal
- [x] define complete index/domain typing rules — index is always `index` type from `for ... in`
- [x] define final semantics of loop exit/result values — carries survive after loop; no separate `end ->` or `break expr`
- [x] implement typed loop-signature/header source syntax — replaced by `for`/`while` keywords
- [x] add explicit loop port/state ASDL
- [x] add explicit loop early-exit semantics — break preserves current carry values
- [x] fix structural lowering for branchy loop bodies
- [x] support body-local shared latch values — Cranelift SSA preserves sharing
- [x] represent loop-invariant values — Cranelift loop analysis detects invariants
- [x] keep loop-carried state in explicit SSA/block-param form — matches Cranelift lowering
- [x] implement new statement syntax: `for ... in ... do ... end` / `while ... with ... do ... end` with inline `next name = expr`; legacy typed `loop (...) -> T ... end -> expr` remains only as the older expression-loop path

## 3.7 Switch and block completion

- [x] finalize switch-key type rules
- [x] implement all currently intended scalar key kinds (`bool`, integral scalars, `index`)
- [x] decide whether non-scalar switch values are part of the language
- [x] preserve dense switch structure late enough in lowering to allow jump-table-like backend codegen when intended
- [x] preserve first-class switch structure through hot loop bodies / interpreter-style dispatch instead of collapsing it early into compare CFG
- [x] preserve authored `select(...)` as choose-shaped semantic lowering rather than expecting generic `if` exprs to imply it
- [x] surface runtime assertions as `assert(cond)` and lower through explicit `SurfAssert -> ElabAssert -> SemStmtAssert -> BackCmdTrap` rather than expression-statement magic
- [x] finalize block-expression reachability/termination rules — unreachable branches are suppressed; missing result is a compiler error with source span

## 3.8 Const system completion

- [x] define complete constant-expression subset
- [x] implement unary const eval
- [x] implement arithmetic const eval
- [x] implement comparison const eval
- [x] implement cast const eval
- [x] implement select/if const eval if intended
- [x] implement field/index projection const eval if intended
- [x] implement aggregate/array const eval coherently
- [x] define whether calls/intrinsics can appear in const eval — current rule: ordinary calls are not const-evaluable, and intrinsic-call const eval is not currently supported
- [x] support const references between sibling consts/modules — cross-module const references now frozen as supported
- [x] split pure compile-time const items from addressable static data items if the language intends both
- [x] strengthen propagation/immediate folding for typed numeric and `index` consts so codegen-sensitive kernels do not route trivial constants through data objects unnecessarily

## 3.9 Intrinsics completion

### Frontend
- [x] choose frontend intrinsic syntax/binding surface
- [x] add Surface representation if needed
- [x] add Elab representation if needed
- [x] map frontend intrinsic calls into `SemIntrinsic`
- [x] make `fma` reachable from authored/frontend code as a first-class code-shape-sensitive operation
- [x] make intrinsic argument elaboration phase-driven by `SurfIntrinsic` rather than parser magic or authored helper casts (`rotl(x, 1)`, `assume(cond)`, and `fma(a,b,c)` type their operands in `Surface -> Elab`)

### Sem -> Back

- [x] implement `SemExprIntrinsicCall` lowering in value position
- [x] implement `SemExprIntrinsicCall` lowering in materialization position where meaningful
- [x] define which intrinsics are scalar-only vs aggregate/vector-only
- [ ] implement const evaluation for intrinsic calls if the language decides to allow const intrinsics later

### Backend

- [x] map each `SemIntrinsic` to `BackCmd` and/or direct backend lowering strategy
- [x] implement/populate support for:
  - [x] `popcount`
  - [x] `clz`
  - [x] `ctz`
  - [x] `rotl`
  - [x] `rotr`
  - [x] `bswap`
  - [x] `fma`
  - [x] `sqrt`
  - [x] `abs`
  - [x] `floor`
  - [x] `ceil`
  - [x] `trunc_float`
  - [x] `round`
  - [x] `trap`
  - [x] `assume`

## 3.10 Aggregate/value-model completion

- [ ] finalize named aggregate representation strategy in the reboot
- [ ] complete aggregate load/store/materialization rules
- [ ] support array value indexing end-to-end
- [ ] support slice value indexing end-to-end
- [ ] complete the frozen slice/view descriptor model for strided/interleaved/windowed kernels end-to-end
- [ ] support aggregate field addressing and copying uniformly
- [x] implement storable/passable immutable function values — one-word code pointers, storable in structs/arrays
- [x] implement closure desugaring to `struct { fn, ctx }` before `Surface -> Elab`
- [x] implement closure invocation sugar for local/param closure values (`f(x)` -> `f.fn(f.ctx, x)`)
- [x] define view construction primitives — six primitives frozen: `view`, `view_window`, `view_from_ptr`, `view_from_ptr(..., stride)`, `view_strided`, `view_interleaved`
- [x] implement view construction lowering — `view(xs)`, `view(xs, start, len)`, `view_from_ptr`, `view_from_ptr(ptr, len, stride)`, `view_strided`, and `view_interleaved` now lower through explicit `SemView` variants (`SemViewFromExpr`, `SemViewWindow`, `SemViewContiguous`, `SemViewStrided`, `SemViewRestrided`, `SemViewInterleavedView`)
- [x] define array-value indexing semantics — copy-out via `base + i*elem_size` load
- [x] implement scalar array-value indexing in `Sem -> Back`

## 3.11 Sem layout resolution completion

- [ ] ensure all field projections use resolved layout when required
- [ ] ensure all field addresses use resolved offsets when required
- [ ] ensure all named aggregate copies/materializations use resolved layouts automatically
- [x] define whether unresolved field refs may ever survive past layout resolution

## 3.12 Complete compiler front door
- [x] define the canonical public compile pipeline for closed code
- [x] wire `Surface module -> Elab -> Sem -> resolve_sem_layout -> Back -> JIT`
- [x] make that one official path the default compile path
- [x] remove/retire stale direct shortcuts that bypass the real architecture

---

# 4. Phase B — Complete the backend/runtime model for the language

Goal:

- make the runtime/codegen layer able to represent the real language, not just a scalar subset

## 4.1 `Sem -> Back` missing pieces

- [ ] implement full slice/view lowering model
- [ ] implement bounded-value domain lowering
- [x] implement `zip_eq` lowering
- [x] implement intrinsic lowering
- [x] stop redeclaring direct/extern callees from call sites during `Sem -> Back`
- [x] make loop-carried/index lowering use backend-valid value naming without duplicate bound ids
- [x] lower explicit binding storage class distinctions through an explicit `SemBackBinding` ASDL result instead of leaving them as ad hoc residence checks inside backend lowering
- [x] lower explicit machine-facing switch-arm key distinctions through `SemBackSwitch*` ASDL results instead of re-probing raw switch expressions inside backend lowering
- [ ] lower explicit `SemPlace`-style addressable forms directly instead of inferring addressability from generic exprs late in the backend
- [x] keep params as pure backend values until an explicit addressability requirement forces materialization to storage
- [x] keep loop-carried/index values as pure backend/block-param values until an explicit addressability requirement forces materialization to storage
- [x] keep pure immutable locals/invariants as backend values unless an explicit addressability requirement forces storage
- [x] fix terminated/block-fill handling for branchy loop bodies and body-local shared values
- [x] complete `SemExprCastTo` value lowering in the canonical expr path — scalar numeric casts now choose explicit `SemCastOp` results and lower to Back conversion commands
- [ ] complete non-scalar load lowering where intended
- [ ] complete non-scalar call result lowering where intended
- [x] complete closure invocation sugar / closure-call lowering for local and parameter closure values
- [ ] complete non-scalar loop expr lowering where intended
- [ ] complete non-scalar switch/if/block expr lowering where intended

## 4.2 Back command set completion

- [x] decide whether the current `BackCmd` set is sufficient for the finished language
- [x] if not, extend `BackCmd` deliberately rather than encoding everything indirectly
- [x] implement `BackCmdFrem` or remove it from the intended surface — decided: remove; float `%` is not part of the language
- [x] confirm which casts/conversions need direct backend support vs higher lowering
- [x] decide whether explicit memcpy/memset/data-copy commands should exist
- [x] decide whether plain scalar choose forms should lower through explicit `BackCmdSelect`/select-shaped semantics instead of branch CFG when intended
- [x] add first-class backend switch/dispatch support if preserved semantic switch structure is meant to survive into Cranelift cleanly
- [x] decide whether first-class switch preservation needs explicit `BackCmd`/Back-plan support rather than only pre-lowered compare CFG
- [x] decide whether slice/view runtime primitives need dedicated `BackCmd` support

Current design decision state:

- the current `BackCmd` set is **not** sufficient for the finished language
- explicit bulk copy/fill commands now exist as `BackCmdMemcpy` / `BackCmdMemset`, and current aggregate copy/materialization lowering uses them where whole-object copy/fill is now explicit
- scalar choose should stay explicit as `BackCmdSelect` when the language means choose/dataflow rather than CFG `if`
- scalar conversions that map directly to Cranelift stay as explicit `Back` commands; aggregate/descriptor conversions should lower earlier into explicit materialization/copy plans
- generic slice/view runtime primitives are **not** intended as a second `Back` mini-IR; slice/view descriptors should decompose to ordinary scalar/backing-address facts before `Back`

## 4.3 ABI completion

- [x] decide the final value ABI categories:
  - [x] scalar values by value
  - [x] pointers by value
  - [x] function values by value
  - [x] slice descriptors as materialized descriptor values
  - [x] view descriptors as materialized descriptor values
  - [x] aggregate/descriptor values by hidden pointer/materialization path
  - [x] single-result only; multi-result returns are not part of the language
- [x] support non-scalar return values through the frozen hidden-pointer result path
- [x] support non-scalar call arguments/results coherently under the frozen descriptor/aggregate ABI
- [x] define internal extern ABI rules for aggregates/slices/views/function values
- [x] define function-pointer ABI rules for indirect calls

## 4.4 Addressability/lvalue model completion

- [x] define what counts as an addressable lvalue
- [x] support address of args if intended
- [x] support address of immutable locals if intended
- [x] support address of globals/const data where meaningful
- [x] define when temporaries are materialized to stack for non-scalar call arguments/results
- [ ] implement the frozen address-taken/materialization trigger for params from pure values to stored values
- [ ] implement the frozen address-taken/materialization trigger for loop carries/index bindings from pure values to stored values
- [ ] make `ref`/`deref` semantics coherent across scalar and aggregate cases

## 4.5 Memory/layout model completion

- [ ] define complete runtime representation for:
  - [ ] named aggregates
  - [ ] arrays
  - [ ] slices/views
  - [ ] function values if storable
- [ ] complete type-size/alignment queries for all supported runtime types
- [ ] complete copy/materialization logic for all supported storable types

## 4.6 Rust backend completion

- [ ] implement all intended `BackCmd` variants in `src/lib.rs`
  - [x] current integer vector arithmetic/load/store lane slice
  - [x] current integer vector compare/select/mask slice
- [ ] keep `jit.lua` replay in sync with all `BackCmd` variants
  - [x] replay current integer vector arithmetic/load/store lane slice
  - [x] replay current integer vector compare/select/mask slice
- [ ] support full intended artifact/function retrieval model
- [ ] define stable error behavior for unsupported IR
- [x] decide whether a persistent session/module model replaces or extends the current artifact model

---

# 5. Phase C — Add the complete parser/text frontend

Goal:

- make Moonlift a real authored language, not only ASDL/manual builder construction

## 5.1 Parser architecture

- [x] choose parser implementation language for the reboot path
- [x] define parser ownership boundary relative to Lua/host/runtime
- [x] ensure parser produces `MoonliftSurface`

Current implemented direction:

- hand-written Lua lexer/parser
- direct construction of `MoonliftSurface` ASDL values
- no separate plain-table parser AST as the main representation

## 5.2 Surface syntax coverage

- [x] parse all current type forms
- [x] parse all expr forms currently present in the reboot `Surface` ASDL
- [x] parse all stmt forms currently present in the reboot `Surface` ASDL
- [x] parse all loop/domain forms currently present in the reboot `Surface` ASDL
- [x] parse all top-level item/module forms currently present in the reboot `Surface` ASDL
- [x] parse all intended intrinsic forms in the current reboot closed language
- [x] parse the current authored type/layout declarations (`type ... = struct { ... }`)

Current implemented reboot parser/frontend now includes:

- types:
  - scalar
  - pointer
  - array
  - slice
  - `view(T)`
  - function type
  - named path
- expressions:
  - literals
  - names / paths
  - unary / binary ops
  - casts
  - intrinsic calls
  - call / field / index
  - field-based aggregate literals
  - array literals via `[]T { ... }`
  - `if` expr
  - `select(cond, a, b)`
  - `switch` expr
  - `do ... end` block expr
  - canonical loop expr
- statements:
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `assert(cond)`
  - `if`
  - `switch`
  - `return`
  - `break`
  - `break value`
  - `continue`
  - canonical loop stmt
- top-level items:
  - `func`
  - `extern func`
  - `const`
  - `static`
  - `import`
  - `type ... = struct { ... }`
  - module packaging

## 5.3 Diagnostics

- [x] source spans/locations at the parser/bootstrap source-front-end layer
- [x] parser diagnostics
- [x] elaboration/name/type diagnostics
- [x] better layout/type error messages
- [x] module/path resolution diagnostics

Current state:

- parser/token diagnostics are structured
- parser exposes parse-with-spans helpers
- source spans are tracked through a path-keyed span index
- public source helpers now catch parse/lower/sem/layout/resolve/back/compile failures through the `try_*` entrypoints and map them back to source paths/line+column when spans are available
- package-level `try_*` helpers now attach importing module names and import-path spans for missing/cyclic module-resolution failures
- lower/layout/type diagnostics now strip raw Lua file/line noise and surface clearer field/layout messages (including available named fields where relevant)
- later-stage diagnostics can still improve further, but the old layout/type-message gap is no longer large enough to keep this box open

## 5.4 Compile facade

- [x] `source text -> Surface`
- [x] `source text -> compiled artifact`
- [x] `source module/package -> compiled artifact`
- [x] source-level error reporting through the canonical public API

Current state:

- `moonlift/lua/moonlift/source.lua` exists
- canonical single-module front-door helpers are now:
  - `pipeline(...)`
  - `back(...)`
  - `compile(...)`
- named-package front-door helpers are:
  - `pipeline_package(...)`
  - `back_package(...)`
  - `compile_package(...)`
- public helpers already cover:
  - `source text -> Surface`
  - `source text -> Elab`
  - `source text -> Sem`
  - `source text -> resolved Sem + layout env`
  - `source text -> BackProgram`
  - parse-with-spans helpers
  - try-parse / try-lower / try-sem / try-resolve helpers
  - canonical `try_pipeline` / `try_back` / `try_compile` helpers for single modules
  - package `try_pipeline_package` / `try_back_package` / `try_compile_package` helpers
- compile facade therefore exists in real bootstrap form; what remains open is final stabilization/documentation of that API, not the existence of structured source-level failure reporting

---

# 6. Phase D — Implement the complete `Meta` / quote / open-code layer

Goal:

- implement the design in `moonlift/QUOTING_SYSTEM_DESIGN.md`

The target is:

- `MoonliftMeta` as a full open elaborated layer
- closure boundary at `Meta -> Elab`

## 6.1 Add `MoonliftMeta` ASDL

- [x] add `MoonliftMeta` module to the schema
- [x] add open type layer
- [x] add open domain layer
- [x] add open expr layer
- [x] add open stmt layer
- [x] add open loop layer
- [x] add fragment nodes
- [x] add function nodes
- [x] add const nodes
- [x] add item/module nodes
- [x] add params/imports/slots/open-set nodes

Current state: the coherent `MoonliftMeta` ASDL vocabulary exists in `moonlift/lua/moonlift/asdl.lua`. Builder/source quote helpers, structural expansion, query/validation/rewrite tooling, and `Meta -> Elab` sealing phases now exist. Hosted parser integration and alpha normalization remain deferred below.

## 6.2 Interface categories

- [x] implement runtime params as first-class values
- [x] implement imports as first-class values
- [x] implement kinded slots as first-class values
- [x] define binder/symbol identity rules

## 6.3 Builder-side `Meta` construction

- [x] builder expr fragments
- [x] builder region fragments
- [x] builder function templates
- [x] builder const templates
- [x] builder module templates
- [x] builder slot constructors
- [x] builder import constructors

## 6.4 Source-side quote elaboration

- [x] source expr quotes -> `MetaExprFrag`
- [x] source region quotes -> `MetaRegionFrag`
- [x] source func quotes -> `MetaFunction`
- [x] source const/static/module quotes if intended
- [x] elaboration against explicit Meta params/open sets
- [x] quote-hole `$name` source syntax backed by explicit Meta slots/open values
- [x] forbid undeclared free names by default

## 6.5 Structural operations in `Meta`

- [x] slot filling / expansion for all slot kinds
- [x] fragment use / inline assembly nodes
- [x] item/module splice expansion
- [x] deterministic binder rebasing via explicit `use_id` fields
- [ ] alpha normalization / canonicalization
- [x] closedness validation
  - [x] sealing-time rejection for unfilled slots and unexpanded splices
  - [x] explicit `MetaValidationReport` for slots, generic imports, open module names, and unexpanded uses

## 6.6 `Meta -> Elab` closure

- [x] close expr fragments to `ElabExpr`
- [x] close region fragments to `ElabStmt*`
- [x] close functions to `ElabFunc`
- [x] close consts to `ElabConst`
- [x] close modules to `ElabModule`
- [x] ensure no open slots/imports survive closure
  - [x] unfilled slots are rejected during sealing
  - [x] richer import/open-set closedness validation through `meta_validate.lua`

## 6.7 Query/rewrite/walk tooling

- [x] `Meta` walk APIs
- [x] `Meta` query APIs
- [x] `Meta` rewrite APIs
- [x] structural equality / identity guarantees for ASDL identity-based rewrite rules
- [x] PVM phases for open-code normalization and closure
  - [x] structural expansion / slot-filling phases
  - [x] initial PVM sealing phases for closed `Meta -> Elab`

## 6.8 Integration with the closed compiler path

- [x] canonical compile path from `Meta` through `Elab -> Sem -> Back`
- [x] function/module sealing integrated with ordinary compile pipeline
- [x] no accidental second semantic universe beyond `Meta`

---

# 7. Phase E — Deferred hosted integration

Goal:

- keep the richer path described in `moonlift/LUAJIT_HOSTED_INTEGRATION.md` as future design work, but do not prioritize it before the closed language and FFI path are complete

This is **not** the current priority.
Hosted/state-aware integration should be revisited only after the language/compiler and public FFI path are complete and stable.

## 7.1 Lua-state-aware native integration

- [ ] define the hosted/state-aware runtime object model
- [ ] expose real session objects
- [ ] expose real artifact objects
- [ ] expose real compiled function objects
- [ ] expose real callback/function userdata where appropriate
- [ ] add `__gc` lifetime management
- [ ] add direct Lua-callable compiled objects
- [ ] add registry-backed hidden retention of native state

## 7.2 Hosted compile/session model

- [ ] persistent compile session object
- [ ] session-local caches
- [ ] module/function artifact retention
- [ ] stable compiled-object identity rules
- [ ] explicit invalidation/rebuild policy where needed

## 7.3 Hosted parser integration

- [ ] choose final hosted parser integration strategy
- [ ] integrate parser with the hosted environment
- [ ] expose parser-backed fragment syntax if the host/parser model allows it
- [ ] unify hosted syntax with builder/source-string semantics via `Meta`

## 7.4 Rich diagnostics and dev UX

- [ ] direct Lua errors from native/session layer
- [ ] source-mapped diagnostics through hosted parser path
- [ ] object introspection / pretty printing for compiled/session objects
- [ ] disassembly/debug hooks from hosted objects

## 7.5 Hosted callback/runtime ergonomics

- [ ] callback registration surface
- [ ] callback lifetime/ownership rules
- [ ] stateful session wiring for callbacks
- [ ] swap/rebuild/rebind story for compiled callbacks

---

# 8. Phase F — Stabilize and complete the plain FFI layer

Goal:

- keep the existing thin public FFI-facing path
- make it explicit, documented, and complete enough for LuaJIT users
- finish the language/compiler through this path before revisiting hosted integration

This is the **current primary public integration path**, not a secondary compatibility layer.

There is already a thin FFI layer today (`moonlift/src/ffi.rs` + `moonlift/lua/moonlift/jit.lua`).
This phase is about stabilizing, documenting, and extending that path rather than inventing it from scratch.

## 8.1 Stable FFI surface design

- [ ] decide stable C ABI surface
- [ ] define opaque handles for:
  - [ ] session
  - [ ] artifact
  - [ ] compiled function
  - [ ] maybe modules/types/layouts if exposed
- [ ] define ownership/free rules clearly
- [ ] define error reporting surface clearly

## 8.2 FFI compile/build APIs

- [x] compile from `BackProgram`
- [ ] compile from higher-level forms if desired
- [x] function lookup APIs
- [ ] module lookup APIs if desired
- [x] explicit free/destruction APIs

## 8.3 FFI calling APIs

- [ ] scalar call helpers
- [ ] pointer call helpers
- [ ] aggregate-by-pointer helpers if needed
- [x] keep the FFI calling API single-result only in line with the frozen language target
- [ ] extern registration APIs if needed

## 8.4 FFI marshalling/documentation

- [ ] document ABI rules for all public-callable types
- [x] document lifetime rules
- [x] provide minimal LuaJIT FFI examples
- [x] provide non-hosted library-loading examples

## 8.5 Relationship to hosted path
- [ ] ensure any later hosted path can reuse the core native machinery
- [x] ensure the FFI path remains a first-class supported public path for LuaJIT users, not a second compiler architecture

---

# 9. Phase G — Polish, coherence, and architecture cleanup

Goal:

- make the whole system coherent enough to count as finished rather than merely feature-complete

## 9.1 Remove stale/obsolete code paths

- [x] retire stale `lower_surface_to_sem.lua`
- [x] remove other obsolete shortcuts that no longer match the real architecture
- [x] ensure one canonical compile path exists for closed code
- [ ] ensure one canonical closure path exists for `Meta`

## 9.2 Public API coherence

- [ ] define the canonical builder API
- [ ] define the canonical source API
- [ ] define the canonical `Meta`/quote API
- [ ] define the canonical hosted/session API
- [ ] define the canonical FFI API
- [ ] ensure these surfaces are related clearly rather than duplicative

## 9.3 Documentation coherence

- [ ] keep `README.md` aligned with actual architecture
- [ ] keep `CONTRIBUTING.md` aligned with actual architecture discipline
- [ ] keep `CURRENT_IMPLEMENTATION_STATUS.md` current
- [ ] keep this checklist current as a living document whenever boxes become true/false or need wording changes
- [ ] keep `QUOTING_SYSTEM_DESIGN.md` aligned with real implementation
- [ ] keep `LUAJIT_HOSTED_INTEGRATION.md` aligned with real integration plan
- [ ] document the final compile pipeline end-to-end
- [ ] document the final value/layout/ABI model end-to-end

## 9.4 Performance and caching coherence

- [ ] ensure PVM boundaries are correct and stable
- [ ] ensure open-code operations are structural and cache-friendly
- [ ] ensure layout resolution is memoized in the right place
- [ ] ensure compile/session caches are architecturally clean
- [ ] ensure hosted and FFI paths do not create duplicate semantic work

---

# 10. Final completion checklist

Moonlift reaches the intended complete state only when all of these are true:

## 10.1 Closed language/compiler

- [ ] authored source code can define real functions, consts, externs, and modules
- [ ] top-level frontend lowering is complete
- [ ] namespace/env synthesis is complete
- [ ] type/layout story is complete for the intended language
- [ ] loops/domains are complete for the intended language
- [ ] const eval is complete for the intended language
- [ ] intrinsics are complete for the intended language
- [ ] `Surface -> Elab -> Sem -> Back` is coherent and canonical

## 10.2 Runtime/backend

- [ ] scalar backend is complete
- [ ] aggregate/slice/value-model backend is complete
- [ ] ABI is complete for intended public/runtime value categories
- [ ] Rust backend supports the intended `BackCmd` set

## 10.3 Meta/open-code system

- [x] `MoonliftMeta` exists
- [ ] fragments/functions/modules as open code exist
- [ ] structural slot/import system exists
- [x] initial closed `Meta -> Elab` closure exists
- [ ] source/builder/hosted syntax all converge at `Meta`

## 10.4 Hosted integration

- [ ] state-aware hosted path exists
- [ ] parser-hosted or equivalent rich syntax path exists as intended
- [ ] sessions/artifacts/compiled callables are real host objects

## 10.5 FFI layer

- [ ] plain FFI-facing API exists
- [ ] stable ABI/lifetime/error rules are documented
- [ ] FFI users can compile and call Moonlift cleanly without the rich hosted path

## 10.6 Documentation

- [ ] current status, design docs, and public docs all match reality

---

# 11. Short reading order

A good way to use the current docs together is:

1. `moonlift/CONTRIBUTING.md`
   - the ASDL-first rules for making changes correctly
2. `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
   - what exists right now
3. `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`
   - what remains to reach completion
4. `moonlift/QUOTING_SYSTEM_DESIGN.md`
   - the target `Meta` / open-code design
5. `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
   - the richer future hosting strategy

That set is the current roadmap stack.
