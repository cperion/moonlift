# C backend implementation plan 
Implementation planning for the Lalin C backend side projection described in C_BACKEND_DESIGN.md and represented by LalinC.CBackend* ASDL nodes.
**Workflow ID**: wf-c-backend-impl
**Started**: 2026-06-08 08:14:05
---

## Edit-planner Output — 2026-06-08 08:19:08

### Precondition Checks

- Confirm `lua/lalin/c/c_type.lua` still defines `LalinC.CBackendUnit` at lines 513-523 and no validation/report ASDL nodes exist yet.
- Confirm `lua/lalin/schema/init.lua` already requires `lalin.c.c_type` at line 14; do not add a second schema include.
- Confirm `lua/lalin/frontend_pipeline.lua` still lowers only to LalinBack at lines 31-76 and returns only `lower_module`, `parse_and_lower`, `assert_no_cmd_trap` at lines 198-202.
- Confirm `lua/lalin/init.lua` public facade still has `emit_object`/`emit_shared` only; add C emission without changing existing APIs.
- Confirm Cranelift path tests still pass before large integration: `luajit tests/test_schema_compile_pipeline.lua`.

---

### Files to Modify

#### `lua/lalin/c/c_type.lua`

**Goal**: Add ASDL validation report nodes for the C backend projection.

**Edit blocks**:
1. **After lines 513-523**: Add `CBackendValidationIssue` and `CBackendValidationReport`.
   - After:
     ```lua
     A.sum "CBackendValidationIssue" {
         A.variant "CBackendIssueDuplicateSig" { ... },
         A.variant "CBackendIssueMissingSig" { ... },
         A.variant "CBackendIssueDuplicateFunc" { ... },
         A.variant "CBackendIssueMissingFunc" { ... },
         A.variant "CBackendIssueDuplicateExtern" { ... },
         A.variant "CBackendIssueMissingExtern" { ... },
         A.variant "CBackendIssueDuplicateGlobal" { ... },
         A.variant "CBackendIssueMissingGlobal" { ... },
         A.variant "CBackendIssueDuplicateHelper" { ... },
         A.variant "CBackendIssueMissingHelper" { ... },
         A.variant "CBackendIssueDuplicateLocal" { ... },
         A.variant "CBackendIssueMissingLocal" { ... },
         A.variant "CBackendIssueDuplicateLabel" { ... },
         A.variant "CBackendIssueMissingLabel" { ... },
         A.variant "CBackendIssueInvalidCName" { ... },
         A.variant "CBackendIssueDuplicateCName" { ... },
         A.variant "CBackendIssueFuncSigMismatch" { ... },
         A.variant "CBackendIssueBlockArgCount" { ... },
         A.variant "CBackendIssueBlockArgType" { ... },
         A.variant "CBackendIssueCallArgCount" { ... },
         A.variant "CBackendIssueCallArgType" { ... },
         A.variant "CBackendIssueCallResultType" { ... },
         A.variant "CBackendIssueIndirectCallNonCodePtr" { ... },
         A.variant "CBackendIssueDataCodePtrConfusion" { ... },
         A.variant "CBackendIssueHelperMismatch" { ... },
         A.variant "CBackendIssueInvalidAlignment" { ... },
         A.variant "CBackendIssueDataInitOutOfBounds" { ... },
     }

     A.product "CBackendValidationReport" {
         A.field "issues" (A.many "LalinC.CBackendValidationIssue"),
         A.unique,
     },
     ```
   - Quirk: keep these after `CBackendUnit` and before the module closing `}`.

**Danger zones**:
- Do not rename or reorder existing `CBackend*` nodes unless all schema tag tests are intentionally updated.
- Do not use one generic string-only issue variant; validation should preserve typed references.

---

#### `lua/lalin/frontend_pipeline.lua`

**Goal**: Add a sibling C pipeline without altering the existing LalinBack path.

**Edit blocks**:
1. **Lines 31-35**: Add requires inside `M.Define(T)`.
   ```lua
   local TreeToC = require("lalin.tree_to_c").Define(T)
   local CValidate = require("lalin.c_validate").Define(T)
   ```

2. **After existing `lower_module` function, before `parse_and_lower`**: Add `lower_module_to_c(module, opts)`.
   - Reuse parse/open/closure/typecheck/layout sequence from `lower_module`.
   - Replace:
     ```lua
     local program, provenance = Lower.module(...)
     local back_report = Validate.validate(...)
     ```
     with:
     ```lua
     local c_unit = TreeToC.module(resolved, opts.c_opts or opts)
     local c_report = CValidate.validate(c_unit, collector)
     ```
   - Return table with:
     `expanded`, `open_report`, `closed`, `checked`, `resolved`, `c_unit`, `c_report`.

3. **After `parse_and_lower`**: Add `parse_and_lower_c(src, opts)` mirroring `parse_and_lower`, including source anchors, then calling `lower_module_to_c`.

4. **Lines 198-202 return table**: Add:
   ```lua
   lower_module_to_c = lower_module_to_c,
   parse_and_lower_c = parse_and_lower_c,
   ```

**Danger zones**:
- Do not call `tree_to_back` or `back_validate` in C path.
- Do not remove provenance/back trap checks from existing path.

---

#### `lua/lalin/init.lua`

**Goal**: Expose public source-to-C emission.

**Edit blocks**:
1. **Near lines 39-43**: Add module exports:
   ```lua
   M.type_to_c = require("lalin.type_to_c")
   M.tree_to_c = require("lalin.tree_to_c")
   M.c_validate = require("lalin.c_validate")
   M.c_emit = require("lalin.c_emit")
   M.c_helpers = require("lalin.c_helpers")
   ```

2. **After `emit_shared`, before CLI section**: Add:
   ```lua
   function M.emit_c(src, path, name, opts)
       ...
   end
   ```
   - Build fresh ASDL context.
   - Call `Pipeline.Define(T).parse_and_lower_c(src, { site = "emit_c", c_opts = opts })`.
   - Error if `#result.c_report.issues ~= 0`.
   - Emit via `require("lalin.c_emit").Define(T).emit(result.c_unit, opts)`.
   - Write text if `path` supplied.
   - Return source string.

**Danger zones**:
- Keep return type as string, not artifact object.
- Do not change `emit_object` / `emit_shared`.

---

#### `lua/lalin/host_module_values.lua`

**Goal**: Add builder/bundle C emission methods.

**Edit blocks**:
1. **After `BundleValue:emit_object` around lines 255-263**: Add:
   ```lua
   function BundleValue:emit_c(opts)
       ...
   end
   ```
   - Use `self:_lower_c_unit(opts)` or inline C pipeline equivalent.
   - Emit source with `c_emit`.

2. **After `BundleValue:object` or near object/library methods**: Add:
   ```lua
   function BundleValue:c_source(path_or_opts)
       ...
   end
   ```
   - Accept string path or opts table.
   - Write if `opts.c_path` / `opts.source_path` provided.
   - Return source string.

**Danger zones**:
- `_lower_program` returns LalinBack; do not reuse it for C.
- Preserve existing `compile`, `object`, and `library` behavior.

---

### New Files

#### `lua/lalin/type_to_c.lua`

- **Purpose**: Project Lalin semantic types to `LalinC.CBackendType`.
- **Contents sketch**:
  - `local pvm = require("lalin.pvm")`
  - `function M.Define(T)` with `T._lalin_api_cache.type_to_c`.
  - API:
    - `scalar_to_c(scalar)`
    - `type_to_c(ty, ctx)`
    - `func_sig_id(params, result)`
    - `ensure_sig(ctx, params, result)`
    - `default_target(opts)`
  - Mappings:
    - `ScalarVoid -> CBackendVoid`
    - `ScalarBool -> CBackendBool8`
    - integer/floats -> `CBackendScalar(scalar)`
    - `ScalarRawPtr -> CBackendDataPtr(nil)`
    - `ScalarIndex -> CBackendIndex`
    - `TPtr(elem) -> CBackendDataPtr(project(elem))`
    - `TFunc(params, result) -> CBackendCodePtr(sig)`
    - `TCFuncPtr(sig) -> CBackendCodePtr(converted sig id)`
    - `TCType(id) -> CBackendNamed(id)`
    - `TNamed(TypeRefGlobal)` -> `CBackendNamed(CTypeId(module, name))`
- **Imports required**: `pvm`, `LalinCore`, `LalinType`, `LalinC`.

---

#### `lua/lalin/c_helpers.lua`

- **Purpose**: Helper registry and helper C body generation.
- **Contents sketch**:
  - `helper_key(kind)` deterministic by variant + fields.
  - `helper_id(kind)` stable names like `ml_i32_add_wrap`, `ml_load_i32`, `ml_trap`.
  - `register(ctx, kind)` deduplicates `CBackendHelperUse`.
  - `helper_signature(use)` for validator/emitter.
  - `emit_helper(use, emit_type)` returns source lines.
- **Must support**:
  - wrapping int arithmetic
  - checked div/rem
  - shifts
  - intrinsics
  - load/store via `memcpy`
  - `memcpy`/`memset`/`memcmp`
  - trap helper

---

#### `lua/lalin/tree_control_to_c.lua`

- **Purpose**: Lower explicit Lalin control regions to C backend label/goto blocks.
- **Contents sketch**:
  - `Define(T, base)`
  - `stmt_region_to_c`
  - `expr_region_to_c`
  - block label helpers:
    - `label_id(region_id, label)`
    - `block_param_local(region_id, label, param)`
  - Validate with `tree_control_facts`.
  - Emit `CBackendBlock` values with explicit `params`, `stmts`, `term`.
- **Important**: preserve jump argument parallel assignment via block params; emitter handles transfer temps.

---

#### `lua/lalin/tree_to_c.lua`

- **Purpose**: Project resolved `LalinTree.Module` to `LalinC.CBackendUnit`.
- **Contents sketch**:
  - `Define(T)`
  - context:
    ```lua
    {
      module_name,
      target,
      sigs = {},
      types = {},
      globals = {},
      externs = {},
      helpers = {},
      funcs = {},
      next_local = 0,
      next_label = 0,
    }
    ```
  - `module(module, opts)`
  - `item_to_c`
  - `func_to_c`
  - `extern_to_c`
  - `data_to_c`
  - `expr_to_c(expr, ctx)` returning atom + appended stmts
  - `stmt_to_c(stmt, ctx)`
  - delegate `ExprControl`/`StmtControl` to `tree_control_to_c`.
- **Lowering rules**:
  - shallow expressions only.
  - unsafe integer arithmetic/memory use helpers.
  - direct calls use `CBackendCallDirect`.
  - extern calls use `CBackendCallExtern`.
  - function pointer calls use `CBackendCallIndirect` with exact sig.

---

#### `lua/lalin/c_validate.lua`

- **Purpose**: Validate `CBackendUnit`.
- **Contents sketch**:
  - `Define(T)`
  - `validate(unit, collector)`
  - indexes for sigs/types/globals/externs/helpers/functions.
  - per-function checks:
    - param count/types match sig.
    - local ids unique.
    - labels unique.
    - all atom refs exist.
    - block terminators exactly one by ASDL structure.
    - goto arg count/type matches block params.
    - call arg/result matches sig.
    - indirect callee atom has `CBackendCodePtr(sig)`.
  - unit checks:
    - C names sanitized and unique.
    - globals initializer bounds.
    - helper kind/id consistency.
    - no data/code pointer confusion.
- **Return**: `LalinC.CBackendValidationReport(issues)`.

---

#### `lua/lalin/c_emit.lua`

- **Purpose**: Deterministic C printer.
- **Contents sketch**:
  - `Define(T)`
  - `emit(unit, opts) -> string`
  - Section order:
    1. generated comment
    2. includes
    3. signature typedefs
    4. type declarations
    5. extern declarations
    6. globals/data
    7. helpers
    8. function prototypes
    9. function definitions
  - Emit block params using transfer temps:
    ```c
    __xfer_loop_i = ...;
    __xfer_loop_acc = ...;
    goto loop;

    loop:
      loop_i = __xfer_loop_i;
      loop_acc = __xfer_loop_acc;
    ```
- **Danger zone**: never reconstruct loops; emit labels/gotos only.

---

#### Tests

Create:

- `tests/test_type_to_c.lua`
- `tests/test_c_helpers.lua`
- `tests/test_c_validate.lua`
- `tests/test_c_emit.lua`
- `tests/test_tree_to_c_smoke.lua`
- `tests/test_emit_c_api.lua`

Optionally modify:

#### `tests/test_schema_types_smoke.lua`

- Add assertions for:
  ```lua
  assert(blob:match("type LalinC_CBackendUnit ="), ...)
  assert(ty.LalinC.CBackendUnit ~= nil, ...)
  ```

---

### Order of Operations

1. Add validation ASDL nodes in `c_type.lua`.
2. Implement `type_to_c.lua`.
3. Implement `c_helpers.lua`.
4. Implement `tree_control_to_c.lua`.
5. Implement `tree_to_c.lua`.
6. Implement `c_validate.lua`.
7. Implement `c_emit.lua`.
8. Add C pipeline entry points to `frontend_pipeline.lua`.
9. Add public APIs in `init.lua` and `host_module_values.lua`.
10. Add unit tests for type projection/helper registry.
11. Add validation/emission tests using hand-built units.
12. Add end-to-end C pipeline/API smoke tests.
13. Run focused test suite plus one existing Cranelift regression.

---

### Testing Strategy

Run incrementally:

```sh
luajit tests/test_schema_types_smoke.lua
luajit tests/test_type_to_c.lua
luajit tests/test_c_helpers.lua
luajit tests/test_c_validate.lua
luajit tests/test_c_emit.lua
luajit tests/test_tree_to_c_smoke.lua
luajit tests/test_emit_c_api.lua
luajit tests/test_schema_compile_pipeline.lua
```

For emitted C syntax tests, use `cc -std=c99 -fsyntax-only` only when `cc` exists; otherwise skip with a printed message.

---

### Structured Edit Plan Sidecar

Updated workflow sidecar `wf-c-backend-impl` revision `r1` with 14 tasks:

- `T001` ASDL validation nodes
- `T002` type projection
- `T003` helper registry
- `T004` control projection
- `T005` tree-to-C unit projection
- `T006` validation
- `T007` emission
- `T008` frontend pipeline
- `T009` public facade API
- `T010` builder API
- `T011` type/helper tests
- `T012` validation/emission tests
- `T013` end-to-end/API tests
- `T014` focused test run

---

### Pattern Memo

- Use `pvm.classof(x)` for ASDL dispatch; do not inspect `_variant`.
- Every module exposes `M.Define(T)` and caches API in `T._lalin_api_cache` where reusable.
- C backend names must be sanitized once and validated for uniqueness.
- C emission is deterministic and label/goto based; no loop reconstruction.
- Unsafe C behavior is contained in helpers; do not open-code overflowing arithmetic or unaligned loads/stores.

## Worker Output — 2026-06-08 08:50:57

## Completed
- Claimed and completed `T013`.
- Added end-to-end C backend smoke/API tests.
- Fixed C backend issues needed for those tests:
  - expression-control `return block ...` lowering
  - block-param bindings in C control projection
  - switch `raw_key` case literal lowering
  - zero-field `CBackendVoid`/`Bool8`/`Index` type handling in emitter/helpers/validator

## Files Changed
- `tests/test_tree_to_c_smoke.lua` - new parse/lower/emit smoke test for add, if, switch, block loop, extern call.
- `tests/test_emit_c_api.lua` - new `lalin.emit_c` and `BundleValue:c_source` API test.
- `lua/lalin/tree_to_c.lua` - expression-control return lowering and void detection fix.
- `lua/lalin/tree_control_to_c.lua` - block-param env bindings and switch arm literal lowering.
- `lua/lalin/c_emit.lua` - fixed zero-field C backend type emission.
- `lua/lalin/c_helpers.lua` - fixed zero-field C backend type suffix/emission fallback.
- `lua/lalin/c_validate.lua` - fixed void result validation check.

## Notes
Checks run:
- `luajit tests/test_tree_to_c_smoke.lua`
- `luajit tests/test_emit_c_api.lua`
- `luajit tests/test_type_to_c.lua`
- `luajit tests/test_c_helpers.lua`
- `luajit tests/test_c_validate.lua`
- `luajit tests/test_schema_compile_pipeline.lua`

No ready tasks remain. `T012` is still claimed by another worker, so `T014` is not ready yet.
