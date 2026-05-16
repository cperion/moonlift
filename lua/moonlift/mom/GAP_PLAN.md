# MOM Gap Plan — Closing the Compiler Phase Gap

This document is the complete, actionable checklist for porting the Moonlift
compiler from Lua/PVM to native Moonlift (MOM). Every item specifies the exact
file to create or modify, what it must do, what it depends on, and how to
verify it. An AI coding agent with no prior Moonlift knowledge can execute each
phase by reading this document, the referenced Lua behavioral oracle modules,
and the existing MOM modules.

## Conventions

- **File paths** are relative to the repository root (e.g., `lua/moonlift/mom/back/ops.mlua`).
- **Lua oracle** files are under `lua/moonlift/` (not `lua/moonlift/mom/`).
- **MOM modules** are `.mlua` files under `lua/moonlift/mom/`.
- **Tag constants** come from `lua/moonlift/mom/back/back_tags.lua` — the single source of truth.
- All new MOM modules use `local T = require("moonlift.mom.back.back_tags")` and splice with `@{T.XXX}`.
- Every `func` and `region` must terminate every path with `return`, `yield`, or `jump`.
- No "for now", "temporary", "bridge", or "we can fix it later" framing.
- Lua is staging only — no Lua runtime in the compiler core.

---

## Existing Modules (6,022 lines, 21 files)

| File | Lines | Role |
|------|------:|------|
| `mom/runtime/builders.mlua` | 125 | Allocation-free typed builders (I32Builder, IssueBuilder, CmdBuffer, LowerState) |
| `mom/runtime/sets.mlua` | 105 | Allocation-free integer hash maps (I32Map) |
| `mom/back/ids.mlua` | 50 | BackValId/BackBlockId/BackAccessId/BackStackSlotId allocators |
| `mom/back/env.mlua` | 160 | Function-local backend environment (scalar/view/stack/data/func/extern binds) |
| `mom/back/ops.mlua` | 184 | Pure dispatch: unary/binary/compare/cast/atomic op selection |
| `mom/back/cmd.mlua` | 578 | CmdEntry struct + ~30 Cmd constructors + 4 dispatch lowers |
| `mom/back/expr_lower.mlua` | 207 | 6/18 expression types (lit, unary, binary, compare, select, ref→trap) |
| `mom/back/stmt_lower.mlua` | 345 | 4/15 statement types (return_void, return_value, expr, if) |
| `mom/back/control.mlua` | 235 | Control fact extraction + simplification validation |
| `mom/back/validate.mlua` | 274 | Complete structural Cmd tape validation (all 60+ variants) |
| `mom/back/back_tags.lua` | — | Single source of truth for all schema-derived tag constants |
| `mom/vec/vec_facts.mlua` | 75 | Skeleton: backedge + simple reduction facts only |
| `mom/vec/vec_decide.mlua` | 76 | Skeleton: hardcoded BackI32 default, heuristic lane count |
| `mom/vec/vec_plan.mlua` | 78 | Skeleton: 3 plan tags (NO_PLAN/REDUCE/MAP/ALGEBRAIC) |
| `mom/vec/vec_lower.mlua` | 87 | Skeleton: loop skeleton only, no vector instructions |
| `mom/parser/document_scan.mlua` | 241 | `.mlua` island scanner over `ptr(u8)+len` |
| `mom/parser/native_lexer.mlua` | 1111 | Token tape lexer + parse-event scanner |
| `mom/parser/native_core.mlua` | 1232 | Parser recognition core (regions/blocks/switches parsed fully) |
| `mom/parser/native_tree.mlua` | 353 | Materializes parser output to typed AST arena |
| `mom/driver/wire.mlua` | 179 | MLBT v3 binary wire format writer |
| `mom/driver/lower_wire.mlua` | 291 | Parser tape → MLBT wire (skips semantic phases) |
| `mom/driver/backend_ffi.mlua` | 38 | Rust Cranelift backend FFI bridge |

---

## Lua Oracle Modules (12,117 lines)

These are the behavioral reference. Port compiler *meaning*, not PVM mechanics.

| Oracle File | Lines | Purpose |
|-------------|------:|---------|
| `lua/moonlift/open_expand.lua` | 1048 | Expand splice holes, resolve MoonOpen slots |
| `lua/moonlift/open_rewrite.lua` | 379 | Rewrite typed-open tree nodes to resolved targets |
| `lua/moonlift/open_facts.lua` | 427 | Gather type/value/expr header facts about open slots |
| `lua/moonlift/open_validate.lua` | 78 | Validate open slots, produce issues |
| `lua/moonlift/tree_typecheck.lua` | 795 | Main typecheck pass |
| `lua/moonlift/tree_expr_type.lua` | 135 | Expression type inference |
| `lua/moonlift/tree_stmt_type.lua` | 37 | Statement type checking |
| `lua/moonlift/tree_place_type.lua` | 80 | Place (lvalue) type checking |
| `lua/moonlift/tree_module_type.lua` | 176 | Module-level type orchestration |
| `lua/moonlift/tree_contract_facts.lua` | 82 | Contract fact extraction |
| `lua/moonlift/tree_control_facts.lua` | 267 | Control flow fact extraction and validation |
| `lua/moonlift/sem_call_decide.lua` | 130 | Call target decision |
| `lua/moonlift/sem_const_eval.lua` | 370 | Compile-time constant evaluation |
| `lua/moonlift/sem_switch_decide.lua` | 76 | Switch key classification and arm matching |
| `lua/moonlift/sem_layout_resolve.lua` | 383 | Type layout resolution (struct/union field offsets) |
| `lua/moonlift/type_classify.lua` | 88 | Type category classification |
| `lua/moonlift/type_size_align.lua` | 115 | Type size and alignment computation |
| `lua/moonlift/type_abi_classify.lua` | 72 | ABI category classification |
| `lua/moonlift/type_func_abi_plan.lua` | 71 | Function call ABI planning |
| `lua/moonlift/type_to_back_scalar.lua` | 83 | Type enum → BackScalar mapping |
| `lua/moonlift/tree_control_to_back.lua` | 414 | Lower control regions to Back.Cmd CFG |
| `lua/moonlift/tree_to_back.lua` | 2004 | Main MoonTree → BackProgram lowering |
| `lua/moonlift/bind_residence_gather.lua` | 267 | Gather binding residence facts |
| `lua/moonlift/bind_residence_decide.lua` | 62 | Decide binding storage class |
| `lua/moonlift/bind_machine_binding.lua` | 34 | Produce machine bindings from residence |
| `lua/moonlift/vec_loop_facts.lua` | 625 | Vectorizable loop fact extraction |
| `lua/moonlift/vec_loop_decide.lua` | 154 | Vectorization legality decision |
| `lua/moonlift/vec_kernel_plan.lua` | 848 | Vector kernel plan construction |
| `lua/moonlift/vec_kernel_safety.lua` | 486 | Vectorization safety analysis |
| `lua/moonlift/vec_kernel_to_back.lua` | 921 | Lower vector kernel to Back.Cmd |
| `lua/moonlift/vec_to_back.lua` | 362 | Lower vector shapes and operations |
| `lua/moonlift/vec_inspect.lua` | 23 | Vectorization inspection reports |
| `lua/moonlift/back_validate.lua` | 724 | BackProgram structural validation (oracle for validate.mlua) |
| `lua/moonlift/back_diagnostics.lua` | 35 | Diagnostic output from BackProgram |
| `lua/moonlift/back_inspect.lua` | 54 | BackProgram statistics |
| `lua/moonlift/back_program.lua` | 55 | BackProgram construction utilities |
| `lua/moonlift/back_target_model.lua` | 157 | Target platform model (pointer size, scalar mappings) |

---

## Phase 0: Schema ✅ DONE

All 9 schema files exist under `lua/moonlift/mom/schema/`. Tag constants
auto-derived from schema union declarations via `lua/moonlift/mom/back/back_tags.lua`.

---

## Phase 1: Document Scanner ✅ DONE

- [x] `mom/parser/document_scan.mlua` — scans `.mlua` for Moonlift islands

**Test:** `luajit tests/test_mom_document_scan.lua`

---

## Phase 2: Lexer ✅ DONE

- [x] `mom/parser/native_lexer.mlua` — token tape lexer over `ptr(u8)+len`

**Test:** `luajit tests/test_mom_native_lexer.mlua`

---

## Phase 3: Parser Core ✅ DONE

- [x] `mom/parser/native_core.mlua` — full region/block/switch/emit parsing
- [x] `mom/parser/native_tree.mlua` — typed AST materialization

**Test:** `luajit tests/test_mom_native_core.lua`, `luajit tests/test_mom_native_tree.lua`

---

## Phase 4: Command Constructors (30/60 done, 30 remain)

**Status:** `mom/back/cmd.mlua` has ~30 Cmd constructors. 30 more are needed.

**Oracle:** `lua/moonlift/tree_to_back.lua` is the behavioral reference for what
each Cmd variant must contain.

**Current constructors** (in `cmd.mlua`):
`CmdTrap`, `CmdConst`, `CmdSelect`, `CmdIntBinary`, `CmdFloatBinary`,
`CmdBitBinary`, `CmdShift`, `CmdUnary`, `CmdBitNot`, `CmdCompare`, `CmdCast`,
`CmdPtrOffset`, `CmdLoadInfo`, `CmdStoreInfo`, `CmdAlias`,
`CmdCreateStackSlot`, `CmdStackAddr`

**Missing constructors (30):**

Create each as a pure `func` returning a `CmdEntry` (18-field struct `tag + w0..w16`).
Tag constants come from `@{T.CmdXxx}` in `back_tags.lua`.

| Constructor | Tag constant | Fields (w0..) |
|-------------|-------------|---------------|
| `mb_cmd_target_model` | `CmdTargetModel` | ptr_size, has_f32, has_f64, has_vec |
| `mb_cmd_create_sig` | `CmdCreateSig` | sig_id |
| `mb_cmd_declare_data` | `CmdDeclareData` | data_id, init_tag, align, len, ptr |
| `mb_cmd_data_init_zero` | `CmdDataInitZero` | data_id |
| `mb_cmd_data_init` | `CmdDataInit` | data_id, offset, scalar, lit_tag, lit_lo, lit_hi |
| `mb_cmd_data_addr` | `CmdDataAddr` | data_id |
| `mb_cmd_func_addr` | `CmdFuncAddr` | func_id |
| `mb_cmd_extern_addr` | `CmdExternAddr` | extern_id |
| `mb_cmd_declare_func` | `CmdDeclareFunc` | vis, func_id, sig_id |
| `mb_cmd_declare_extern` | `CmdDeclareExtern` | extern_id, sig_id |
| `mb_cmd_begin_func` | `CmdBeginFunc` | func_id |
| `mb_cmd_create_block` | `CmdCreateBlock` | block_id |
| `mb_cmd_switch_to_block` | `CmdSwitchToBlock` | block_id |
| `mb_cmd_seal_block` | `CmdSealBlock` | block_id |
| `mb_cmd_bind_entry_params` | `CmdBindEntryParams` | block_id, count |
| `mb_cmd_append_block_param` | `CmdAppendBlockParam` | block_id, val_id |
| `mb_cmd_intrinsic` | `CmdIntrinsic` | dst, intrinsic, scalar, args... |
| `mb_cmd_atomic_load` | `CmdAtomicLoad` | dst, scalar, ptr, ordering |
| `mb_cmd_atomic_store` | `CmdAtomicStore` | scalar, ptr, val, ordering |
| `mb_cmd_atomic_rmw` | `CmdAtomicRmw` | dst, op, scalar, ptr, val, ordering |
| `mb_cmd_atomic_cas` | `CmdAtomicCas` | dst, scalar, ptr, expected, new, ordering |
| `mb_cmd_atomic_fence` | `CmdAtomicFence` | ordering |
| `mb_cmd_rotate` | `CmdRotate` | dst, op, scalar, lhs, rhs |
| `mb_cmd_fma` | `CmdFma` | dst, scalar, a, b, c |
| `mb_cmd_alias_fact` | `CmdAliasFact` | kind, a, b, c |
| `mb_cmd_memcpy` | `CmdMemcpy` | dst, src, len |
| `mb_cmd_memset` | `CmdMemset` | dst, val, len |
| `mb_cmd_call` | `CmdCall` | dst, func_id, args_aux, args_count |
| `mb_cmd_jump` | `CmdJump` | dest, args_aux, args_count |
| `mb_cmd_br_if` | `CmdBrIf` | cond, then_block, then_aux, then_count, else_block, else_aux, else_count |
| `mb_cmd_switch_int` | `CmdSwitchInt` | val, cases_aux, default_block |

Plus completing row-format writers in `driver/wire.mlua` for any new Cmd variants.

**Files to modify:**
- `lua/moonlift/mom/back/cmd.mlua` — add each constructor
- `lua/moonlift/mom/back/validate.mlua` — add validation rules for each new Cmd variant (tag, required/optional fields, scope membership)
- `lua/moonlift/tests/test_mom_groundwork.lua` — add test for each constructor

**Verification:** Each constructor must round-trip through `cmd.mlua` construction → `validate.mlua` validation → `wire.mlua` serialization → Rust FFI decode. Run `luajit tests/test_mom_groundwork.lua` for each batch.

---

## Phase 5: Expression Lowering (6/18 done, 12 remain)

**Status:** `mom/back/expr_lower.mlua` handles lit, unary, binary, compare, select.
Ref lowering emits `CmdTrap` (implementation gap: env lookup not wired).
Hardcoded `BackI32` scalar throughout — needs type tape input.

**Oracle:** `lua/moonlift/tree_to_back.lua` lines handling each Expr variant.

**Missing expression lowerers (12):**

| Expr tag constant | Lowering behavior | Cmd variant produced |
|-------------------|-------------------|----------------------|
| `EX_CAST` | Read cast op + scalar from type tape, dispatch through `mb_lower_cast_cmd` | `CmdCast` or `CmdTrap` |
| `EX_LOGIC` | Lower both operands, emit `CmdSelect` for short-circuit and/or | `CmdSelect` |
| `EX_CALL` | Lower args, choose direct/extern call target | `CmdCall` |
| `EX_DOT` | Lower struct field access (layout-aware) | `CmdLoadInfo` + offset |
| `EX_INDEX` | Lower array index access | `CmdLoadInfo` + computed offset |
| `EX_DEREF` | Lower pointer dereference | `CmdLoadInfo` |
| `EX_ADDR` | Lower address-of | `CmdStackAddr` or re-emit ptr |
| `EX_LEN` | View length lookup | Read from view descriptor |
| `EX_VIEW` | View construction | Emit view descriptor fields |
| `EX_IF` | Scalar: emit `CmdSelect`. Effectful: emit `CmdBrIf` + blocks | `CmdSelect` or CFG |
| `EX_SWITCH` | Emit `CmdSwitchInt` + arm blocks | `CmdSwitchInt` + CFG |
| `EX_CONTROL` | Delegate to control region lowerer | Depends on region |

**Files to create or modify:**
- `lua/moonlift/mom/back/expr_lower.mlua` — add each new lowering `func`
- `lua/moonlift/mom/back/stmt_lower.mlua` — import from `expr_lower` instead of duplicating

**Key dependency:** Cast and call lowering need type information. Until Phase 9 (typecheck) produces typed AST, these lowerers read type info from a type tape passed as parameters. The `mb_lower_expr` function signature must accept `(tag, a, b, c, d, e, st: ptr(i32), cmds: ptr(i32), e_tag: ptr(i32), e_scalar: ptr(i32))` where `e_scalar` provides the type-scalar tag for each expression node.

**Verification:** `luajit tests/test_mom_groundwork.lua` — add test for each new expression lowerer.

---

## Phase 6: Statement Lowering (4/15 done, 11 remain)

**Status:** `mom/back/stmt_lower.mlua` handles return_void, return_value, expr_stmt, if.
Duplicates expr_lower helpers. Needs block ID allocator separation (done).
Unknown tags emit `CmdTrap`.

**Oracle:** `lua/moonlift/tree_to_back.lua` statement handling.

**Missing statement lowerers (11):**

| Stmt tag constant | Lowering behavior | Cmd variants produced |
|-------------------|-------------------|----------------------|
| `ST_LET` | Lower init expr, bind scalar/view local in env | `CmdSelect` or zero-cost bind |
| `ST_VAR` | Create stack slot, lower init, store | `CmdCreateStackSlot` + `CmdStoreInfo` |
| `ST_SET` | Lower place address and value, emit store | `CmdStoreInfo` |
| `ST_SWITCH` | Emit `CmdSwitchInt` + arm/default/join blocks | CFG commands |
| `ST_JUMP` | Emit `CmdJump` with args | `CmdJump` |
| `ST_YIELD_VOID` | Emit `CmdReturnValue` or zero-cost yield depending on context | depends |
| `ST_YIELD_VALUE` | Emit value + `CmdReturnValue` | `CmdReturnValue` |
| `ST_EMIT` | Delegate to control region lowerer | region composition |
| `ST_ATOMIC_STORE` | Lower address + value + ordering | `CmdAtomicStore` |
| `ST_ATOMIC_FENCE` | Lower ordering | `CmdAtomicFence` |
| `ST_CONTROL` | Delegate to control region lowerer | region composition |

**Files to modify:**
- `lua/moonlift/mom/back/stmt_lower.mlua` — add each new lowerer, remove expr_lower duplication by importing from expr_lower
- `lua/moonlift/mom/back/env.mlua` — extend env to support `ST_LET`/`ST_VAR` binding (scalar, view, stack, data, func, extern kinds)

**Key dependency:** `ST_LET` and `ST_VAR` need type-scalar info (from type tape or env). `ST_EMIT` and `ST_CONTROL` need Phase 10 (control lowering).

**Verification:** `luajit tests/test_mom_groundwork.lua` — add test for each new statement lowerer.

---

## Phase 7: Control Fact Extraction (partial skeleton, needs extension)

**Status:** `mom/back/control.mlua` extracts `CF_BLOCK`, `CF_JUMP`, `CF_YIELD_VOID`,
`CF_YIELD_VALUE`, `CF_ENTRY_BLOCK`, `CF_ENTRY_PARAM`, `CF_BACKEDGE`, `CF_RETURN`.
No contract facts, no region parameter facts.

**Oracle:** `lua/moonlift/tree_control_facts.lua` (267 lines) — extracts block facts,
jump arg facts, yield type facts, contract facts from region declarations.
`lua/moonlift/tree_contract_facts.lua` (82 lines) — extracts vectorization/alias
contract facts.

**Missing:** Contract fact extraction (`CF_CONTRACT_*` variants), region parameter
propagation, and the full set of validation rules from `tree_control_facts.lua`.

**Files to create:**
- `lua/moonlift/mom/back/back_control_facts.mlua` — full control fact extraction from typed AST
- `lua/moonlift/mom/back/back_control_validate.mlua` — full validation (reducibility, jump protocol, yield types, block param consistency, duplicate labels, missing labels, unterminated blocks, yield-in-expr-region)

**Files to modify:**
- `lua/moonlift/mom/back/control.mlua` — may be absorbed into `back_control_facts.mlua` or kept as a simplified version

**Verification:** `luajit tests/test_mom_groundwork.lua` — extend with validation test cases covering: reducible graphs, missing labels, duplicate labels, yield type mismatches, unterminated blocks.

---

## Phase 8: Control Lowering (does not exist)

**Status:** No `back_control_lower.mlua` exists. This is the port of
`lua/moonlift/tree_control_to_back.lua` (414 lines).

**What it does:** Allocates fresh nonce/block prefix from `LowerState.ids`,
creates all target blocks and block params upfront, lowers entry initializers to
jump args, for each control block: switches to target block, binds block params
into local env, lowers body, requires termination or emits `CmdTrap`.

**Files to create:**
- `lua/moonlift/mom/back/back_control_lower.mlua` — implements:

| Function | Signature | Purpose |
|----------|-----------|---------|
| `mc_lower_region` | `region(Stmts, LowerState; done)` | Top-level region lowerer |
| `mc_lower_block` | `func(BlockStmts, block_params, LowerState) -> LowerState` | Lower a single block body |
| `mc_lower_emit` | `region(EmitSite, LowerState; done)` | Lower an emit statement (splice CFG) |
| `mc_lower_jump` | `func(JumpArgs, dest_block, LowerState) -> LowerState` | Lower a jump with phi args |
| `mc_lower_yield_void` | `func(LowerState) -> LowerState` | Lower a void yield |
| `mc_lower_yield_value` | `func(val_id, LowerState) -> LowerState` | Lower a value yield |

**Oracle:** `lua/moonlift/tree_control_to_back.lua` — the production Lua implementation of all four control patterns (region/block/jump/yield emit).

**Verification:** Write `tests/test_mom_control_lower.lua` that:
1. Constructs a simple region (entry + loop + yield)
2. Lowers it through `mc_lower_region`
3. Validates the resulting Cmd tape through `mb_validate`
4. Compares the output CFG shape with the Lua oracle for the same source

---

## Phase 9: Type System (in progress)

**This is the critical blocker.** No typed AST → no type info → no correct lowering.

The MOM typechecker reads `MomTreeOut` (flat SoA from `native_tree.mlua`) and produces
typed annotations as additional parallel arrays consumed by lowering passes.

**Input:** `MomTreeOut` — type/expr/stmt/item arenas as flat SoA
**Output:** `TypeCheckOut` — per-expr type annotations + per-stmt flow + issues

All tag constants from `lua/moonlift/mom/back/back_tags.lua`. All type inference
rules follow `lua/moonlift/tree_typecheck.lua` (795 lines) — the primary behavioral
oracle. PVM phase dispatch becomes Moonlift `func` + `switch`.

### 9a: Open Expansion (deferred — handled by Lua staging)

`@{}` splice slots and fragment references (`ExprSlotValue`, `StmtUseRegionFrag`,
`ExprUseExprFrag`) are resolved at the Lua `.mlua` staging layer before source
reaches the MOM native parser. The MOM native compiler receives closed AST only.

When the MOM compiler needs to handle `.mlua` compilation end-to-end (Phase 14),
create:
- `mom/open/open_facts.mlua` — walk parsed AST, find splice slots and fragment use sites
- `mom/open/open_validate.mlua` — check fill types, region param arity, import resolution
- `mom/open/open_expand.mlua` — rewrite open constructs, inline fragments

**Oracle:** `lua/moonlift/open_expand.lua` (1048), `lua/moonlift/open_facts.lua` (427),
`lua/moonlift/open_validate.lua` (78), `lua/moonlift/open_rewrite.lua` (379).

### 9b: Typecheck (MVP — 6 modules, ~800 LOC)

**Oracle files (primary):**
| File | Lines | Purpose |
|---|---|---|
| `tree_typecheck.lua` | 795 | Main typecheck pass — all Expr/Stmt/Place/Control/Func/Module typing |
| `tree_expr_type.lua` | 135 | Expression type inference (header_type, value_ref_type, expr_type) |
| `tree_module_type.lua` | 176 | Module env building (item env entries, layouts, func/extern/const entries) |
| `tree_stmt_type.lua` | 37 | Stmt env effects (StmtEnvAddBinding / StmtEnvNoBinding) |
| `tree_place_type.lua` | 80 | Place subexpression typing (PlaceRef/PlaceDeref/PlaceDot/PlaceField/PlaceIndex) |

**Oracle files (secondary — pure dispatch patterns):**
| File | Lines | Purpose |
|---|---|---|
| `type_classify.lua` | 88 | Type variant → TypeClass classification (scalar/ptr/view/func/...) |
| `type_size_align.lua` | 115 | Type memory layout (size/alignment per scalar class) |
| `type_to_back_scalar.lua` | 83 | Scalar/Type → BackScalar mapping |
| `sem_call_decide.lua` | 130 | Call target decision (direct/extern/indirect/closure) |
| `sem_const_eval.lua` | 370 | Compile-time constant evaluation |
| `sem_switch_decide.lua` | 76 | Switch key classification and arm matching |

**Files to create:**
| Module | Lua oracle mapping | Functions | Est LOC |
|---|---|---|---|
| `typecheck/type_scalar.mlua` | `tree_typecheck.lua` helpers | `mt_is_float_scalar`, `mt_is_integer_scalar`, `mt_is_bool_scalar`, `mt_scalar_bit_width`, `mt_adopt_literal` | 50 |
| `typecheck/type_env.mlua` | `tree_module_type.lua` env + `tree_typecheck.lua` env helpers | `push_scope`, `pop_scope`, `lookup(name) -> (found, type_idx)`, `bind(name, type_idx)` | 80 |
| `typecheck/type_classify.mlua` | `type_classify.lua` | `classify_type(type_tag, scalar) -> (class_tag, elem)` — maps `MT_SCALAR→TypeClassScalar`, `MT_PTR→TypeClassPointer`, etc. | 40 |
| `typecheck/type_expr.mlua` | `tree_expr_type.lua` + `tree_typecheck.lua` type_expr | `type_expr(expr_idx, tree, env, out) -> scalar` — all 20 `ME_*` tags | 250 |
| `typecheck/type_stmt.mlua` | `tree_typecheck.lua` type_stmt + `tree_stmt_type.lua` | `type_stmt(stmt_idx, tree, env, out) -> flow` — all 13 `MS_*` tags + env effects | 200 |
| `typecheck/type_module.mlua` | `tree_module_type.lua` + `tree_typecheck.lua` type_module | `build_env(tree) -> env_idx`, `type_module(tree, out) -> issue_count` | 180 |

**Output struct:**
```moonlift
struct TypeCheckOut
    expr_scalar: ptr(i32)     -- per-expr: inferred scalar tag or -1
    expr_type_idx: ptr(i32)   -- per-expr: type arena index or -1
    stmt_flow: ptr(i32)       -- per-stmt: 0=falls_thru, 1=returns, 2=terminates
    issue_tag: ptr(i32)
    issue_data0: ptr(i32)
    issue_data1: ptr(i32)
    issue_count: i32
    cap: index
end
```

**Key type inference rules (from Lua oracle):**

| Expr tag (`ME_*`) | Rule | Produces |
|---|---|---|
| `ME_LIT` | Token-dependent | `TK_INT→ScalarI32`, `TK_TRUE→ScalarBool`, `TK_FLOAT→ScalarF64`, `TK_STRING→BackPtr` |
| `ME_REF` | Env lookup by name token | env binding type |
| `ME_UNARY` | Type of child (`expr_lhs`) | child's scalar/type |
| `ME_BINARY` | Type of LHS; ptr+int → ptr | LHS type |
| `ME_COMPARE` | Always bool | `ScalarBool` |
| `ME_CAST` | Target type from type arena (LHS = type index) | cast target type |
| `ME_CALL` | Result type from callable target | func return type |
| `ME_DOT` | Field type from struct layout | field type |
| `ME_INDEX` | Element type from base (view/ptr elem) | elem type |
| `ME_DEREF` | `ptr(T)` → `T` | pointed-to type |
| `ME_ADDR_OF` | `ptr(inner_type)` | pointer to inner |
| `ME_LEN` | Always index | `ScalarIndex` |
| `ME_IF` | Type of then-branch | branch type |
| `ME_SELECT` | Type of then-branch | branch type |
| `ME_SWITCH` | Type of default arm | arm type |
| `ME_CONTROL` | Region result type | `region.result_ty` |
| `ME_VIEW` | View elem type | `view(elem)` |
| `ME_HOLE` | Void/unknown | `ScalarVoid` |

**Issue types (tags from `back_tags.lua`, schema from `MoonCyclic.mlua`):**
`TypeIssueUnresolvedValue`, `TypeIssueExpected`, `TypeIssueArgCount`,
`TypeIssueNotCallable`, `TypeIssueNotPointer`, `TypeIssueNotIndexable`,
`TypeIssueInvalidUnary`, `TypeIssueInvalidBinary`, `TypeIssueInvalidCompare`,
`TypeIssueInvalidLogic`.

**Build order:**
1. `type_scalar.mlua` — independent scalar predicates + literal adoption
2. `type_env.mlua` — scoped name→type map using `I32Map` from `runtime/sets.mlua`
3. `type_classify.mlua` — type tag classification
4. `type_expr.mlua` — all 20 expression tags
5. `type_stmt.mlua` — all 13 statement tags
6. `type_module.mlua` — env building + orchestration
7. `tests/test_mom_typecheck.lua` — test each module

**Verification:**
```sh
luajit tests/test_mom_groundwork.lua   # must still pass
luajit tests/test_mom_typecheck.lua     # new: compile + test each typecheck module
```

### 9c: Layout Resolve (after 9b)

**Oracle:** `lua/moonlift/sem_layout_resolve.lua` (383), `lua/moonlift/type_size_align.lua` (115),
`lua/moonlift/type_abi_classify.lua` (72), `lua/moonlift/type_func_abi_plan.lua` (71).

**Files to create:**
- `lua/moonlift/mom/layout/layout_env.mlua` — type → storage info mappings
- `lua/moonlift/mom/layout/layout_field.mlua` — struct/union field offset computation
- `lua/moonlift/mom/layout/layout_resolve.mlua` — rewrite pass: `TypeRef` → `LayoutEntry`, `ExprDot` → `ExprField(offset)`

**Test:** Create `tests/test_mom_layout.lua`.

---

## Phase 10: ABI Helpers (partial — needs completion)

**Status:** `mom/back/ops.mlua` has `mb_is_float_scalar`, `mb_core_scalar_to_back`, `mb_type_to_back_scalar`, and all op dispatch. Missing: ABI classification, function ABI planning.

**Oracle:** `lua/moonlift/type_abi_classify.lua` (72), `lua/moonlift/type_func_abi_plan.lua` (71).

**Files to create:**
- `lua/moonlift/mom/back/back_abi.mlua` — consolidate and extend:
  - `mb_abi_classify(type_tag, scalar_tag) -> AbiClass` (Direct, Indirect, ViewDescriptor)
  - `mb_func_abi_plan(param_types, result_type) -> FuncAbiPlan` (parameter registers, stack args, return classification)
  - `mb_type_to_back_scalar` (move from `ops.mlua`)

**Test:** Extend `tests/test_mom_groundwork.lua` with ABI tests. Compare ABI results with Lua `type_abi_classify.lua` and `type_func_abi_plan.lua`.

---

## Phase 11: Binding and Memory (does not exist)

**Oracle:** `lua/moonlift/bind_residence_gather.lua` (267), `lua/moonlift/bind_residence_decide.lua` (62), `lua/moonlift/bind_machine_binding.lua` (34).

**What it does:** After typecheck, decide whether each local binding lives in a register, stack slot, or addressable memory. This determines whether `let x = …` becomes a zero-cost SSA bind or a `CmdCreateStackSlot` + `CmdStoreInfo`.

**Files to create:**
- `lua/moonlift/mom/back/back_residence.mlua` — gather residence facts (address-taken, mutable, non-scalar-abi), decide residence, produce machine bindings

**Test:** Create `tests/test_mom_residence.lua`.

---

## Phase 12: Function and Module Lowering (does not exist)

**Oracle:** `lua/moonlift/tree_to_back.lua` (2004) — the main lowering file. Not a single module; extract function/module lowering concerns.

**Files to create:**
- `lua/moonlift/mom/back/back_func.mlua` — ABI plan for function entry, parameter binding, return mode, stack slot allocation
- `lua/moonlift/mom/back/back_module.mlua` — item hoisting, externs, globals, FinalizeModule emission

**These orchestrate the existing per-expression and per-statement lowerers into function-level and module-level contexts.**

**Test:** Extend `tests/test_mom_groundwork.lua` with function-level lowering tests (begin func, bind params, lower body, finish func, finalize module).

---

## Phase 13: Vectorization (skeletons only — replace with real implementation)

**Status:** All four `vec/*.mlua` files exist as skeletons with hardcoded constants and trivial output. Must be replaced with real implementations ported from the Lua oracle.

**Oracle files:**
- `lua/moonlift/vec_loop_facts.lua` (625) — recognize counted loops, reduction patterns, memory access patterns, alias analysis
- `lua/moonlift/vec_loop_decide.lua` (154) — decide vectorization legality based on facts + target model
- `lua/moonlift/vec_kernel_plan.lua` (848) — construct `VecKernelPlan` for map/reduce/algebraic kernels
- `lua/moonlift/vec_kernel_safety.lua` (486) — check vectorization safety (aliasing, masking, dependencies)
- `lua/moonlift/vec_kernel_to_back.lua` (921) — lower vector kernel to `Back.Cmd`
- `lua/moonlift/vec_to_back.lua` (362) — lower vector shapes and operations

**Files to rewrite:**
- `lua/moonlift/mom/vec/vec_facts.mlua` — **replace** with real loop recognition
- `lua/moonlift/mom/vec/vec_decide.mlua` — **replace** with real legality + lane count decision
- `lua/moonlift/mom/vec/vec_plan.mlua` — **replace** with real kernel planning
- `lua/moonlift/mom/vec/vec_lower.mlua` — **replace** with real `CmdVecSplat`, `CmdVecBinary`, etc.

**Files to create:**
- `lua/moonlift/mom/vec/vec_safety.mlua` — alias and dependency analysis
- `lua/moonlift/mom/vec/vec_validate.mlua` — verify vector kernel correctness

**Key dependency:** Real `vec_decide.mlua` must read element type from typed AST, not hardcode `BackI32`. Real `vec_lower.mlua` must emit actual vector instructions, not loop skeletons.

**Verification:** `luajit tests/test_mom_vec.lua` — compare with Lua `vec_to_back.lua` for every vectorizable loop test.

---

## Phase 14: Pipeline Wiring (partial)

**Status:** `lua/moonlift/host_mom.lua` compiles lexer + parser + lower_wire + backend_ffi.
`lua/moonlift/mom/driver/lower_wire.mlua` goes parser tape → MLBT wire, skipping all semantic phases.

**Files to modify:**
- `lua/moonlift/mom/driver/lower_wire.mlua` — become a thin serialization of validated `BackProgram` → MLBT v3 (remove parser-tape shortcut, require semantic pipeline output)
- `lua/moonlift/host_mom.lua` — insert semantic phases:
  ```
  parse → open_expand → typecheck → layout_resolve
  → control_facts → back_lower (expr+stmt+control+func+module)
  → back_validate → lower_wire → backend
  ```

**After Phases 4-12 are complete**, each phase module is loaded via `host_mom.lua`,
compiled through `mlua_run`, and called in sequence. The wire format becomes a
pure serialization step for validated `BackProgram` data.

**Files to create:**
- `lua/moonlift/mom/driver/compile_module.mlua` — orchestrate full pipeline for a single module

**Test:** End-to-end: source string → native execution for every test in `tests/test_parse_typecheck.lua` that types correctly.

---

## Phase 15: Diagnostics and Inspection (does not exist)

**Oracle:** `lua/moonlift/back_diagnostics.lua` (35), `lua/moonlift/back_inspect.lua` (54), `lua/moonlift/back_program.lua` (55), `lua/moonlift/back_target_model.lua` (157).

**Files to create:**
- `lua/moonlift/mom/driver/back_diagnostics.mlua` — produce diagnostic output from BackProgram + issues
- `lua/moonlift/mom/driver/back_inspect.mlua` — command counts and structural statistics
- `lua/moonlift/mom/driver/back_target_model.mlua` — target platform model (pointer size, vector width, scalar encoding)

---

## Phase 16: Object and Shared Library Emission

**Status:** `host_mom.emit_object` works through MOM wire format. No `emit_shared` for the native path.

**Files to create:**
- `lua/moonlift/mom/driver/object_driver.mlua` — validated `BackProgram` → relocatable `.o`
- `lua/moonlift/mom/driver/shared_driver.mlua` — validated `BackProgram` → `.so`/`.dylib` via link plan

---

## Dependency Graph

```
Phase 0 (Schema) ✅
  └─ Phase 1 (Doc scanner) ✅
  └─ Phase 2 (Lexer) ✅
  └─ Phase 3 (Parser) ✅
       ├─ Phase 9b (Typecheck) ← current phase
       │    └─ Phase 9c (Layout resolve)
       │         └─ Phase 10 (ABI helpers)
       │              ├─ Phase 11 (Binding/memory)
       │              │    └─ Phase 12 (Func/module lowering)
       │              │         └─ Phase 14 (Pipeline wiring)
       │              │              └─ Phase 15 (Diagnostics)
       │              │                   └─ Phase 16 (Object/shared emission)
       │              ├─ Phase 5 (Expr lowering) ← needs type tape
       │              └─ Phase 6 (Stmt lowering) ← needs type tape + env
       ├─ Phase 7 (Control fact extraction)
       │    └─ Phase 8 (Control lowering) ← needs typed AST
       └─ Phase 4 (Cmd constructors) ← independent, can proceed now
            └─ Phase 13 (Vectorization) ← needs Phase 12
```

Phases 4, 5, and 6 can proceed now (with type tape as parameter, hardcoded
scalars where needed). Phase 9 (type system) unblocks correct lowering and
is the highest-priority blocker for a working pipeline.

Open expansion (9a) is deferred: `@{}` splice resolution happens at the Lua
staging layer before source reaches the MOM native compiler.

---

## Naming Convention

| Layer | Prefix | Example |
|-------|--------|---------|
| parser | `mp_` | `mp_parse_expr`, `mp_accept` |
| open | `mo_` | `mo_expand_stmt` |
| typecheck | `mt_` | `mt_type_expr` |
| layout | `ml_` | `ml_resolve_field` |
| backend lowering | `mb_` | `mb_lower_expr` |
| control lowering | `mc_` | `mc_lower_region` |
| vector | `mv_` | `mv_plan_kernel` |
| validation | `mbv_` | `mbv_validate_cmds` |
| runtime/util | `mr_` | `mr_push_issue` |

---

## Verification Checklist (run after every change)

```sh
# Foundation (run always)
luajit tests/test_mom_groundwork.lua
luajit tests/test_mom_validate.lua
luajit tests/test_mom_check_correctness.mlua

# Parser (run when touching parser/)
luajit tests/test_mom_document_scan.lua
luajit tests/test_mom_native_lexer.mlua
luajit tests/test_mom_native_core.lua
luajit tests/test_mom_native_tree.lua

# Wire and CLI
luajit tests/test_mom_wire.lua
luajit tests/test_mom_source_to_binary.lua
luajit tests/test_mom_cli.lua

# Vectorization
luajit tests/test_mom_vec.lua
```

Add a new test file for each phase and add it to this checklist.

---

## Files to Create (Complete List)

| Phase | File | Purpose |
|-------|------|---------|
| 4 | (modify) `mom/back/cmd.mlua` | Add 30 missing Cmd constructors |
| 4 | (modify) `mom/back/validate.mlua` | Add validation for new Cmd variants |
| 5 | (modify) `mom/back/expr_lower.mlua` | Add 12 missing expression lowerers |
| 5 | (modify) `mom/back/stmt_lower.mlua` | Import from expr_lower, remove duplication |
| 9b | `mom/typecheck/type_scalar.mlua` | Scalar predicates and literal adoption |
| 9b | `mom/typecheck/type_env.mlua` | Scoped name→type map using I32Map |
| 9b | `mom/typecheck/type_classify.mlua` | Type tag → classification |
| 9b | `mom/typecheck/type_expr.mlua` | Expression type inference (all 20 tags) |
| 9b | `mom/typecheck/type_stmt.mlua` | Statement type checking + flow |
| 9b | `mom/typecheck/type_module.mlua` | Module env building + item typing |
| 9c | `mom/layout/layout_env.mlua` | Type → storage info mappings |
| 9c | `mom/layout/layout_field.mlua` | Struct/union field offset computation |
| 9c | `mom/layout/layout_resolve.mlua` | Rewrite pass: layout-aware forms |
| 7 | `mom/back/back_control_facts.mlua` | Full control fact extraction |
| 7 | `mom/back/back_control_validate.mlua` | Full control validation |
| 8 | `mom/back/back_control_lower.mlua` | Lower control regions to target CFG |
| 9a | `mom/open/open_facts.mlua` | Walk AST, find splice slots and fragment use sites |
| 9a | `mom/open/open_validate.mlua` | Check fill types, param arity, imports |
| 9a | `mom/open/open_expand.mlua` | Rewrite open constructs, inline fragments |
| 10 | `mom/back/back_abi.mlua` | ABI classification, func ABI plan |
| 11 | `mom/back/back_residence.mlua` | Binding residence gather/decide/machine |
| 12 | `mom/back/back_func.mlua` | Function-level lowering orchestration |
| 12 | `mom/back/back_module.mlua` | Module-level lowering orchestration |
| 13 | (rewrite) `mom/vec/vec_facts.mlua` | Real loop recognition |
| 13 | (rewrite) `mom/vec/vec_decide.mlua` | Real legality + lane decision |
| 13 | (rewrite) `mom/vec/vec_plan.mlua` | Real kernel planning |
| 13 | (rewrite) `mom/vec/vec_lower.mlua` | Real vector instruction emission |
| 13 | `mom/vec/vec_safety.mlua` | Alias and dependency analysis |
| 13 | `mom/vec/vec_validate.mlua` | Vector kernel correctness verification |
| 14 | (modify) `mom/driver/lower_wire.mlua` | Thin serialization of validated BackProgram |
| 14 | (modify) `host_mom.lua` | Insert semantic phases |
| 14 | `mom/driver/compile_module.mlua` | Full pipeline orchestration |
| 15 | `mom/driver/back_diagnostics.mlua` | Diagnostic output from BackProgram |
| 15 | `mom/driver/back_inspect.mlua` | Command counts and statistics |
| 15 | `mom/driver/back_target_model.mlua` | Target platform model |
| 16 | `mom/driver/object_driver.mlua` | BackProgram → .o |
| 16 | `mom/driver/shared_driver.mlua` | BackProgram → .so/.dylib |

**Total new files: ~30. Total rewrites: 4. Total modifications: 6.**

---

## Estimated Line Counts

| Phase | New LOC | Cumulative |
|-------|--------:|-----------:|
| 4. Cmd constructors | 800 | 800 |
| 5. Expr lowering (complete) | 400 | 1,200 |
| 6. Stmt lowering (complete) | 300 | 1,500 |
| 7. Control facts/validation | 400 | 1,900 |
| 8. Control lowering | 500 | 2,400 |
| 9a. Open expansion | 600 | 3,000 |
| 9b. Typecheck | 2,500 | 5,500 |
| 9c. Layout resolve | 800 | 6,300 |
| 10. ABI helpers | 300 | 6,600 |
| 11. Binding/memory | 350 | 6,950 |
| 12. Func/module lowering | 800 | 7,750 |
| 13. Vectorization (real) | 1,500 | 9,250 |
| 14. Pipeline wiring | 400 | 9,650 |
| 15. Diagnostics/inspection | 200 | 9,850 |
| 16. Object/shared emission | 300 | 10,150 |

**Total estimated: ~10,150 new lines of Moonlift.**