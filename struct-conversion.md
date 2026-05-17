# MOM Struct Conversion Implementation Plan

 Context

 The MOM codebase currently uses raw aux_i32 array arithmetic with manual offset calculations throughout the backend lowering pipeline. The
 struct-conversion.md guide outlines a comprehensive refactoring to replace this with properly typed, schema-defined structs.

 Why this change: The current approach is error-prone (manual offset math), hard to read (complex arithmetic instead of named fields), and
 doesn't leverage the type system. Struct-based code will be more maintainable, safer (caught by typechecker), and clearer to understand.

 Current State Assessment:

- ✅ 4 existing structs: MomBackLowerCtx, MomBackLocalEnv, MomBackIdAllocator, CmdEntry already exist
- ❌ 11 missing structs: None of the workspace/result/table/slice structs from the conversion guide exist yet
- ❌ All lowering code: Uses raw aux_i32 arithmetic with manual offset calculations
- ❌ All continuations: Use tuple outputs like (value, scalar, ok) instead of struct results
- ⚠️ Critical blocker discovered: expr_lower.mlua uses ctx.last_expr_value/scalar/ok/addr fields (60+ references) that don't exist in
 MomBackLowerCtx struct definition (bug in current code)

 Critical Files

 Schema:

- lua/moonlift/mom/schema/MoonBack.mlua - Add all 11 missing structs here

 Backend lowering (conversion sites):

- lua/moonlift/mom/back/lower_ctx.mlua - MomBackLowerCtx struct (add missing fields)
- lua/moonlift/mom/back/control_lower.mlua - 100% raw aux_i32, needs MomControlRegionWorkspace
- lua/moonlift/mom/back/expr_lower.mlua - 32 continuation sites, uses missing context fields
- lua/moonlift/mom/back/stmt_lower.mlua - 25 continuation sites, phi table conversions
- lua/moonlift/mom/back/address.mlua - 8 continuation sites

 Supporting:

- lua/moonlift/mom/back/module.mlua - Function signatures (MomFuncSig)
- lua/moonlift/mom/back/validate.mlua - Command slices (MomCmdSlice)
- lua/moonlift/mom/vec/*.mlua - Vector fact slices (MomVecFactSlice)

 Missing Structs (must add to schema)

 All 11 structs from the conversion guide need to be defined:

 1. MomExprResult - value: i32, scalar: i32, ok: bool
 2. MomStmtResult - flow: i32, ok: bool
 3. MomAddressResult - addr: i32, pointee_scalar: i32, ok: bool
 4. MomControlRegionWorkspace - ctrl_start, n_blocks, block_ids: view(i32), param_vals: view(i32), exit_blk, is_expr, result_scalar,
 result_val
 5. MomIfPhiEntry - name_tok, param_val, scalar
 6. MomIfPhiTable - entries: view(MomIfPhiEntry), n_changed, then_blk, else_blk, join_blk
 7. MomSwitchCaseEntry - key_val, target_blk
 8. MomSwitchCaseTable - entries: view(MomSwitchCaseEntry), n_cases, default_blk
 9. MomFuncSig - params_aux: view(i32), n_params, result_aux: view(i32), n_results, sig_id, func_id
 10. MomCmdSlice - tag: ptr(i32), a..f: ptr(i32), n: i32 (6-parallel arrays)
 11. MomVecFactSlice - Same as MomCmdSlice for vectorization

 Implementation Strategy

 Recommended Approach: Bottom-Up (Result Structs First)

 The conversion guide recommends starting with control_lower.mlua (most complex), but analysis reveals bottom-up is better:

 Why bottom-up:

 1. Dependency order: control_lower.mlua calls expr/stmt lowering (lines 123, 247, 261) - must convert callees before callers
 2. Complexity gradient: Start simple (3-field MomExprResult) → build to complex (8-field MomControlRegionWorkspace with views)
 3. Risk management: Fail fast on simple struct vs. many variables in complex workspace
 4. Learning curve: Build confidence with result structs before workspace threading

 Phase 0: Fix Context Fields (BLOCKING - 30 min)

 Problem: expr_lower.mlua uses ctx.last_expr_value, ctx.last_expr_scalar, ctx.last_expr_ok, ctx.last_addr (60+ references) but these fields
 don't exist in MomBackLowerCtx definition.

 Solution: Add to MomBackLowerCtx struct in lower_ctx.mlua:
 -- Function-based lowering results (avoids region-in-region restriction)
 last_expr_value: i32
 last_expr_scalar: i32
 last_expr_ok: bool
 last_addr: i32
 last_pointee_scalar: i32

 Verification: cargo build --release && luajit tests/test_mom_groundwork.lua

 Phase 1: MomExprResult (3-4 hours)

 Simplest struct, broadest impact (4 files)

 1. Add MomExprResult struct to MoonBack.mlua
 2. Convert mb_lower_expr_region continuation signature (expr_lower.mlua:469)

- From: done: cont(value: i32, scalar: i32, ok: bool)
- To: done: cont(result: MomExprResult)

 1. Update all exit points in expr_lower.mlua (~15 sites):

- From: jump done(value = val, scalar = scl, ok = true)
- To: jump done(result = MomExprResult(value = val, scalar = scl, ok = true))

 1. Update call sites:

- control_lower.mlua: 7 sites
- stmt_lower.mlua: 10 sites
- address.mlua: 3 sites
- From: emit mb_lower_expr_region(ctx, idx, value, scalar, ok)
- To: emit mb_lower_expr_region(ctx, idx; done = cont(result: MomExprResult)) then destructure

 Test: func main() -> i32 return 2 + 2 end

 Phase 2: MomStmtResult + MomAddressResult (4 hours)

 1. Add both structs to MoonBack.mlua
 2. Convert stmt_lower.mlua:

- mb_lower_stmt signature + 10 exit points + 15 call sites
- mb_lower_if_stmt, mb_lower_switch_stmt signatures

 1. Convert address.mlua:

- mb_place_addr_to_back signature + exits
- mb_index_addr_to_back signature + exits
- Add mb_place_addr_to_back_fn, mb_index_addr_to_back_fn wrappers (required by expr_lower.mlua lines 191, 205)

 Test: func main() -> i32 let x = 2; var y = x; return y end

 Phase 3: MomControlRegionWorkspace (6 hours)

 Most complex: 8 fields including view types, threading through 3 blocks

 1. Add struct to MoonBack.mlua with all 8 fields
 2. Add mb_build_region_workspace constructor in control_lower.mlua:

- Computes total_params (sum across blocks)
- Creates views into aux_i32 for block_ids and param_vals
- Returns workspace struct

 1. Thread workspace through control_lower.mlua blocks:

- init_params(pi: i32, aux: ptr(@{MomControlRegionWorkspace}))
- lower_blocks(bi: i32, aux: ptr(@{MomControlRegionWorkspace}))
- seal_exit(aux: ptr(@{MomControlRegionWorkspace}))

 1. Replace ALL aux_i32 offset arithmetic:

- Line 84: ctx.aux_i32.data[block_ids_aux + bi] → aux.block_ids[bi]
- Line 143: Complex param offset calculation → aux.param_vals.data + total_before
- Line 188: Result value offset → aux.result_val

 Test: luajit tests/test_mom_control_lower.lua (if exists) or control flow test

 Phase 4: Phi/Switch Table Structs with True Struct Arenas (6-7 hours)

 Approach: Add typed struct arenas to MomBackLowerCtx for proper struct allocation (cleaner than accessor pattern).

 Context redesign needed:

 1. Add to MomBackLowerCtx (lower_ctx.mlua):
 -- Typed arenas for control structures
 phi_entries: ptr(@{MomI32Builder})     -- builder for MomIfPhiEntry structs
 switch_entries: ptr(@{MomI32Builder})  -- builder for MomSwitchCaseEntry structs
 1. OR use existing builders with struct casting - TBD based on MomI32Builder capabilities
 1. Initialize in mb_ctx_init (add arena initialization)

 Conversion sites:

 1. If-phi tables (stmt_lower.mlua - NEW implementation):

- Current: No phi table at all (simplified if-lowering)
- Target:
  - Implement mb_collect_changed_bindings region to compare then/else branch environments
  - Build MomIfPhiTable with entries array
  - Allocate join-block parameters for changed bindings
  - Rebind environment after join
- Key challenge: Environment snapshot/comparison logic doesn't exist yet

 1. Switch-case tables (control_lower.mlua lines 392-406):

- Current: Interleaved [key_val, target_blk, ...] in aux_i32
- Target:
  - Allocate MomSwitchCaseEntry array
  - Build MomSwitchCaseTable with proper view
  - Pass struct to mb_emit_switch_int (signature change needed)

 Helper functions to add:

- mb_ctx_fresh_phi_table(ctx, n_changed) - allocates phi table in arena
- mb_ctx_fresh_switch_table(ctx, n_cases) - allocates switch table in arena
- mb_emit_switch_int signature change to accept MomSwitchCaseTable instead of cases_aux, n_cases

 Test:

- If: let x = 1; if cond then x = 2 end; return x (requires phi)
- Switch: switch val case 0: return 1 case 1: return 2 default: return 3 end

 Phase 5: Infrastructure Structs (4-5 hours)

 Lower priority, less invasive

 1. MomFuncSig (module.mlua):

- Replace separate params_aux, n_params, result_aux, n_results args
- Single struct parameter to mb_lower_func/mb_lower_extern

 1. MomCmdSlice (validate.mlua):

- Replace 6+ separate array pointers to single slice struct
- mb_validate signature: (cmds: MomCmdSlice, ...) instead of (ct, ca, cb, cc, cd, ce, cf, n, ...)

 1. MomVecFactSlice (vec/*.mlua):

- Same pattern for vectorization fact tapes

 Test: Full test ladder

 Verification Strategy

 After each phase:

 1. Compile: cargo build --release
 2. Run relevant tests: Focus test from the ladder
 3. Run hygiene check: luajit scripts/check_mom_hygiene.lua
 4. Verify no regressions: Run full test suite

 Estimated Timeline
 ┌───────┬───────────────────────────────┬─────────┬─────────────────────────────────────────────────────────────────────────────────┐
 │ Phase │          Description          │  Time   │                                      Risk                                       │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 0     │ Fix context fields            │ 30 min  │ Low (simple addition)                                                           │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 1     │ MomExprResult                 │ 3-4 hrs │ Low (simple struct, clear pattern)                                              │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 2     │ MomStmtResult + Address       │ 4 hrs   │ Medium (2 structs, func wrappers)                                               │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 3     │ MomControlRegionWorkspace     │ 6 hrs   │ High (complex workspace threading)                                              │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 4     │ Phi/Switch with struct arenas │ 7-8 hrs │ Very High (arena design, changed-binding logic NEW, if-phi not implemented yet) │
 ├───────┼───────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────────────────┤
 │ 5     │ Infrastructure                │ 4-5 hrs │ Low (isolated changes)                                                          │
 └───────┴───────────────────────────────┴─────────┴─────────────────────────────────────────────────────────────────────────────────┘
 Total: 24.5-29.5 hours

 Critical Risks:

- Phase 0 is blocking - must do first, all code currently broken without these fields
- Phase 4 most complex - requires implementing changed-bindings collection (doesn't exist), arena integration, and full if-phi protocol
 (currently simplified)
- Phase 4 arena design - need to decide struct allocation strategy (reuse MomI32Builder with casting or new typed builders)
- Testing gaps - if-phi tracking needs new test cases to validate changed-binding detection
- Edge cases may require rework in any phase

 Design Decisions (Confirmed)

 1. Context fields: ✓ Add missing last_expr_* fields to MomBackLowerCtx - fixes the bug, keeps function-based pattern for region-in-region
 workaround
 2. Phase order: ✓ Bottom-up (results → workspace) - respects dependencies, builds confidence with simple structs first
 3. Phi tables: ✓ Implement full MomIfPhiTable with changed-binding tracking per guide
 4. Struct arena: ✓ True struct arena with typed views - add phi_arena and switch_arena to MomBackLowerCtx for proper struct allocation

 ---
 Implementation Summary (Quick Reference)

 Phase 0: Context Fields (MUST DO FIRST)

- File: lua/moonlift/mom/back/lower_ctx.mlua
- Add 5 fields to MomBackLowerCtx struct (lines 32-70): last_expr_value, last_expr_scalar, last_expr_ok, last_addr, last_pointee_scalar
- Initialize in mb_ctx_init if needed
- Test: cargo build --release

 Phase 1: MomExprResult

- File: lua/moonlift/mom/schema/MoonBack.mlua - add struct definition
- File: lua/moonlift/mom/back/expr_lower.mlua - convert continuation (line 469) + ~15 exit sites
- Files: control_lower.mlua (7 sites), stmt_lower.mlua (10 sites), address.mlua (3 sites) - update call sites
- Test: func main() -> i32 return 2 + 2 end

 Phase 2: MomStmtResult + MomAddressResult

- File: lua/moonlift/mom/schema/MoonBack.mlua - add 2 struct definitions
- File: lua/moonlift/mom/back/stmt_lower.mlua - convert mb_lower_stmt + if/switch signatures
- File: lua/moonlift/mom/back/address.mlua - convert mb_place_addr_to_back, add _fn wrappers
- Test: func main() -> i32 let x = 2; var y = x; return y end

 Phase 3: MomControlRegionWorkspace

- File: lua/moonlift/mom/schema/MoonBack.mlua - add struct with 8 fields including views
- File: lua/moonlift/mom/back/control_lower.mlua:
  - Add mb_build_region_workspace constructor
  - Thread workspace through init_params, lower_blocks, seal_exit (3 blocks)
  - Replace ALL aux_i32 arithmetic (lines 84, 143, 188+)
- Test: Control flow test with blocks/jumps

 Phase 4: Phi/Switch Arenas

- File: lua/moonlift/mom/schema/MoonBack.mlua - add MomIfPhiEntry, MomIfPhiTable, MomSwitchCaseEntry, MomSwitchCaseTable
- File: lua/moonlift/mom/back/lower_ctx.mlua - add arena fields to MomBackLowerCtx
- File: lua/moonlift/mom/back/stmt_lower.mlua:
  - NEW: Implement mb_collect_changed_bindings region
  - Convert if-lowering to build MomIfPhiTable (currently simplified, no phi)
  - Add rebinding logic after join block
- File: lua/moonlift/mom/back/control_lower.mlua:
  - Convert switch to use MomSwitchCaseTable (lines 392-406)
  - Update mb_emit_switch_int signature
- Test: If with changed var, switch with multiple cases

 Phase 5: Infrastructure

- File: lua/moonlift/mom/schema/MoonBack.mlua - add MomFuncSig, MomCmdSlice, MomVecFactSlice
- Files: module.mlua, validate.mlua, vec/*.mlua - convert to use structs
- Test: Full test ladder
