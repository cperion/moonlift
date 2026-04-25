# Moonlift Current Implementation Status

Status: implementation inventory for the **current rebooted Moonlift**.

This document is about **what has and has not actually been coded yet**, based on the current implementation and the current ASDL in:

- `moonlift/lua/moonlift/asdl.lua`

This file should be kept in sync eagerly with the implementation.
For the contribution rules that define what counts as an architecturally correct implementation, see:

- `moonlift/CONTRIBUTING.md`

For the frozen closed-language semantic target that this inventory is measured against, see:

- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`

This is **not** a test-status document.
It is intentionally focused on implementation coverage rather than test enumeration.
Tests, local build prerequisites, and shared-library availability may still drift independently of this inventory; this file is about implementation coverage.

For the current reboot source-language shape, parser target, and span strategy, see:

- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md`
- `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md` — frozen typed loop-header/signature design note, now reflected in the canonical parser/front-end syntax
- `moonlift/SOURCE_SPAN_STRATEGY.md`

For the ASDL-first vectorization direction, see:

- `moonlift/VECTORIZATION_DESIGN.md`
- `moonlift/VECTORIZATION_ASDL_REDESIGN.md`

For the future open-code / metaprogramming direction, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future LuaJIT-hosted / self-hosted integration and parser-hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Scope of this review

If this file and the code disagree, the file should be fixed immediately.
Do not leave known drift here just because a checklist item or design note existed earlier.

This inventory was based on the current implementation files:

- `moonlift/lua/moonlift/asdl.lua`
- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/lua/moonlift/source.lua`
- `moonlift/lua/moonlift/source_spans.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_top.lua`
- `moonlift/lua/moonlift/lower_elab_to_sem.lua`
- `moonlift/lua/moonlift/resolve_sem_layout.lua`
- `moonlift/lua/moonlift/lower_sem_to_back.lua`
- `moonlift/lua/moonlift/lower_sem_to_back_cast.lua`
- `moonlift/lua/moonlift/jit.lua`
- `moonlift/src/lib.rs`
- `moonlift/src/ffi.rs`

One legacy compatibility file is now explicitly retired and should **not** be treated as a real pipeline stage:

- `moonlift/lua/moonlift/lower_surface_to_sem.lua`
  - current behavior: fail fast and direct users to the canonical `Surface -> Elab -> Sem` path

---

# 2. Current real compiler shape

The current actual ASDL defines a real closed compiler stack:

- `MoonliftSurface`
- `MoonliftElab`
- `MoonliftSem`
- `MoonliftBack`

It also now defines the future open-code layer vocabulary:

- `MoonliftMeta`

The current implementation already contains a real middle/back-end path for significant parts of the closed stack. The `MoonliftMeta` ASDL is present as one coherent open-code vocabulary, but its builder/source frontends, normalization phases, slot-filling phases, and `Meta -> Elab` sealing phases are not implemented yet.

## High-level summary

### Real and coded today
- local expression lowering
- local statement lowering
- local loop and domain lowering
- typed `while`/`over` expr loops with valued early-exit results (`break expr`) through the current backend path
- explicit `ElabExprExit` / `SemExprExit` classification so breakless expr loops and valued-break expr loops are no longer conflated in backend lowering
- explicit function-scoped storage/addressability planning through `SemResidencePlan`
- explicit machine-facing `SemBinding -> SemBackBinding` classification before backend lowering
- explicit machine-facing switch-arm classification (`SemBackSwitchKey`, `SemBackSwitchStmtArms`, `SemBackSwitchExprArms`) before choosing preserved `BackCmdSwitchInt` vs compare fallback lowering
- authored/source `switch` key support for all currently intended scalar kinds: `bool`, integral scalars, and `index`
- explicit `Sem -> Sem` const-scalar normalization before backend lowering so typed numeric / `index` const globals and pure derived scalar const expressions become immediate `SemExprConst*` / `SemExprNil` nodes instead of surviving as runtime const reads
- top-level `Surface -> Elab` lowering for params/funcs/externs/consts/statics/imports/type-items/modules
- explicit local/export function ASDL variants through `Surface -> Elab -> Sem`; visibility is no longer hidden in boolean fields
- explicit struct/union ASDL variants through `Elab -> Sem -> layout`; union layout uses overlapping field offsets
- top-level `Elab -> Sem` lowering for params/funcs/externs/consts/statics/imports/type-items/modules
- function-arg env synthesis from params
- sibling-item value env synthesis for funcs/consts/externs/statics
- explicit named-module package/import synthesis for qualified cross-module value/type lookup
- module-local type/layout env synthesis from authored `type ... = struct { ... }` and `type ... = union { ... }` items
- env-based named-type resolution through `ElabEnv.types`
- authored intrinsic parsing/lowering through the current closed frontend path
- semantic layout resolution pass with automatic module layout synthesis
- large `Sem -> Back` lowering
- combined package `Sem -> Back` lowering for imported named modules
- bootstrap source front door helpers in `moonlift.source`, including module/package pipeline + compile helpers
- `BackCmd` FFI replay
- Cranelift codegen host in Rust
- initial reboot text parser/front-end that constructs `MoonliftSurface` directly

### Still missing to make the language fully working as an authored language
- complete reboot parser coverage beyond the current bootstrap subset
- richer module/package features beyond the current explicit named-module + `import` path
- richer authored type-definition coverage beyond the current named-struct path
- full first-class slice/view descriptor value model
- fuller const evaluation and immediate propagation
- fuller aggregate / non-scalar ABI support
- richer diagnostics and source mapping through later layers
- quote/open-code operations over the now-defined `MoonliftMeta` ASDL layer

---

# 3. What is already implemented

## 3.1 `Surface -> Elab` for local code and top-level value items is real

Implemented in:

- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_top.lua`

### Types implemented
- `SurfTVoid`
- `SurfTBool`
- all signed integer widths
- all unsigned integer widths
- `SurfTF32`
- `SurfTF64`
- `SurfTIndex`
- `SurfTPtr`
- `SurfTSlice`
- `SurfTView`
- `SurfTFunc`
- `SurfTNamed`

### Expressions implemented
- integer / float / bool / nil literals
- `SurfNameRef`
- authored dotted value syntax with later resolution (`SurfExprDot`)
- unary ops
- binary ops, including comparison operand contextual typing for literal/contextual left operands against typed right operands
- cast forms
- intrinsic calls
- calls
- index access
- aggregate literals
- array literals
- explicit `select(cond, a, b)`
- `if` expr
- `switch` expr
- block expr
- loop expr
- authored view constructors, with descriptor operands (`start`, `len`, `stride`, `lane`) elaborated as `index`

### Statements implemented
- `let`
- `var`
- `set`
- expr stmt
- authored `assert(cond)` through `SurfAssert -> ElabAssert -> SemStmtAssert`
- `if`
- `switch`
- `return`
- `break`
- `break value`
- `continue`
- loop stmt

### Loop/domain forms implemented
- `SurfLoopWhileStmt`
- `SurfLoopOverStmt`
- `SurfLoopWhileExpr`
- `SurfLoopOverExpr`
- `SurfDomainRange`
- `SurfDomainRange2`
- `SurfDomainZipEq`
- `SurfDomainValue`

### Block-local environment threading implemented
The current `Surface -> Elab` code already threads local env effects for:

- `let`
- `var`
- block expr stmt lists
- loop carry bindings and `next`

### Top-level item lowering implemented
The current `Surface -> Elab` code also lowers:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfStatic`
- `SurfImport`
- authored `SurfStruct` type items
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfItemStatic`
- `SurfItemImport`
- `SurfItemType`
- `SurfModule`

And it already synthesizes real module environments for:

- function arguments from params
- sibling function references in module scope
- sibling const references in module scope
- sibling extern references in module scope
- sibling static references in module scope
- sibling named types/layouts from authored type items
- imported qualified module namespaces through the named-package source front door

So the frontend is now real for local code and top-level items, not just a sketch.

---

## 3.2 `Elab -> Sem` for local code and top-level items is real

Implemented in:

- `moonlift/lua/moonlift/lower_elab_to_sem.lua`

Implemented:
- `ElabType -> SemType`
- `ElabParam -> SemParam`
- `ElabBinding -> SemBinding`
- `ElabExpr -> SemExpr`
- `ElabStmt -> SemStmt`
- `ElabDomain -> SemDomain`
- `ElabLoop -> SemLoop`
- `ElabFunc -> SemFunc`
- `ElabExternFunc -> SemExternFunc`
- `ElabConst -> SemConst`
- `ElabImport -> SemImport`
- `ElabItem -> SemItem`
- `ElabModule -> SemModule`

Also implemented:

- call target classification:
  - globals become `SemCallDirect`
  - externs become `SemCallExtern`
  - locals/args become `SemCallIndirect`

Top-level authored funcs currently lower to `SemFuncExport`, since the rebooted Surface layer does not yet expose a visibility/export distinction.

So the elaborated-to-semantic lowering is real for both local code and top-level items.

---

## 3.3 Semantic layout resolution is real

Implemented in:

- `moonlift/lua/moonlift/resolve_sem_layout.lua`

Implemented:
- named-layout lookup through `SemLayoutEnv`
- `SemFieldByName -> SemFieldByOffset`
- recursive resolution over exprs
- recursive resolution over stmts
- recursive resolution over loops
- recursive resolution over funcs/consts/items/modules
- recursive resolution over `SemIndexBaseView`
- recursive resolution over call targets and field refs

This is an important real pass, not a stub.

---

## 3.4 `Sem -> Back` is large and real

Implemented in:

- `moonlift/lua/moonlift/lower_sem_to_back.lua`

### Strongly implemented areas
- scalar integer lowering
- scalar float lowering
- bool lowering
- comparisons
- bitwise ops
- scalar cast / extend / reduce / promote / demote / float-int conversion command emission, including `SemExprCastTo` through explicit `SemCastOp` selection and explicit `trunc` / `zext` / `sext` / `bitcast` expression lowering
- select
- direct / extern / indirect calls

Authored `select(cond, a, b)` is already preserved distinctly through the current closed path as `SurfSelectExpr -> ElabSelectExpr -> SemExprSelect -> BackCmdSelect`, rather than being forced through generic `if`-CFG lowering.
- direct/extern call lowering without redundant call-site redeclarations
- block params / CFG lowering
- explicit expr-flow lowering through `BackExprLowering`
- explicit address/materialization-flow lowering through `BackAddrLowering`
- `if` / `switch`
- `while` loops
- `over range(...)`
- `over range(start, stop)`
- loop exprs
- loop-carried/index lowering through canonical slots without duplicate backend value ids
- block exprs
- assert -> trap lowering
- const data object emission
- function lowering from `SemFunc`
- item lowering from `SemItem`
- module lowering from `SemModule`

### Aggregate-ish support that is already real
- named aggregate copies via layout env
- named aggregate materialization into memory
- array literal materialization into memory
- named aggregate const-data initialization
- array const-data initialization
- explicit whole-object bulk copy/fill commands now exist in `Back` as `BackCmdMemcpy` / `BackCmdMemset`
- current `Sem -> Back` aggregate copy/materialization lowering now uses those commands for whole-object copy and zero-fill where appropriate

So `Sem -> Back` is already a serious implementation, especially on the scalar/CFG side.

---

## 3.5 FFI replay and Rust backend are real

### LuaJIT side
Implemented in:

- `moonlift/lua/moonlift/jit.lua`

This currently replays the `BackCmd` stream into the Rust builder via FFI.
That replay path now uses plain non-memoized command dispatch rather than a memoized `pvm.phase(...)` call, so identical `BackCmd` values replay every time instead of being accidentally skipped.
That matters for real CFG shapes where both branches may emit the same join jump or other repeated command values.
There is already a thin plain FFI-facing path today, and that FFI path is the current practical/project-priority integration route while the language is completed.
What is still missing there is a more polished/stable final public FFI surface.
Practical use through `moonlift.jit` still requires building the shared library with cargo and either letting the default `target/...` search path find it or passing an explicit `libpath`; that build/load requirement is separate from the backend implementation coverage described here.

### Rust side
Implemented in:

- `moonlift/src/lib.rs`
- `moonlift/src/ffi.rs`

The current C ABI already exposes opaque handles for:

- `moonlift_jit_t`
- `moonlift_program_t`
- `moonlift_artifact_t`

The Rust host already supports a broad subset of current `BackCmd`, including:

- data declarations and initialization
- function declarations
- blocks and block params
- stack slots
- constants
- scalar ops
- comparisons
- loads / stores
- explicit bulk memory copy/fill (`BackCmdMemcpy` / `BackCmdMemset`) via Cranelift libcalls
- direct / extern / indirect calls
- select
- branches / jumps / returns / trap

So the backend is not speculative.
It exists.

---

# 4. What still exists mainly as internal / pass-produced IR today

Some semantic forms are real and used downstream, but are still reached mostly through internal passes, lower-level helper lowering, or manual `Sem` construction in tests rather than through broad first-class authored syntax.

Important current examples include:

- `SemExprLoad`
- resolved field refs like `SemFieldByOffset`
- lower-level explicit view/index forms such as `SemView*` and `SemIndexBaseView`

These are useful real semantic forms, but they should be understood as part of the current internal/compiler IR story rather than as uniformly surfaced authored constructs.

---

# 5. Major missing pieces

This is the core missing-work inventory.

## 5.1 Top-level `Surface -> Elab` item lowering is now real for value items, imports, and authored struct types

The reboot now has real frontend lowering for:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfStatic`
- `SurfImport`
- `SurfTypeDecl`
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfItemStatic`
- `SurfItemImport`
- `SurfItemType`
- `SurfModule`

What is still missing at this layer is not the existence of authored top-level items, but broader completion around:

- richer authored type-definition families beyond the current named-struct path
- broader package/module features beyond the current named-module import path
- clearer final surface rules for visibility/export semantics

---

## 5.2 Top-level `Elab -> Sem` item lowering now exists, but export/visibility semantics are still minimal

These current ASDL nodes now have real lowering:

- `ElabParam`
- `ElabFunc`
- `ElabExternFunc`
- `ElabConst`
- `ElabStatic`
- `ElabImport`
- `ElabTypeDecl`
- `ElabItemFunc`
- `ElabItemExtern`
- `ElabItemConst`
- `ElabItemStatic`
- `ElabItemImport`
- `ElabItemType`
- `ElabModule`

Current explicit limitation:

- `export func` vs plain `func` visibility distinction is now frozen but not yet implemented; currently all funcs lower as `SemFuncExport`

---

## 5.3 Param lowering is now implemented at the frontend layers

The current path now supports:

- `SurfParam -> ElabParam`
- `ElabParam -> SemParam`
- function arg env synthesis from params

What is still missing is richer authored parameter semantics beyond plain typed params, if the reboot later grows them.

---

## 5.4 Environment / namespace synthesis is now real but still intentionally narrow

Current authored `Surface -> Elab` now automatically builds real value/type/layout environments for:

- function argument env construction
- module/global value env construction for sibling items
- sibling function/const/extern/static name resolution
- module-local type/layout env construction from authored type items
- explicit named-module package imports through `import Demo`
- env-based qualified value path resolution through `SurfPathRef`

Still missing authored infrastructure includes:

- richer package/module features beyond the current named-module host API
- import aliasing / renaming if the reboot later wants it
- clearer documented shadowing/lookup rules for every namespace corner case

---

## 5.5 Qualified path references are now partially implemented

The frontend now supports qualified value lookup, and the reboot parser preserves authored dotted value syntax explicitly before elaboration resolves it.

Current value-name behavior:

- explicit already-disambiguated `SurfPathRef` still lowers through the real frontend
- authored dotted value syntax parses as `SurfExprDot(...)`
- if the head of a dotted chain resolves as a local/runtime value binding, lowering treats the chain as field projection
- otherwise lowering may resolve the chain as a qualified value binding

What currently resolves:

- env-provided qualified value references
- module-qualified global function refs through `ElabGlobalFunc(module_name, item_name, ...)`
- module-qualified global const refs through `ElabGlobalConst(module_name, item_name, ...)`
- explicit named-package imports that synthesize those env entries automatically for direct imports

Still missing:
- a broader documented namespace story beyond the current authored-dot local-head rule and qualified-only imports
- richer module/package features beyond the current named-module package API

So qualified value refs are no longer a blocker, and the reboot now has a real authored import path, but the broader package story can still grow.

---

## 5.6 `ElabEnv.types` is wired into named-type resolution, and current authored type env synthesis now exists

`ElabEnv` contains:

- `module_name`
- `values`
- `types`
- `layouts`

The current frontend now uses `types` for real `SurfTNamed` lowering.
Named type paths must resolve through explicit `ElabEnv.types` entries, with no lexical fallback.
This includes module-qualified type lookup when the env carries entries like `"Foo.Bar"`.

Current authored infrastructure now synthesizes those type envs from:

- local authored type items
- explicit named-module imports through the package front door

What is still missing is broader namespace/import surface beyond the current qualified import model.

---

## 5.7 `SurfTArray` type lowering now exists, but count elaboration is still limited

`lower_surface_to_elab.lua` now lowers:

- `SurfTArray`

by elaborating the count expression into the `ElabTArray(count, elem)` form.

Current explicit limitation:

- the current non-literal count subset is still intentionally small
- count refs currently work only through explicit index-typed global const bindings / sibling const env synthesis
- broader general const-eval forms are still not implemented here

So currently:

- array literals work
- array type syntax lowers through the real frontend path
- arithmetic array-count expressions like add/sub/mul are supported
- array counts can reference explicit index-typed const bindings by name/path
- sibling module consts are synthesized for count evaluation in top-level lowering
- broader general const/name-driven const eval is still pending

---

## 5.8 Reference/dereference typing now performs the real type transformation in `Surface -> Elab`

`SurfExprRef` and `SurfExprDeref` now lower through explicit typed handling rather than the generic unary helper path.

Implemented type transformations:

- `T -> ptr(T)` for ref
- `ptr(T) -> T` for deref

Current explicit limitation:

- full addressability/lvalue rules are still incomplete downstream, so not every syntactically typable `ref` use is yet machine-lowerable

So ref/deref are now real typed frontend features, but the full lvalue/addressability model is still partial.

---

## 5.9 Logical `and` / `or` now lower as short-circuit boolean control flow

Current lowering treats:

- `SurfExprAnd`
- `SurfExprOr`

as boolean-only operators in the frontend, and `Sem -> Back` lowers them through explicit CFG short-circuiting rather than strict bool bit-ops.

So today they are implemented as short-circuit boolean operations.

---

## 5.10 Named struct types/layouts are now authored and integrated on the current reboot path

The current frontend now supports an authored top-level path for:

- defining named struct types with `type Name = struct { ... }`
- synthesizing matching layout/type env entries
- using those named types in aggregate literals, field access, and qualified module paths
- carrying them through `Surface -> Elab -> Sem -> resolve_sem_layout`

Frozen extensions now implemented on the authored module path:

- enums: `type Color = enum { red, green, blue }` desugar to sibling const declarations
- tagged unions: `type Result = ok(i32) | err(i32)` desugar to a discriminant struct plus tag consts
- untagged unions: `type U = union { x: i32, y: f32 }` lower through explicit union type/layout items

Enum and tagged-union expansion happen in the parser/module item path before ordinary `Surface -> Elab`; untagged unions lower through the existing explicit `SurfUnion -> ElabUnion -> SemUnion` path.

---

## 5.11 Intrinsics are now real from authored source through `Sem -> Back` and the Rust backend

The ASDL now carries an explicit intrinsic family across the current closed path:

- `MoonliftSurface.SurfIntrinsic`
- `MoonliftElab.ElabIntrinsic`
- `MoonliftSem.SemIntrinsic`

Authored source can now parse and lower intrinsic calls through the normal frontend path into `SemExprIntrinsicCall`.

Current implemented scalar intrinsic family includes:

- integer-like scalar intrinsics:
  - `popcount`
  - `clz`
  - `ctz`
  - `rotl`
  - `rotr`
  - `bswap`
- float scalar intrinsics:
  - `fma`
  - `sqrt`
  - `floor`
  - `ceil`
  - `trunc_float`
  - `round`
- scalar numeric intrinsic:
  - `abs`
    - integer-like or float scalar
- control intrinsics:
  - `trap`
  - `assume`
    - currently stmt-position / void-form control intrinsics in `Sem -> Back`

### Frontend status
The reboot parser and frontend lowering now include intrinsic call parsing/binding and lower those calls through:

- `SurfExprIntrinsicCall`
- `ElabExprIntrinsicCall`
- `SemExprIntrinsicCall`

Intrinsic argument elaboration is phase-driven by `SurfIntrinsic`, so meaningful operand typing is explicit instead of parser-side magic. For example, rotate shift literals are elaborated to the value operand type, and `assume(...)` elaborates its condition as `bool` while remaining a void/control intrinsic.

Return-value elaboration is also now context typed by the function result type. `return 0` in an authored `-> u32` function elaborates as a `u32` integer literal, and that explicit result type is threaded through nested statement bodies such as `if`, `switch`, loops, and block-expression statement lists. Arithmetic/bitwise binary expression elaboration now uses the expected result type for the left operand, then uses the left operand type for the right operand, so `return 1 + 2` in a `-> u32` function elaborates the whole expression as `u32` without authored casts. `for` range bounds elaborate with the `index` type, so literal-bounded ranges such as `for i in 1..5` are naturally index-typed in `Surface -> Elab`.

### `Sem -> Back` status
`SemExprIntrinsicCall` lowers in value position for scalar-result intrinsics and in materialization position where that is meaningful.

### Rust backend / FFI replay status
The backend command vocabulary and Rust Cranelift host include lowering/replay for the intrinsic-backed `BackCmd` forms needed by the currently supported scalar intrinsic family.

Current explicit limitations:

- intrinsic lowering is still scalar-oriented
- intrinsics are not yet part of const evaluation
- there is not yet a richer user-facing intrinsic namespace/binding story beyond the current direct intrinsic call surface

---

## 5.12 Authored `assert(...)` is integrated through the closed path

Runtime assertions are now represented across the closed compiler path:

- `SurfAssert(cond)` from authored `assert(cond)` statements
- `ElabAssert(cond)` with `cond` elaborated as `bool`
- `SemStmtAssert(cond)` for semantic/backend lowering

`Sem -> Back` lowers assertions to trap-on-false control flow using the existing `BackCmdTrap` path.

---

## 5.13 Slice/view support is incomplete

This is one of the biggest backend/runtime gaps.

### Present in the ASDL
- `SurfTSlice`
- `ElabTSlice`
- `SemTSlice`
- `SemView`
- `SemIndexBaseView`
- `SemDomainView`
- `SemDomainZipEq`

### What is now implemented in lowering
`Sem -> Back` now has an explicit bounded-view lowering path with a real backend result shape for:

- slice/view indexing through `SemIndexBaseView`
- slice/view-backed `SemDomainView` lowering
- slice/view-backed `zip_eq` `over` loops
- explicit contiguous/strided/window/interleaved `SemView*` lowering
- slice/view mem sizing in key runtime cases
- slice/view stack-slot sizing for stack-resident values
- slice/view runtime copying for stack-resident values
- runtime equal-length checks for dynamic `zip_eq` traversal

Frozen target note:

- slices are intended as first-class descriptor values with canonical runtime meaning `data + len`
- views are intended as first-class descriptor values with canonical runtime meaning `data + len + stride`
- richer contiguous/strided/windowed/interleaved view forms normalize into that descriptor-oriented story

Still missing or still restricted:

- the finished authored-language story for constructing/passing slice/view values through the current descriptor ABI/value path
- a complete explicit low-level slice/view bounds/checking model beyond the current bounded-view lowering shape
- broader non-scalar load/call/result/materialization completion around slice/view values

So slices/views/domains no longer stop at array-only machine lowering: the backend now lowers bounded slice/view indexing and traversal directly, but the broader descriptor-value language/runtime story is still not complete.

---

## 5.14 Array indexing is not fully supported end-to-end

Arrays are partially implemented.

What exists:
- array literals
- array materialization into memory
- array copy logic
- array const-data init

What is now implemented:
- scalar array-value indexing all the way through `Sem -> Back`
- authored array literals materialized to memory, then indexed through explicit bounded-view/index address lowering

Current remaining restrictions:
- non-scalar array element results still require address/materialization context rather than direct value returns

So arrays are first-class for the current scalar indexed-value path, with broader non-scalar element ABI/materialization still part of the aggregate-value work.

---

## 5.15 Aggregate / non-scalar ABI is incomplete

Current backend/lowering is still heavily scalar-oriented.

The frozen target is now explicit:

- the language is single-result only
- multiple logical results use explicit struct values rather than anonymous tuple/multi-result forms
- slices/views are descriptor values
- aggregates lower through hidden-pointer/materialization conventions
- function values are intended to be first-class immutable callable values

Now implemented:
- non-scalar returns lower through an explicit hidden result pointer (`BackReturnSret`)
- non-scalar call arguments materialize to stack and pass an address
- non-scalar call results materialize directly into the destination address
- non-scalar function and extern signatures add the hidden result pointer as the first backend parameter
- non-scalar parameters are passed as addresses under the internal Back ABI
- function values have pointer-sized layout/storage
- direct function/extern binding reads lower to explicit backend function-address commands
- closure desugaring emits a canonical closure signature struct `{ fn, ctx }` plus per-expression context structs and helper functions
- closure parameters lower as pointers to canonical closure signature structs
- closure invocation sugar for local/parameter closure values lowers to `f.fn(f.ctx, args...)` and compiles through the authored front door

Still restricted:
- direct non-scalar load-as-value forms remain address/materialization-only
- public C-facing helper documentation for hidden result pointers/non-scalar parameters still needs polish

So the effective callable ABI now supports scalar/pointer direct values and non-scalar descriptor/aggregate values through explicit hidden-pointer/materialization paths.

---

## 5.16 Global mutation is not implemented

The global binding space is now split explicitly:

- `SemBindGlobalFunc`
- `SemBindGlobalConst`
- `SemBindGlobalStatic`

Runtime reads exist for statics, while consts are expected to fold or lower through constant-data initialization rather than ordinary runtime binding reads.

But global assignment/store lowering is explicitly not implemented in `Sem -> Back`.

So mutable globals are not currently a real feature.

---

## 5.17 Externs are semantically first-class, but implementation is still partial

The frozen closed-language target treats extern function items as function values in the same immutable callable family as ordinary functions.

Current implementation still mainly supports externs through call-target lowering.
Direct extern binding reads and broader extern-as-value flows are not complete yet.

So externs are intended to be first-class immutable callable values, but that semantic target is not yet fully implemented.

---

## 5.18 Addressability is still partial

The address-of / place model is explicit now, but still incomplete.

Frozen target note:

- `let`/params/loop carries/loop indices are value bindings first
- `var` is the explicit mutable-cell binding form
- address-of applies to real places rooted in locals, params, loop carries/indices, statics, and projections/dereferences/indexes built from those roots
- address-of does not apply to pure compile-time `const` values or arbitrary temporary rvalues

Implemented now:
- address of mutable locals through canonical local-cell stack slots
- address of static globals through `SemBindGlobalStatic`
- address of projected/deref/index places built from those addressable bases
- a real function-scoped `SemResidencePlan` phase boundary for storage/addressability classification
- an explicit machine-facing `SemBackBinding` ASDL result type that classifies immutable locals/params/loop carries/loop indices into pure-vs-stored forms for `Sem -> Back`
- place-root bindings (`SemPlaceBinding(...)`) now force stack residence in that plan instead of relying only on default-by-type answers

Still missing or restricted:
- the broader not-yet-finished non-scalar/value-model path
- address of pure const globals (`SemBindGlobalConst`)
- address of many computed values except where explicit materialization already exists
- a fully general implementation of the frozen place/addressability model across all intended place categories

So references/places exist in the IR, storage/addressability now has both an explicit function-scoped residence plan and an explicit machine-facing `SemBackBinding` classification consumed by `Sem -> Back`, but the broader non-scalar/general-place story is still incomplete.

---

## 5.19 Const evaluation is very limited

Current const-data lowering supports:

Normative subset document:
- `moonlift/CONSTANT_EXPRESSION_SUBSET.md`


- scalar literal constants
- bool literals
- nil as zero-init
- named aggregate literal const data
- array literal const data
- sibling const references within the current module through explicit `SemConstEnv`
- computed scalar constant evaluation for:
  - neg / logical-not / bit-not
  - add / sub / mul / div / rem
  - eq / ne / lt / le / gt / ge
  - bool `and` / `or`
  - bitwise binary ops and shifts
  - scalar casts / trunc / zext / sext / bitcast / saturating cast
  - pure `if` / `select`
- constant `block` / `switch` expressions through explicit `SemConstLocalEnv`
  and `SemConstStmtResult`
- constant loop evaluation through explicit const statement-flow and local-env threading for:
  - `while` stmt loops
  - `while` expr loops
  - `over range(...)`
  - `over range(start, stop)`
- constant statement execution for the currently supported subset:
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `if`
  - `switch`
  - `assert`
  - loop stmt
  - loop-local `break` / `continue`
- aggregate field projection from constant aggregates
- array index projection from constant arrays
- recursive aggregate/array constant materialization through the evaluator

In addition, the type-level array-count evaluator now supports a small explicit subset:

- integer literals
- add/sub/mul over count expressions
- references to explicit index-typed global const bindings through `ElabConstEnv`
- sibling const references in `ElabModule` count lowering

General value-level const evaluation still explicitly does not support several forms, including:

- address-taking / dereference / loads
- intrinsic calls
- normal calls
- `over bounded value` / `zip_eq` constant loops
- store statements in constant blocks
- full multi-module/future-final const-expression coverage beyond the documented current subset
- a complete multi-module const-reference story

So constant evaluation is no longer literal-only, but it is still incomplete.

---

## 5.20 Floating remainder is removed from the language

`frem` is removed. `%` is integer-only.

- `BackCmdFrem` is removed from the backend ASDL
- Rust backend `frem` error stub is removed

---

## 5.21 A bootstrap parser / text frontend now exists and already covers most of the current closed reboot surface

There is now an initial reboot parser/front-end in:

- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/test_parse_smoke.lua`

It already constructs `MoonliftSurface` ASDL values directly for a substantial bootstrap/front-door surface, including:

- top-level items:
  - `func`
  - `extern func`
  - `const`
  - `static`
  - `import`
  - `type ... = struct { ... }`
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
  - calls / field / index
  - field-based aggregate literals
  - array literals via `[]T { ... }`
  - explicit `select(cond, a, b)`
  - `if` expr
  - `switch` expr
  - block expr
  - canonical loop expr
- note:
  - statement loop syntax is now `for ... in ... do ... end` / `while ... with ... do ... end`; carries survive after loop and `next name = expr` is inline in the body
  - the old typed `loop (...) -> T while/over ... next ... end -> expr` path still exists as legacy expression-loop infrastructure
- statements:
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `if`
  - `switch`
  - `return`
  - `break` (bare only, no `break expr`)
  - `continue`
  - `next` (loop carry recurrence)
  - loop stmt (`for`, `while`)
- public helper facade:
  - `moonlift/lua/moonlift/source.lua`
  - `moonlift/lua/moonlift/source_spans.lua`
  - parse helpers
  - parse-with-spans helpers
  - try-parse helpers with structured diagnostics
  - canonical single-module front-door helpers:
    - `pipeline(...)`
    - `back(...)`
    - `compile(...)`
  - named-package front-door helpers:
    - `pipeline_package(...)`
    - `back_package(...)`
    - `compile_package(...)`
  - try-lower / try-sem / try-resolve helpers for single-module source text
  - canonical `try_pipeline` / `try_back` / `try_compile` helpers for single-module source text
  - package `try_pipeline_package` / `try_back_package` / `try_compile_package` helpers
  - `parse -> Surface -> Elab`
  - `parse -> Surface -> Elab -> Sem`
- current source spans are stored in a parallel **path-keyed** span index rather than a naive `node -> span` map, because interned `Surface` values do not preserve occurrence identity by object identity alone
- current public source helpers now catch parse/lower/sem/layout/resolve/back/compile failures across the `try_*` entrypoints, strip raw Lua file/line noise from user-facing messages, and attach structural source paths, source spans, and package module names when that context is available

But it is still a bootstrap/front-door rather than the final frozen authored language.

Still missing from the reboot authored front door:

- complete grammar coverage for everything already present in `Surface`
- frozen authored syntax for currently open `Surface` areas such as `view`
- richer diagnostics and source span plumbing through later compiler layers
- hosted fragment / quote syntax

So the reboot is no longer parser-less, and it now has a real authored source front door, but it is not yet the final complete authored text language.

---

## 5.22 A bootstrap top-level compile facade now exists

The pipeline pieces are no longer only manual / semi-manual.
`moonlift/lua/moonlift/source.lua` now exposes real authored-source helpers for:

- `source text -> Surface`
- `source text -> Elab`
- `source text -> Sem`
- `source text -> resolved Sem + synthesized layout env`
- `source text -> BackProgram`
- `source text -> compiled artifact` via canonical `compile(...)`
- named source package/module sets -> compiled artifact via `compile_package(...)`

The closed compile path used by those helpers is the real reboot path:

- parse -> `Surface`
- `Surface -> Elab`
- `Elab -> Sem`
- synthesize/resolve layout
- `Sem -> Back`
- JIT compile

What is still missing here is not the existence of a compile facade, but any additional later-layer diagnostic polish beyond the now-cleaner canonical front door.

---

## 5.23 Current codegen-shape limitations exposed by `peek`

Recent direct machine-code inspection of small benchmark kernels shows several real remaining design/codegen gaps:

- constant-key `switch` on `bool` / integral scalars / `index` now lowers through preserved `BackCmdSwitchInt` structure; dense cases can become `br_table`/jump-table-style code, while sparse cases stay preserved long enough for Cranelift to choose a sparse compare tree instead of Moonlift pre-collapsing them
- source elaboration now threads the switch-value type into arm-key elaboration, so authored integer literals in `u*` / `i*` / `index` switches are typed as the intended scalar key kind instead of defaulting through unrelated literal fallback
- switch-arm classification is now explicit at the backend boundary (`SemBackSwitch*`), so `Sem -> Back` no longer rediscovers const-vs-expr switch shape by probing raw `SemSwitch*Arm` expressions during lowering
- plain scalar `if` chooses currently lower as branch CFG, not as an explicit select/branchless choice form
- scalar function arguments now stay as backend entry values by default, and function-scoped residence planning plus explicit `SemBackBinding` classification materialize storage only when addressability requires it; the same policy now also covers pure scalar loop carries/indices, while general-place/non-scalar cases are still less complete
- authored unsigned / `index` benchmarking is still somewhat awkward in places because type-directed integer literal elaboration is still not uniformly strong enough across every source context, though typed const globals now fold cleanly to immediates through the current backend path

So the current backend is already useful for real codegen observation, and the switch-preservation situation is materially better than before. Recent const-folding cleanup also means typed numeric / `index` const globals no longer have to survive as backend-visible const-object loads in simple scalar kernels. Important machine-shape outcomes are still limited by implementation gaps relative to the now-frozen closed-language semantics—especially explicit `select` preservation and the still-incomplete storage/addressability/value-model work.

One recently-fixed backend-host issue is worth calling out explicitly:

- simple stmt `if`, stmt `switch`, loop-body stmt `if`, linear body-local `let ...; next ... = out`, and bounded nested `if`-expression loop updates now compile cleanly through the current LuaJIT FFI replay path instead of dropping repeated identical join jumps during replay

---

## 5.24 Back/Cranelift-facing design decisions are now more explicit even where implementation still lags

Recent direct inspection of the vendored Cranelift sources in `third_party/wasmtime/cranelift/` was used to answer several previously-open Moonlift design questions.

The current frozen direction is now:

- the current `BackCmd` set is **not** considered sufficient for the finished language
- explicit bulk copy/fill commands should exist eventually rather than forcing all aggregate/data movement through ad hoc scalar sequences
- pure scalar choose should continue to preserve explicit `BackCmdSelect` structure when the language means choose/dataflow rather than CFG `if`
- scalar casts/conversions stay as explicit `Back` commands, while aggregate/descriptor conversions should lower earlier into explicit materialization/copy plans
- generic slice/view runtime primitives are **not** intended as a second `Back` mini-IR; slice/view descriptor operations should mostly decompose before `Back`
- if a richer persistent session/module model is added later, it should extend the current artifact model rather than replace it

This is a design-freeze/status point, not a claim that the missing commands or runtime/value-model work are already implemented.

## 5.25 `MoonliftMeta` ASDL exists; quote/open-code operations are not implemented yet

The metaprogramming layer discussed in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

now has a coherent ASDL vocabulary in `moonlift/lua/moonlift/asdl.lua`:

- `MoonliftMeta`
- open type/domain/expr/stmt/loop families
- fragment nodes
- function/const/static/type/item/module nodes
- params/imports/open-set/slot nodes
- slot value and slot binding nodes

There is also an initial builder/helper API in:

- `moonlift/lua/moonlift/meta.lua`

That helper API constructs canonical `MoonliftMeta` ASDL values and installs small convenience methods on Meta slots, symbols, and fragments. It covers the current ASDL nouns, including type/value constructors, slots, imports, params, open sets, bindings, places, domains, loops, exprs, stmts, fragments, funcs, consts, statics, type declarations, items, modules, and slot bindings. These helpers are construction conveniences only.

There is also an initial source quote frontend in:

- `moonlift/lua/moonlift/meta_source.lua`

That API parses ordinary Moonlift source snippets against explicit Meta params/open sets, lowers them through `Surface -> Elab`, and converts them into `MoonliftMeta` through explicit source-environment ASDL mappings. It currently supports expr fragments, single-statement / statement-list region fragments, function items, const items, static items, and modules. It also supports `$name` quote holes as syntax for explicit Meta slots/open-code holes; the hole targets remain ASDL values.

There are also initial query/validation/rewrite APIs in:

- `moonlift/lua/moonlift/meta_query.lua`
- `moonlift/lua/moonlift/meta_validate.lua`
- `moonlift/lua/moonlift/rewrite_meta.lua`

Those APIs provide PVM-backed structural walking to flat `MetaFact` values, explicit `MetaValidationReport` closedness checks, and ASDL-visible `MetaRewriteSet` rewrite rules for identity-based type/binding/place/domain/expr/stmt/item rewrites.

There is also an initial structural expansion API in:

- `moonlift/lua/moonlift/expand_meta.lua`

That API provides `pvm.phase(...)` boundaries for slot filling, param substitution, fragment expansion, item/module splice expansion, and deterministic local-id rebasing via explicit `use_id` fields and `MetaExpandEnv`.

There is also an initial closure/sealing API in:

- `moonlift/lua/moonlift/seal_meta_to_elab.lua`

That API provides `pvm.phase(...)` boundaries for sealing closed Meta values into ordinary `MoonliftElab` values across the current Meta families: types, intrinsics, bindings, places, index bases, domains, loops, exprs, stmts, funcs, extern funcs, consts, statics, imports, type declarations, items, modules, and expr/region fragment bodies. It rejects unfilled slots and unexpanded fragment/module splices with explicit errors.

Still missing / intentionally deferred:

- hosted parser/session integration for non-string quote literals
- richer source-mapped diagnostics for quote holes and rewrites
- alpha normalization / canonicalization beyond deterministic `use_id` rebasing

So the meta side is now **ASDL plus builder construction helpers plus source quote elaboration plus query/validation/rewrite tooling plus structural expansion plus initial closed Meta -> Elab sealing**.

---

# 6. What is partly implemented but still incomplete

## 6.1 Modules/functions/items and authored struct type items now exist, but the broader language story is still incomplete

This distinction still matters.

### Implemented today
- `SurfFunc` / `ElabFunc` / `SemFuncExport`
- `SurfExternFunc` / `ElabExternFunc` / `SemExternFunc`
- `SurfConst` / `ElabConst` / `SemConst`
- `SurfStatic` / `ElabStatic` / `SemStatic`
- `SurfImport` / `ElabImport` / `SemImport`
- `SurfStruct` / `ElabStruct` / `SemStruct`
- `SurfItem*` / `ElabItem*` / `SemItem*`
- `SurfModule` / `ElabModule` / `SemModule`
- named-module package imports / qualified refs/types through the source helpers
- their downstream `Sem -> Back` lowering

### Still missing today
- closure-valued returns through the broader aggregate return ABI
- broader non-scalar ABI completion for aggregate/descriptor values

---

## 6.2 Field and layout machinery is integrated for the current named-struct path, but broader completion remains

Current real support includes:
- authored top-level struct type declarations
- automatic layout synthesis from authored program items
- named layout env
- field-name resolution to offset
- named aggregate copying/materialization
- field-address and field-load support downstream

But current real missing parts include:
- broader type/layout families beyond the current struct path
- finalizing which unresolved forms may survive past layout resolution
- fuller non-scalar / view-driven layout and value-model completion

---

## 6.3 Loops are strong on `for`, `while`, `range`, and bounded view/zip domains

Current real support:
- statement `for i in 0..n do ... end` and `for i in start..stop do ... end`
- statement `for i in domain with acc: T = init do ... next acc = expr ... end`
- statement `while cond with i: T = init do ... next i = expr ... end`
- old typed `loop (...) while/over ... next ... end -> expr` expression-loop path still exists as legacy infrastructure
- range domains, array/slice/view value domains, and `zip_eq(...)` domains with runtime equal-length checks
- loop carries survive after statement loops and are exposed as ordinary bindings after the loop
- bare `break` preserves the current carry values

Frozen syntax/semantics:
- `do` is mandatory for new `for`/`while` statement loops
- `next name = expr` is inline in the loop body, not a separate `next` block
- no `end -> expr` projection for new statement loops, no `break expr`
- carries are the loop's natural "output" per Cranelift's block-param dataflow

---

# 7. Rust/FFI-specific explicit backend facts

These are concrete backend facts to keep in mind when comparing the frozen semantic target to the current backend layer.

## 7.1 `BackCmdFrem` is removed

Floating-point remainder is not part of the closed language.

## 7.2 Raw pointer API is intentionally single-result

Rust rejects multi-result extern declarations for the raw pointer API.
That now matches the frozen single-result language/ABI target and is not itself a semantic gap.

## 7.3 Direct artifact API is intentionally single-result oriented

Direct function-pointer retrieval is limited to the current single-result shape.
That now matches the frozen single-result language/ABI target; the remaining backend gap is completing aggregate/descriptor conventions around that target.

These backend facts are separate from the frontend/value-model gaps above.

---

# 8. Current practical progress read

## 8.1 The strongest completed area

The strongest completed area is:

- local expression/statement/loop/domain lowering
- top-level value-item lowering through `Surface -> Elab -> Sem`
- sibling value env synthesis for funcs/consts/externs
- semantic layout resolution
- scalar/backend CFG lowering
- function/module codegen

That is a real compiler middle and backend.

## 8.2 The biggest missing authored-language area

The biggest missing authored-language area is now:

- implementing the newly frozen loop syntax (`for ... in` / `while ... with`)
- implementing `export func` visibility
- implementing enum/tagged-union/untagged-union desugaring
- completing closure-valued returns under the aggregate return ABI
- implementing view construction primitives
- implementing type-directed integer literal elaboration
- richer diagnostics / source mapping through later compiler layers

## 8.3 The biggest missing runtime/value-model areas

The biggest incomplete runtime/value-model areas are:

- slices/views
- fuller const evaluation / immediate propagation
- non-scalar ABI/value support
- storage/addressability classification cleanup
- code-shape preservation for switch/select-sensitive lowering

The repo now also has a ratcheting semantic-dispatch audit for active semantic/backend compiler files:

- `moonlift/test_semantic_dispatch_audit.lua`
- `moonlift/semantic_dispatch_audit_baseline.txt`

The audited active semantic/backend files are currently at **zero baseline findings**.
That means the previously-inventoried raw `.kind` / raw helper type-classification debt in those audited files has been paid down, and new sites should now fail as immediate regressions.

There is also now a small scalar-only Terra comparison benchmark track in:

- `moonlift/benchmarks/README.md`
- `moonlift/benchmarks/bench_moonlift.lua`
- `moonlift/benchmarks/bench_terra.t`
- `moonlift/benchmarks/bench_moonlift_shapes.lua`
- `moonlift/benchmarks/FINDINGS.md`
- `moonlift/benchmarks/run_vs_terra.sh`

This benchmark path intentionally exercises the current closed `Surface -> Elab -> Sem -> Back -> Artifact` compiler path on scalar kernels only. The separate `bench_moonlift_shapes.lua` track compares generic scalar formulations against explicit Moonlift source/code-shape constructs such as range-domain `for`, `select`, and scalar intrinsics. These benchmarks should not be treated as aggregate/slice/view/value-model coverage until those runtime features are implemented end-to-end.

There is also an initial ASDL-backed vectorization fact-gathering prototype in:

- `moonlift/lua/moonlift/vector_facts.lua`
- `moonlift/test_vector_facts.lua`

This now defines the coherent `MoonliftVec` vocabulary from `VECTORIZATION_ASDL_REDESIGN.md`: expression ids, loop ids, target facts, expression graphs, range facts, counted domains, inductions, reductions, proofs, explicit loop decisions, scalar/vector/chunked loop shapes, and the `VecModule` root. The current prototype detects simple `for i in range with acc ... next acc = acc + lane_expr` loops recursively through PVM phases, records the term as `VecLoopFacts`, chooses `VecLoopDecision` values instead of old hand-written plan variants, and can prove the initial bounded-narrowing case when the reduction term has an explicit bitand bound such as `& 1023`.

The `MoonliftBack` layer also now has an initial explicit vector command slice:

- `BackVec(elem, lanes)`
- `BackCmdVecSplat`
- `BackCmdVecIadd`
- `BackCmdVecImul`
- `BackCmdVecBand`
- `BackCmdVecLoad`
- `BackCmdVecStore`
- `BackCmdVecInsertLane`
- `BackCmdVecExtractLane`
- `BackCmdAppendVecBlockParam`

Those commands replay through the LuaJIT FFI bridge into Rust and produce Cranelift vector IR in `moonlift/test_back_vectors.lua`.

There is now also an initial `MoonliftVec.VecLoopDecision` / `VecModule -> BackProgram` lowering in:

- `moonlift/lua/moonlift/vector_to_back.lua`
- `moonlift/test_vector_to_back.lua`

Those lowerings consume the chosen vector loop shape and emit vectorized main loops, vector accumulator block params, explicit unrolled vector accumulators, horizontal lane extraction/reduction, scalar tail loops, and for the bounded-narrow case a chunked `i32x4` accumulator that widens extracted lane sums back to `index`. Both the ordinary/unrolled add-reduction path and the bounded chunked-narrow path now materialize real `VecBlock` / `VecCmd` skeletons before mechanical lowering to `BackProgram`. The ordinary vector skeleton also now carries initial contiguous view-backed memory facts through to backend vector memory commands: `VecMemoryAccess` / `VecExprLoad` / `VecCmdLoad` lower to `BackCmdVecLoad`, and `VecStoreFact` / `VecCmdStore` lower to `BackCmdVecStore`, currently for pointer-backed contiguous views. Store loops now also produce explicit `VecDependenceFact` values: in-place same-base/same-lane load-store maps can be proven with `VecNoDependence`, while unknown alias pairs remain `VecDependenceUnknown` and choose scalar fallback instead of assuming noalias. `moonlift/benchmarks/run_vector_sum_vs_terra.sh` currently validates the arithmetic path with measured speedups over scalar Moonlift: base `i64x2`, unrolled `i64x2`, and chunked bounded `i32x4`. The fastest current path is still slower than Terra/LLVM's wider AVX-512 vectorized code, but the gap is now represented as explicit ASDL facts/proofs/decisions and vector block skeletons rather than hidden backend recovery.

## 8.4 The biggest missing future-architecture area

The biggest planned-but-not-operational area is the open-code/meta layer described in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

The `MoonliftMeta` ASDL vocabulary, initial builder construction helpers, source quote elaboration, structural query/validation/rewrite tooling, structural expansion/slot-filling/splice expansion, and initial closed Meta -> Elab sealing exist. Hosted parser/session integration and alpha normalization remain deferred.

And the deferred future host/parser integration strategy described in:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 9. Short summary

> Moonlift now has a frozen language design with `for ... in` / `while ... with` loops, closures as surface sugar, enum/union desugaring, `export func` visibility, and view construction primitives. The existing implementation has a real parser, real top-level item lowering, qualified module imports, authored struct type/layout synthesis, a layout-resolution pass, canonical compile helpers, new statement-loop syntax with surviving carries, and a substantial scalar backend. Remaining implementation work includes: expression-loop syntax cleanup, full enum/union/closure hardening, view construction completion, array-value indexing, function-value storage, cross-module consts, const intrinsics, and operational `Meta` construction/normalization/sealing over the now-present `MoonliftMeta` ASDL layer.

And if compressed even further:

- **language design:** frozen
- **scalar backend:** real
- **new loop/type/closure syntax:** statement loops are implemented; closure/type syntax exists but still needs hardening
- **slice/view/value-model:** still incomplete
- **meta layer:** ASDL vocabulary, builder helpers, source quote elaboration, structural query/validation/rewrite tooling, structural expansion/slot filling/splice expansion, and initial closed Meta -> Elab sealing exist; hosted parser integration and alpha normalization are still deferred

---

# 10. Related design docs

This file is intentionally only about implementation coverage.

For the future open-code / metaprogramming layer:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future LuaJIT-hosted / parser-hosted integration strategy:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
