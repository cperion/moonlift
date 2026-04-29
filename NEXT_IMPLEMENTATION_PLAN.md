# Moonlift Next Implementation Plan — View/Contract/Proof Compiler Pass

This plan describes the next coherent Moonlift implementation pass. It is meant
as a **single unified ASDL-first compiler update**, not a sequence of unrelated
patches.

The goal is to move Moonlift from:

```text
jump-first typed control + executable scalar/SIMD kernels with explicit raw-pointer assumptions
```

to:

```text
jump-first typed control + views/contracts + proof-backed memory safety + executable scalar/SIMD kernels
```

The core principle remains:

```text
if it affects compiler behavior, it must be represented as ASDL data
```

No meaningful safety, aliasing, bounds, vectorization, view ABI, or contract
semantics should be hidden in helper switches, comments, side tables, or backend
peepholes.

---

## 0. Current baseline

Current working pipeline:

```text
Moonlift source text
  -> parse.lua
  -> Moon2Parse.ParseResult
  -> Moon2Tree.Module(ModuleSurface)
  -> tree_typecheck.lua
  -> Moon2Tree.Module(ModuleTyped)
  -> tree_control_facts.lua
  -> vec_loop_facts.lua
  -> vec_kernel_plan.lua
  -> vec_kernel_safety.lua
  -> vec_kernel_to_back.lua
  -> Moon2Back.BackProgram
  -> back_jit.lua
  -> Rust / Cranelift
```

Current executable vector shapes:

```text
i32 -> i32x4
u32 -> u32x4
i64 -> i64x2
u64 -> u64x2
```

Current vector safety status:

```text
raw pointer bounds: explicit assumptions
raw pointer aliasing: explicit assumptions, with same-index in-place proofs where recognized
view-backed bounds: ASDL exists partially, but source/backend/proof path is incomplete
```

Current vector kernel ASDL status:

```text
VecKernelCore
VecKernelMemoryUse
VecKernelSafetyInput
VecKernelSafetyDecision
VecKernelPlan
VecKernelReductionBin
VecKernelMaskExpr
VecKernelExprSelect
```

Integer vector compare/select is now implemented end-to-end for the current 128-bit executable shapes. Source `select(cond, then_expr, else_expr)` parses to `ExprSelect`; vector planning recognizes comparison masks and `and`/`or`/`not` mask logic through `VecKernelMaskExpr`; safety traverses mask/select operands; backend lowering emits explicit vector compare/select/mask commands plus scalar-tail selects.

This pass should preserve that architecture and make safety proofs real.

---

## 1. Target outcome

By the end of this pass, Moonlift should support source like:

```moonlift
export func sum_view_i32(xs: view(i32)) -> i32
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(xs) then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

and:

```moonlift
export func add_noalias_i32(
    noalias dst: ptr(i32),
    readonly a: ptr(i32),
    readonly b: ptr(i32),
    n: i32,
) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end
```

The compiler should produce explicit proof-backed vector safety:

```text
VecKernelSafetyProven(...)
```

where contracts/views prove bounds and aliasing, and explicit assumptions only
where the source program actually leaves safety as a caller obligation.

---

## 2. PVM design note

### Source ASDL

Existing types affected:

- `Moon2Type.Type`
  - `TView(elem)` already exists and remains the typed view type.
- `Moon2Tree.View`
  - Existing `ViewFromExpr`, `ViewContiguous`, `ViewStrided`, `ViewWindow`, etc.
    become executable/source-reachable, not dormant structure.
- `Moon2Tree.Expr`
  - Needs explicit length expression/intrinsic form.
- `Moon2Tree.Func`
  - Needs contract-bearing function shape or attached contract facts.
- `Moon2Vec.*`
  - Memory safety facts/proofs become the consumer of contracts/views.

New types needed:

```text
Moon2Tree.ParamModifier
Moon2Tree.FuncContract
Moon2Tree.ContractExpr or ContractPredicate
Moon2Tree.ContractFact
Moon2Tree.ExprLen or Moon2Core.IntrinsicLen
Moon2Tree.ViewDescriptorFact
Moon2Vec.VecBoundsProofInput
Moon2Vec.VecAliasProofInput
Moon2Vec.VecMemoryContractFact
Moon2Vec.VecProofBounds
Moon2Vec.VecProofNoAlias
```

User-authored fields:

- Parameter modifiers:
  - `noalias`
  - `readonly`
  - `writeonly`
- Function-level contracts:
  - `requires bounds(ptr, len)`
  - `requires disjoint(a, b)`
  - possibly `requires same_len(a, b)` for view families later
- View constructors:
  - `view(ptr, len)`
  - later `view(ptr, len, stride)`
- View length:
  - `len(xs)`

Derived fields excluded:

- resolved bindings in contracts
- proven bounds facts
- proven noalias facts
- ABI-expanded view descriptor fields
- vector safety decisions
- lowered backend values

These must be produced by phases, not parsed as final facts.

### Events / Apply

No mutable compiler state events are required for this pass. The design remains
functional phase lowering.

Event variants needed:

```text
none for compiler state mutation
```

Pure state transition:

```text
source module
  -> typed module with binding-backed contracts
  -> fact streams
  -> proof decisions
  -> backend commands
```

State fields changed through `pvm.with`:

- Typed function nodes may be rebuilt with typed contract fields.
- Expressions are rebuilt from surface to typed headers.
- Index bases are rebuilt as typed view/pointer bases.

### Phase boundaries

#### Boundary: parse source contracts/views

Question answered:

```text
What source syntax did the user write?
```

Input type:

```text
source text
```

Output:

```text
ModuleSurface with surface contracts, param modifiers, ExprCall/ExprLen/View constructors
ParseIssue*
```

Cache key:

```text
source text identity / parser input
```

Explicit extra args:

```text
none
```

#### Boundary: typecheck contracts/views

Question answered:

```text
Which bindings and types do contract/view expressions refer to?
```

Input:

```text
ModuleSurface
```

Output:

```text
ModuleTyped
TypeIssue*
```

Cache key:

```text
ASDL node identity
```

Explicit extra args:

```text
TypeCheckEnv
```

#### Boundary: contract fact gathering

Question answered:

```text
What memory claims did the source program make, in binding-backed form?
```

Input:

```text
Func typed contracts + params
```

Output:

```text
ContractFact*
MemoryContractFact*
```

Cache key:

```text
Func node identity
```

#### Boundary: view ABI lowering

Question answered:

```text
How is a view represented in backend values?
```

Input:

```text
TView / View / ExprLen / IndexBaseView
```

Output:

```text
BackViewLowering
BackExprLowering
BackAddrLowering
```

Cache key:

```text
ASDL expression/view identity + explicit backend environment
```

#### Boundary: vector bounds/alias proof

Question answered:

```text
Can each vector memory use be proven safe for [0, stop)?
```

Input:

```text
VecLoopFacts
VecKernelCore
ContractFact*
View facts
```

Output:

```text
VecKernelSafetyDecision
```

Cache key:

```text
VecKernelSafetyInput identity
```

### Field classification

Code-shaping fields:

- `TView(elem)`
- `ViewContiguous(data, elem, len)`
- `ViewStrided(data, elem, len, stride)`
- `ExprLen(value)` or equivalent intrinsic target
- `ParamModifierNoAlias`
- `ParamModifierReadonly`
- `ParamModifierWriteonly`
- `ContractBounds(ptr/view, len)`
- `ContractDisjoint(a, b)`
- `VecKernelBoundsProven`
- `VecKernelAliasProven`

Payload fields:

- source parameter names
- literal lengths
- reason strings in proof/reject nodes
- source spans if/when diagnostics are added

Dead fields to remove:

- Any helper-only boolean flags for noalias/bounds.
- Any string-only semantic tags where ASDL variants should exist.
- Any backend-only hidden assumption tables.

### Execution

Flat fact / command type:

```text
Moon2Back.Cmd
```

Push/pop stack state:

```text
none beyond existing backend block/value environment
```

Final loop behavior:

- View indexing lowers to pointer arithmetic using view descriptor data.
- `len(view)` lowers to descriptor length extraction.
- Vector kernels lower exactly as today, but their safety is proof-backed when
  source contracts/views provide proof inputs.

### Diagnostics

Expected `pvm.report` reuse:

- Typechecking contracts should reuse typed expression/name resolution heavily.
- Vector safety should cache by `VecKernelSafetyInput`.
- View lowering should cache by view expression and backend env identity.

Possible cache failure modes:

- Opaque Lua tables in contract environments.
- Safety phases capturing mutable helper state.
- String keys standing in for binding identity.
- Recomputing view descriptor lowering with hidden side effects.

Avoid all of these by using ASDL values and explicit phase args.

---

## 3. ASDL checklist

### 3.1 Parameter modifiers

- [ ] Add `ParamModifier` ASDL.

Proposed shape:

```text
ParamModifier = ParamNoAlias
              | ParamReadonly
              | ParamWriteonly
```

- [ ] Extend function parameter representation or add parallel param metadata.

Preferred shape if changing params directly is acceptable:

```text
FuncParam = (string name, Moon2Type.Type ty, Moon2Tree.ParamModifier* modifiers) unique
```

Alternative compatibility shape:

```text
ParamContract = ParamContract(Moon2Bind.Binding param, ParamModifier* modifiers) unique
```

- [ ] Update every constructor/consumer affected by parameter representation.
- [ ] Keep parser output surface-level; binding-backed param contracts are typed phase output.

### 3.2 Function contracts

- [x] Add source contract ASDL.

Proposed shape:

```text
FuncContract = ContractBounds(Moon2Tree.Expr base, Moon2Tree.Expr len) unique
             | ContractDisjoint(Moon2Tree.Expr a, Moon2Tree.Expr b) unique
             | ContractSameLen(Moon2Tree.Expr a, Moon2Tree.Expr b) unique
             | ContractReadonly(Moon2Tree.Expr base) unique
             | ContractWriteonly(Moon2Tree.Expr base) unique
```

- [x] Add typed/binding-backed contract facts, including `same_len` for view families.

```text
ContractFact = ContractFactBounds(Moon2Bind.Binding base, Moon2Bind.Binding len) unique
             | ContractFactDisjoint(Moon2Bind.Binding a, Moon2Bind.Binding b) unique
             | ContractFactSameLen(Moon2Bind.Binding a, Moon2Bind.Binding b) unique
             | ContractFactReadonly(Moon2Bind.Binding base) unique
             | ContractFactWriteonly(Moon2Bind.Binding base) unique
             | ContractFactRejected(Moon2Tree.TypeIssue issue) unique
```

- [x] Attach contracts to `Func` or add a `FuncContractSet` facet.
- [x] Avoid opaque `ctx.contracts` tables as semantic carriers.

### 3.3 Length expression

- [x] Add explicit length expression ASDL.

Preferred:

```text
ExprLen(Moon2Tree.ExprHeader h, Moon2Tree.Expr value) unique
```

Alternative:

```text
IntrinsicLen
```

- [x] Type rule:

```text
len(view(T)) -> index
```

The temporary executable `i32` length policy has been replaced: `len(view)`, view descriptor lengths, view-window starts/lengths, and vector loop counters for `len(view)` stops now use `index`. Pointer kernels with authored `i32` stop bindings still keep `i32` vector counters.

- [x] Lowering rule:

```text
len(view descriptor) -> descriptor.len
```

### 3.4 View descriptor ABI

- [x] Add explicit function/view ABI plans (`FuncAbiPlan`, `AbiParamView`, `AbiParamScalar`, `AbiResultPlan`).

```text
ViewAbi = ViewAbiContiguous(Moon2Back.BackScalar ptr_scalar, Moon2Back.BackScalar len_scalar) unique
        | ViewAbiStrided(Moon2Back.BackScalar ptr_scalar, Moon2Back.BackScalar len_scalar, Moon2Back.BackScalar stride_scalar) unique
```

- [x] Decide initial executable function ABI for `TView(elem)`.

Current initial executable ABI:

```text
view(T) parameter expands to:
  data: ptr
  len: i32
```

Future strided ABI:

```text
view(T) parameter expands to:
  data: ptr
  len: index
  stride: index
```

- [ ] Represent ABI expansion as data, not ad hoc parameter insertion.

### 3.5 Vector proof input ASDL

- [ ] Add vector memory contract facts.

```text
VecMemoryContractFact = VecContractBounds(Moon2Bind.Binding base, Moon2Bind.Binding len, Moon2Vec.VecProof proof) unique
                      | VecContractDisjoint(Moon2Bind.Binding a, Moon2Bind.Binding b, Moon2Vec.VecProof proof) unique
                      | VecContractReadonly(Moon2Bind.Binding base, Moon2Vec.VecProof proof) unique
                      | VecContractWriteonly(Moon2Bind.Binding base, Moon2Vec.VecProof proof) unique
```

- [ ] Add explicit proof variants if current `VecProofKernelSafety` is too vague.

```text
VecProofBounds(Moon2Bind.Binding base, Moon2Bind.Binding stop, string reason) unique
VecProofNoAlias(Moon2Bind.Binding a, Moon2Bind.Binding b, string reason) unique
VecProofViewLength(Moon2Bind.Binding view, Moon2Bind.Binding stop, string reason) unique
```

- [x] Keep `VecAssumption` variants for raw pointer fallback.
- [x] Make `VecKernelSafetyDecision` carry both proofs and assumptions explicitly.

---

## 4. Parser checklist

Parser remains fast and dumb. It should emit source shape only.

### 4.1 Parameter modifiers

- [x] Lex keywords:

```text
noalias
readonly
writeonly
requires
bounds
disjoint
len
```

- [x] Parse parameter modifiers:

```moonlift
noalias dst: ptr(i32)
readonly xs: ptr(i32)
writeonly dst: ptr(i32)
```

- [ ] Emit surface ASDL; do not resolve modifier meaning in parser.

### 4.2 Function contracts

- [x] Parse requires clauses after function signature and before body:

```moonlift
requires bounds(dst, n)
requires disjoint(dst, src)
```

- [ ] Support comma lists later, but line-based clauses are enough initially.
- [x] Emit `FuncContract*` source nodes.
- [ ] Produce `ParseIssue` for malformed contract syntax.

### 4.3 View constructors

- [x] Parse expression call `view(ptr, len)` as explicit surface view construction.

Historical option considered:
  - ordinary `ExprCall` resolved by typechecker, or
  - explicit `ExprView(ViewContiguous(...))` if parser sees keyword `view`.

Preferred for dumb parser:

```text
parse as ordinary call or keyword-shaped surface view node;
typechecker owns semantic interpretation
```

- [ ] Parse `len(xs)` as ordinary call or explicit `ExprLen` surface node.

Preferred:

```text
ExprLen(ExprSurface, xs)
```

because length is a core language operation, not an arbitrary function.

### 4.4 Tests

- [ ] Add parser test for param modifiers.
- [ ] Add parser test for requires clauses.
- [x] Add parser/backend test for `view(ptr, len)`.
- [ ] Add parser test for `len(xs)`.

---

## 5. Typechecker checklist

### 5.1 Parameter bindings

- [ ] Preserve existing function argument binding creation.
- [x] Attach param modifiers to binding-backed facts.
- [ ] Reject invalid modifier combinations:

```text
readonly + writeonly maybe allowed as no-access? decide explicitly
noalias on non-pointer/view should be rejected
bounds on non-pointer/view should be rejected
```

### 5.2 Contract typing

- [x] Resolve contract operands to typed expressions.
- [x] Convert refs to `Binding` facts.
- [ ] Type `bounds(base, len)`:

```text
base: ptr(T) or view(T)
len: integer/index
```

- [ ] Type `disjoint(a, b)`:

```text
a,b: ptr/view-compatible memory bases
```

- [x] Produce `TypeIssue*` for invalid contracts.
- [x] Ensure contracts do not affect parser output semantics.

### 5.3 View typing

- [x] Type `view(ptr, len)`:

```text
ptr: ptr(T)
len: integer/index
result: view(T)
```

- [x] Type `len(xs)`:

```text
xs: view(T)
result: i32 in the current executable ABI slice; future target is index
```

- [x] Type `xs[i]` for `TView(elem)` already exists; ensure it uses `IndexBaseView`.
- [ ] Adopt integer literals to `index` for view lengths where expected.

### 5.4 Tests

- [ ] `test_tree_typecheck_contracts.lua`
- [ ] `test_parse_typecheck_views.lua`
- [ ] invalid contract tests:
  - `bounds(i32, n)`
  - `disjoint(i32, ptr)`
  - `len(ptr)` if only views are accepted

---

## 6. Contract fact phase checklist

Add a dedicated phase file:

```text
lua/moonlift/tree_contract_facts.lua
```

Responsibilities:

```text
Func typed contracts + typed params
  -> ContractFactSet
```

Checklist:

- [x] Implement `contract_expr_binding` phase.
- [x] Implement `func_contract_facts` phase.
- [x] Produce binding-backed facts:

```text
ContractFactBounds
ContractFactDisjoint
ContractFactReadonly
ContractFactWriteonly
```

- [x] Produce rejects/issues as explicit ASDL, not Lua booleans.
- [x] Export API:

```lua
return {
  facts = function(func) ... end,
}
```

- [ ] Add tests for manual typed functions.
- [x] Add parser-to-typechecker-to-contract-facts test.

---

## 7. Backend/view ABI checklist

### 7.1 Function signatures

- [x] Update executable function ABI planning for `TView(elem)`.
- [x] Decide executable ABI:

```text
view(T) as two direct params:
  data: ptr
  len: index
```

The earlier temporary `len: i32` ABI has been retired. `ExprLen(view)`, view constructor/window lengths, and vectorized view-loop counters now use `index`; pointer kernels may still use explicit `i32` counters when their authored stop binding is `i32`.

- [x] Update `tree_to_back.lua` function entry binding:
  - one source view parameter maps to two backend entry values
  - binding lookup for view param returns descriptor values, not one scalar

The function ABI part is now explicit ASDL:

```text
FuncAbiPlan
AbiParamScalar(binding, scalar, value)
AbiParamView(binding, data, len)
AbiResultPlan
```

Tree lowering consumes that plan and materializes existing ASDL tree-back locals (`TreeBackScalarLocal`, `TreeBackViewLocal`, `TreeBackStridedViewLocal`) rather than rebuilding the ABI shape itself.

### 7.2 View construction

- [x] Lower `view(ptr, len)` into descriptor value/facet.
- [ ] For now, avoid first-class returned views if ABI is not ready.
- [x] Support view params first, then local constructed views.

### 7.3 `len(view)` lowering

- [x] Lower `ExprLen(view)` to descriptor len value.
- [x] Ensure result type matches the executable ABI (`index`).

### 7.4 View indexing lowering

- [x] For contiguous views:

```text
addr = data + sext(index) * sizeof(elem)
```

- [ ] For future strided views:

```text
addr = data + sext(index) * stride * sizeof(elem)
```

- [ ] Keep existing pointer indexing path.

### 7.5 Tests

- [x] JIT `sum_view_i32`.
- [ ] JIT `copy_view_i32`.
- [x] JIT `add_view_i32` using `same_len` and `noalias` proofs.
- [x] Test scalar tail correctness for non-multiple-of-lanes lengths.

---

## 8. Vector facts/proofs checklist

### 8.1 Bounds proofs from views

- [ ] In `vec_loop_facts.lua`, recognize domain stop:

```text
len(xs)
```

for the same view used in `xs[i]`.

- [x] Emit kernel safety bounds proof equivalents for each same-view or `same_len`-connected access where:

```text
0 <= i < len(view)
```

is established by the counted domain.

- [x] Keep raw pointer `VecBoundsUnknown` if no contract exists.

### 8.2 Bounds proofs from contracts

- [x] Feed `ContractFactBounds(base, n)` into vector safety proof classification.
- [x] If loop domain is `0 <= i < n`, classify matching contract bounds as kernel safety proofs.

- [x] Reject or assume when length mismatch is not proven.

### 8.3 Alias proofs from contracts

- [x] Feed `ContractFactDisjoint(a, b)` into vector safety alias proof classification.
- [x] Emit kernel safety alias proof equivalents for write-involved pairs proven by contracts.

- [x] Preserve same-base same-index proof for in-place kernels.

### 8.4 Safety policy

- [x] `vec_kernel_safety.lua` should produce:

```text
VecKernelSafetyProven
```

when all bounds and alias/dependence requirements are proven.

- [x] Produce:

```text
VecKernelSafetyAssumed
```

only when source contracts are assumptions rather than proofs, or raw pointers
lack proof input but policy permits caller obligations.

- [ ] Add optional strict mode later:

```text
reject unproven vector memory safety
```

### 8.5 Tests

- [ ] `sum_view_i32` has `VecKernelSafetyProven`.
- [ ] `add_noalias_i32` has alias proofs, not alias assumptions.
- [ ] raw `add_i32(ptr, ptr, ptr, n)` still carries assumptions.
- [ ] missing `bounds` contract keeps bounds assumption/reject.
- [ ] missing `disjoint` contract keeps alias assumption/reject.

---

## 9. Vector kernel expansion checklist

After view/contract proofs are working, expand without changing architecture.

### 9.1 Integer maps/reductions

Already supported families should remain passing:

- [ ] `sum_i32`
- [ ] `dot_i32`
- [ ] `prod_i32`
- [ ] `xor_reduce_i32`
- [ ] `fill_i32`
- [ ] `copy_i32`
- [ ] `add_i32`
- [ ] `sub_i32`
- [ ] `scale_i32`
- [ ] `and_i32`
- [ ] `or_i32`
- [ ] `xor_i32`
- [ ] `inc_i32`
- [ ] `axpy_i32`
- [ ] `sum_i64`
- [ ] `dot_i64`
- [ ] `add_i64`
- [ ] `sub_i64`
- [ ] `scale_i64`
- [ ] `or_i64`
- [ ] `sum_u32`
- [ ] `add_u32`
- [ ] `sum_u64`
- [ ] `add_u64`
- [ ] `xor_u64`

### 9.2 Complete unsigned/signed families

- [ ] Add remaining `u32` maps:
  - `sub_u32`
  - `scale_u32`
  - `and_u32`
  - `or_u32`
  - `xor_u32`
- [ ] Add remaining `u64` maps:
  - `sub_u64`
  - `scale_u64`
  - `and_u64`
  - `or_u64`
- [ ] Add bitwise reductions:
  - `and_reduce_i32/u32/i64/u64`
  - `or_reduce_i32/u32/i64/u64`
  - `xor_reduce_i32/u32/i64/u64`

### 9.3 Float vectors later

Do not implement float reductions until reassociation is explicit.

- [ ] Add `VecElemF32`, `VecElemF64`.
- [ ] Add backend vector float ops.
- [ ] Add `VecReassocFloatFastMath` proof/contract.
- [ ] Only vectorize float reductions with explicit fast-math permission.

---

## 10. Switch/control completeness checklist

This is not part of the memory-proof pass, but should be the next compiler
completeness pass after views/contracts.

- [ ] Parse statement `switch`.
- [ ] Parse expression `switch`.
- [ ] Typecheck switch keys and result types.
- [ ] Lower integer switch to `CmdSwitchInt`.
- [ ] Lower fallback switch to compare/branch chain.
- [ ] Add control-region switch facts where needed.
- [ ] Add tests:
  - parser
  - typechecker
  - backend
  - JIT

---

## 11. Backend scalar completeness checklist

After view ABI lands, continue closing deferred backend forms.

- [ ] Address-of.
- [ ] Deref.
- [ ] Explicit load expression.
- [ ] Aggregate literals.
- [ ] Field access.
- [ ] Arrays.
- [ ] Array indexing.
- [ ] Static/global data access.
- [ ] Richer casts/intrinsics.

Each must be represented as explicit ASDL facts/plans before backend commands.

---

## 12. Test plan

### Required existing tests to keep green

```bash
cargo build --manifest-path Cargo.toml

luajit test_back_vectors.lua

luajit test_asdl_define.lua
luajit test_parse_typecheck.lua
luajit test_parse_playground.lua
luajit test_parse_kernels.lua
luajit test_back_bridge_coverage.lua
luajit test_back_vector_smoke.lua
luajit test_tree_type.lua
luajit test_tree_typecheck.lua
luajit test_tree_control_facts.lua
luajit test_tree_to_back_add_select.lua
luajit test_tree_to_back_counted_loop.lua
luajit test_tree_to_back_while_expr_loop.lua
luajit test_tree_to_back_control_multiblock.lua
luajit test_open_facts_validate.lua
luajit test_open_expand.lua
luajit test_open_rewrite.lua
luajit test_sem_layout_resolve.lua
luajit test_sem_const_eval.lua
luajit test_sem_switch_call.lua
luajit test_bind_residence.lua
luajit test_bind_residence_coverage.lua
luajit test_vec_loop_facts_decide.lua
luajit test_vec_kernel_plan.lua
luajit test_vec_to_back.lua
```

### New tests to add

- [ ] `test_parse_contracts.lua`
- [ ] `test_tree_typecheck_contracts.lua`
- [x] `test_tree_contract_facts.lua`
- [ ] `test_view_backend.lua`
- [x] `test_vec_kernel_safety_proofs.lua`
- [x] `test_parse_view_kernels.lua`

### Required new runtime kernels

- [x] `sum_view_i32`
- [x] `sum_construct_view_i32`
- [ ] `sum_view_i64`
- [x] `copy_view_i32`
- [x] `add_noalias_i32`
- [x] `add_construct_view_i32`
- [x] `copy_construct_view_i32`
- [x] `add_construct_view_i64`
- [x] `add_construct_view_u32`
- [x] `add_construct_view_u64`
- [x] constructed-view family test covers `sum`, `dot`, `copy`, `fill`, `add`, `sub`, `scale`, selected bitwise maps/reductions, `inc`, and `axpy` across current executable integer vector shapes.
- [ ] `add_noalias_i64`
- [ ] `scale_view_i32`
- [ ] scalar tail cases for each:
  - `n = 0`
  - `n = 1`
  - `n = lanes - 1`
  - `n = lanes`
  - `n = lanes + 1`
  - `n = 2 * lanes + 1`

---

## 13. Documentation checklist

Update these as implementation reality changes:

- [ ] `moonlift/README.md`
- [ ] `moonlift/IMPLEMENTATION_CHECKLIST.md`
- [ ] `moonlift/SOURCE_GRAMMAR.md`
- [ ] `moonlift/ASDL2_REFACTOR_MAP.md`
- [ ] `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` if bridge/backend reality changes
- [ ] `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` if backend or language support changes

Docs must distinguish:

```text
implemented and tested
implemented but assumption-backed
implemented but proof-backed
planned only
```

---

## 14. Definition of done

This pass is complete when all are true:

- [ ] View parameters can be parsed, typechecked, lowered, JITed, and indexed.
- [ ] `len(view)` works in source and lowers to backend values.
- [x] `view(ptr, len)` works for initial contiguous local view construction.
- [x] `view(ptr, len, stride)` works for scalar/control strided local view construction and indexing.
- [x] `view_window(view, start, len)` works for scalar/control window construction over contiguous or strided local views.
- [x] `window_bounds(base, base_len, start, len)` is a source contract and binding-backed proof fact.
- [x] Window vector safety is mediated by explicit `VecWindowRangeObligation` / `VecWindowRangeDecision` values; full-range windows, literal shrink windows (`start = k`, `len = base_len - c`, `c >= k`, including scalar-alias starts), and nested accumulated literal-offset windows are compiler-proven, while general subwindows require `window_bounds`.
- [x] Vector window length provenance is explicit via `VecKernelLenSource`, and view parameters seed `VecKernelLenView` aliases so `len(view)`-based windows vectorize without binding fakery.
- [x] Vector kernel planning looks through prefix local constructed-view aliases (`let v = view(ptr, len)` / unit-stride `view(ptr, len, 1)`) to recover pointer/length bindings for a broad `i32`/`i64`/`u32`/`u64` map/reduction family.
- [x] Non-unit constructed-view strides produce explicit `VecRejectUnsupportedMemory` values until gather/scatter vectorization is implemented; contiguous/unit-stride constructed windows over pointer-backed locals or view parameters vectorize through explicit offset/length-source aliases when the window range is compiler-proven (`0,n`, `k,n-c` with `c >= k`, including nested offsets) or `window_bounds` proves it.
- [x] Loop fact extraction records constant non-unit view stride as `VecAccessStrided(stride)` and the loop decision phase rejects unsupported strided/gather/scatter/unknown memory patterns explicitly.
- [ ] Function contracts parse and typecheck.
- [ ] Contracts produce binding-backed ASDL facts.
- [ ] Vector loop facts consume view/contract facts.
- [ ] `VecKernelSafetyDecision` distinguishes:
  - proven bounds
  - assumed bounds
  - rejected bounds
  - proven alias/no-dependence
  - assumed alias/no-dependence
  - rejected alias/no-dependence
- [ ] At least one view kernel produces `VecKernelSafetyProven`.
- [ ] At least one noalias pointer kernel produces alias proofs instead of alias assumptions.
- [ ] Existing raw pointer kernels still work and honestly carry assumptions if unproven.
- [ ] All existing tests pass.
- [ ] New parser/typechecker/backend/vector/JIT tests pass.
- [ ] Living docs are updated.

---

## 15. Anti-goals for this pass

Do not implement these in this pass unless the above is complete:

- [ ] general closures
- [ ] full aggregate system
- [ ] parser recovery overhaul
- [ ] arbitrary multi-block vectorization
- [ ] float reductions without explicit reassociation policy
- [ ] backend-specific vector peepholes
- [ ] hidden side tables for noalias/bounds
- [ ] old Moonlift loop syntax

---

## 16. Recommended implementation order inside the single pass

Although this is one coherent pass, implementation should still go bottom-up:

1. [ ] ASDL block update for contracts/views/proofs.
2. [ ] ASDL definition tests.
3. [ ] Parser surface syntax.
4. [ ] Typechecker binding-backed contract/view typing.
5. [ ] Contract fact phase.
6. [ ] Backend view ABI/value lowering.
7. [ ] Vector fact proof production.
8. [ ] Vector safety proof consumption.
9. [ ] JIT source kernels.
10. [ ] Docs sync.
11. [ ] Full test suite.

The invariant throughout:

```text
No phase should infer important meaning from an opaque Lua helper state when that meaning can be an ASDL value.
```
