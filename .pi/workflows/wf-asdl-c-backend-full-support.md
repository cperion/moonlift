# ASDL Text + LalinCode + C Backend Full Support

Intent: document and plan the combined refactor that makes compact `.asdl` files the schema source of truth, introduces `LalinCode` as the normalized typed SSA/control layer, and rebases the C backend on that layer so C output is correct, complete, and naturally optimizable by default.

Canonical design artifact: `C_BACKEND_DESIGN.md`.


## Documenter Output — 2026-06-10 12:29:52

## Decision Record: ASDL source-of-truth + LalinCode + C-on-LalinCode

### Goal
Make compact ASDL text the canonical schema authoring format, introduce `LalinCode` as the normalized typed SSA/control IR between typed resolver output and backends, and move C emission to consume `LalinCode` (not nested LalinTree expressions) so C output becomes correct by construction, fully covered by coverage/validation, and naturally optimizable.

### Incentives
- The legacy C path in `lua/lalin/tree_to_c.lua` lowers nested `LalinTree` directly, inventing temporary values and control shape in the translator rather than operating on a normalized IR. This is the primary source of the `tcc`-specific code-shape artifacts versus cleaner native output.
- `C_BACKEND_DESIGN.md` already requires backend coverage classes to be `supported / phase_unreachable / language_rejected` with no silent “backend TODO” reclassification as completion; that cannot be enforced while lowering bypasses `tree_to_code`-style normalization.
- Dual schema formats (Lua builders + ASDL text) create drift risk; current migration work must finish and harden this to keep embedded and source-tree compilation deterministic.
- `LalinCode` is needed so both C and Cranelift-like backends can share a single semanticized representation and maintain native/C parity (especially tags, payloads, calls, places, and ABIs).

### Current State
#### 1) `.asdl` source-of-truth scaffolding is in place
- `lua/lalin/schema/init.lua` no longer constructs schema from Lua builder modules in-tree; it reads `lua/lalin/schema/*.asdl` via `SCHEMA_ASDL_MODULES`, using:
  - `AsdlText.load_text(modname, path)` → `AsdlText.parse_schema`.
  - `M.Define(T)` calls `context_define_schema.define`.
- `lua/lalin/schema/init.lua` currently appends only C-side schema via `lalin.c.c_type` and `lalin.c.c_ast` (still builder-based by design).
- `scripts/convert_schema_lua_to_asdl.lua` is a one-shot converter used to migrate existing Lua builder modules into `.asdl` (skips `init.lua`), confirming intended tooling.
- `src/build.rs` collects `*.asdl` files and embeds them as Lua preload modules named `<module>_asdl` (e.g., `lalin.schema.code_asdl`) via the generated `src/embedded_hosted_lua.rs`.
  `asdl_text.load_text` already resolves exactly this preload first, then falls back to file read.
- `lua/lalin/code.asdl` defines the LalinCode layer (values, blocks, places, calls, terms, globals/data globals/relocs, validation issues), matching the migration target.

#### 2) `LalinCode` ASDL is defined but not yet used as the lowering spine
- `LalinCode` currently exists as schema (`lua/lalin/schema/code.asdl`) with explicit constructs for:
  - typed SSA values, locals, blocks, block params,
  - explicit memory access and call targets,
  - place forms and storage distinctions,
  - control terms (`jump`, `branch`, `switch`, `variant switch`, `return`, `trap`),
  - data/global init facts and validation issues.
- There is no `lua/lalin/tree_to_code.lua`, `lua/lalin/code_to_c.lua`, or `lua/lalin/code_validate.lua` in tree.

#### 3) Current C frontend still uses legacy Tree-to-C modules
- `lua/lalin/frontend_pipeline.lua` `parse_and_lower_c` still calls `tree_to_c`.
- `lua/lalin/init.lua` still exports/uses `tree_to_c` and `type_to_c` in public-facing API wiring; `emit_c` builds from `c_unit = pipeline.parse_and_lower_c(...)`.
- `lua/lalin/host_module_values.lua` `_lower_c_unit` and `BundleValue:compile_c` still route through `lower_module_to_c` / C CUnit flow, which remains tree-based.
- `lua/lalin/tree_to_c.lua` remains the active C lowering module and depends on:
  `type_to_c`, `c_places`, `c_residence`, `c_cfg`, `c_data`, `c_layout`.

### Chosen Target
#### Approach (selected)
Use LalinTree normalization (`tree_to_code`) as the mandatory C backend front door, then emit C from LalinCode. Keep `LalinC` as the constrained C dialect and reuse existing emission/validation primitives.

#### Architecture (mandated)
Canonical migration pipeline:
```text
parse -> open_expand -> closure_convert -> tree_typecheck
-> sem_layout_resolve(target)
-> tree_to_code -> code_validate -> code_to_c -> c_validate -> c_emit
```
For parity with native backend, a mirrored path is expected:
```text
tree_to_code -> code_validate -> code_to_back -> back_validate -> back_jit/back_object
```
(If not fully migrated immediately, migration permits temporary bridge paths only behind explicit deprecation gates.)

#### Data flow / contracts to preserve
- `tree_to_code` must produce `CodeModule` with:
  - normalized `CodeInst` / `CodeTerm` graph (no raw nested-tree expression recursion),
  - explicit `CodePlace` and `CodeResidence` facts,
  - explicit `CodeCallTarget` (direct/extern/indirect/closure),
  - explicit `CodeMemoryAccess` and `CodeGlobalRef` for init/reloc correctness.
- `code_validate` is the sole source of LalinCode well-formedness enforcement (def/use, arity, type, terminator shape, pointer-vs-code class discipline).
- `code_to_c` should drive C generation from LalinCode block/term structure; C emission quality comes from IR shape, not from late recovery in printer.

#### Tradeoffs acknowledged
- Temporary duplication: existing tree-based `tree_to_c` path must continue as legacy until parity gates pass, but it is no longer the target architecture for final full-support milestones.
- More migration surface in call sites/tests and host-layer bindings, but this is accepted to avoid architectural drift and to make completion explicit.
- `LalinCode`-driven lowering should remove backend-local reconstruction but requires upfront validation and conversion discipline.

#### Public APIs that stay
Stable API surface must remain user-visible (re-routed, not removed):
- `lalin.emit_c`, `lalin.compile_c`
- `BundleValue:emit_c`, `BundleValue:compile_c`
- C runner/toolchain files: `lua/lalin/c_tcc.lua`, `lua/lalin/c_validate.lua`, `lua/lalin/c_emit.lua`, `lua/lalin/c_helpers.lua`
- C schema backend side: `lua/lalin/c/c_type.lua` stays (current migration keeps C schema in Lua builder form)
- Harness/tests/bench assets (`tests/test_c_gcc_harness.lua`, `benchmarks/bench_c_vs_cranelift.lua`) stay as long as behavior remains stable.

#### Direct Tree-to-C modules to retire (as planned target)
`lua/lalin/tree_to_c.lua`, `lua/lalin/tree_control_to_c.lua`, `lua/lalin/type_to_c.lua`,
`lua/lalin/c_places.lua`, `lua/lalin/c_residence.lua`, `lua/lalin/c_cfg.lua`,
`lua/lalin/c_data.lua`, `lua/lalin/c_layout.lua`
— migration goal is removal/replacement once `parse_and_lower_c` and public entry points are proven through `tree_to_code`/`code_to_*`.

#### Milestone/status language (current snapshot)
As of the current workflow (`wf-asdl-c-backend-full-support`, all tasks still pending), status is:
- `.asdl` source-of-truth: **partially migrated** (files exist, hardening/tests still pending).
- LalinCode normalization layer: **designed in schema, not yet implemented in pipeline**.
- C-on-LalinCode: **not yet active** (legacy tree path still used).
- Full-completion claim: only valid at “full-support” milestone gates (see doc), not currently achieved.

### Known inconsistencies / overclaims against current code
1. **`asdl_parser` diagnostics**: `C_BACKEND_DESIGN.md` requires file/line/column parse errors, but `lua/lalin/asdl_parser.lua` currently reports byte-position only via `tok_start`.
2. **Execution-planning vs runtime**: design text includes `code_to_c` / `tree_to_code` modules and retired modules, but those files are not yet present and active in the repository; current runtime still flows through `tree_to_c`.
3. **Status wording in design sections** should be read as the target contract, not as already-complete implementation for all layers.

## Edit-planner Output — 2026-06-10 12:44:55

### Precondition Checks
- Confirm `lua/lalin/schema/*.asdl` is the complete schema source set. Current mismatch to verify: `pvm_surface.asdl` exists but is not listed in `SCHEMA_ASDL_MODULES`.
- Confirm no task in the main sidecar is already done before workers start; I amended r5 → r6 with all tasks still `todo`.
- Grep before edits for forbidden imports:
  - `lalin.tree_to_c`
  - `lalin.tree_control_to_c`
  - `lalin.type_to_c`
  - `lalin.c_places`
  - `lalin.c_residence`
  - `lalin.c_cfg`
- Confirm public APIs stay stable: `lalin.emit_c`, `lalin.compile_c`, `BundleValue:emit_c`, `BundleValue:compile_c`.

### Files to Modify

#### `lua/lalin/schema/init.lua`
**Goal**: Make `.asdl` files the only schema source under `lua/lalin/schema/`.

**Edit blocks**
1. **Lines 10-29**: Modify `SCHEMA_ASDL_MODULES`
   - Ensure list exactly matches every `lua/lalin/schema/*.asdl`.
   - Add or deliberately remove/handle `pvm_surface.asdl`.
2. **Lines 32-43**: Modify schema loading loop
   - Pass source name/path to `AsdlText.parse_schema`.
   - Add assertion/helper that no schema Lua builder modules exist except `init.lua`.
3. **Lines 45-52**: Keep C schema exception only for `lua/lalin/c/c_type.lua` and `c_ast.lua`.

**Danger zones**
- Do not reintroduce schema builder modules under `lua/lalin/schema/`.

#### `lua/lalin/asdl_text.lua`
**Goal**: Harden ASDL text loading and source-aware parsing.

**Edit blocks**
1. **Around line 86**: Modify `parse_schema(T, text)`
   - New signature: `parse_schema(T, text, source_name)`.
   - Call `parser.parse(text, source_name)`.
2. **Lines 221-228**: Modify `load_text`
   - Keep preload `<module>_asdl` before filesystem.
   - Preserve enough source metadata for diagnostics/tests.

#### `lua/lalin/asdl_parser.lua`
**Goal**: Replace byte-position-only parse errors with `file:line:column`.

**Edit blocks**
1. **Lines 20-41**: Extend parser state/error helpers.
2. **Lines 35-41**: Modify `expect`
   - Before: `ASDL parse error ... at pos %d`
   - After: `source:line:column: ASDL parse error ...`
3. **Lines 180-188**: Modify public API
   - `parse(input_string, source_name)` with backward-compatible default.

#### `build.rs`
**Goal**: Fail build on stale schema sources and embed ASDL deterministically.

**Edit blocks**
1. **Lines 15-31 / 33-42**: Add schema-source validation while collecting.
2. **Lines 81-103**: After collecting Lua/ASDL modules, assert no `lua/lalin/schema/*.lua` except `init.lua`.
3. **Lines 105-118**: Keep `_asdl` preload generation deterministic.

#### `lua/lalin/schema/code.asdl`
**Goal**: Finalize LalinCode before lowerers depend on it.

**Edit blocks**
1. **Whole file**: Audit/extend CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm, CodePlace, CodeResidence, CodeMemoryAccess, CodeGlobal/Data/Reloc, CodeIssue.
2. Preserve explicit call target variants: direct/extern/indirect/closure.

### New Files

#### `lua/lalin/code_type.lua`
- **Purpose**: Replace `type_to_c.lua` as the backend-neutral type/signature helper.
- **Contents sketch**:
  - `Define(T)`
  - LalinType → LalinCode.CodeType
  - CodeType → CBackend type helper for `code_to_c`
  - signature interning helpers
- **Must not import** old Tree-to-C modules.

#### `lua/lalin/code_validate.lua`
- **Purpose**: Sole LalinCode well-formedness validator.
- **Validate**: ids, def/use, block arity/types, terminators, calls, places, memory access, reloc targets, data/code pointer separation.

#### `lua/lalin/tree_to_code.lua`
- **Purpose**: Resolved/layout LalinTree → normalized LalinCode.
- **Must produce**: flat CodeInst graph, CodeBlock/CodeTerm control, CodePlace/CodeResidence, CodeCallTarget, CodeGlobal/Data init facts.

#### `lua/lalin/code_to_c.lua`
- **Purpose**: LalinCode → LalinC CBackendUnit.
- **Must consume** LalinCode only; no nested LalinTree recursion.

#### `lua/lalin/code_to_back.lua`
- **Purpose**: LalinCode → LalinBack.BackProgram.
- **Note**: Any bridge is allowed only as a single refactor-step implementation detail and must fail final gates if still present.

#### Tests
- `tests/test_code_validate.lua`
- `tests/test_tree_to_code.lua`
- `tests/test_code_to_back.lua`
- `tests/test_code_to_c_smoke.lua`
- `tests/test_code_to_c_semantics_smoke.lua`
- `tests/test_code_to_c_logic_select.lua`

### Files to Replace/Delete

Delete these after call sites/tests are rerouted:
- `lua/lalin/tree_to_c.lua`
- `lua/lalin/tree_control_to_c.lua`
- `lua/lalin/type_to_c.lua`
- `lua/lalin/c_places.lua`
- `lua/lalin/c_residence.lua`
- `lua/lalin/c_cfg.lua`

Rewrite or delete:
- `lua/lalin/c_data.lua` — may survive only as LalinCode data/global helper.
- `lua/lalin/c_layout.lua` — may survive only as LalinCode/CBackend layout helper.

### Public API Reroute

#### `lua/lalin/frontend_pipeline.lua`
- **Lines 55-68**: Replace old requires:
  - remove `tree_to_c`, `type_to_c`, direct `tree_to_back` from public lowering paths.
  - add `tree_to_code`, `code_validate`, `code_to_c`, `code_to_back`.
- **Lines 70-109**: `lower_module`
  - switch native path to `tree_to_code -> code_validate -> code_to_back -> back_validate`.
- **Lines 111-158**: `lower_module_to_c`
  - switch C path to `sem_layout_resolve -> tree_to_code -> code_validate -> code_to_c -> c_validate`.
- **Lines 279-307**: keep `parse_and_lower_c` signature stable.

#### `lua/lalin/init.lua`
- **Lines 49-50**: Remove `M.type_to_c` and `M.tree_to_c`.
- **Lines 129-160**: Keep `emit_c`/`compile_c` public behavior; internals use pipeline.

#### `lua/lalin/host_module_values.lua`
- **Lines 307-338**: `_lower_c_unit` must return LalinCode-produced C unit.
- **Lines 360-390 / 412-418**: `compile_c`/`emit_c` behavior remains stable.

### Tests/Benchmarks/Docs

- Rewrite tests importing old modules:
  - `tests/test_type_to_c.lua`
  - `tests/test_c_backend_negative.lua`
  - `tests/test_c_emit.lua`
  - `tests/test_c_validate.lua`
  - `tests/test_c_helpers.lua`
  - `tests/test_c_gcc_tagged_union.lua`
  - `tests/test_tagged_union_to_c.lua`
- Rename old tree-to-C tests:
  - `test_tree_to_c_smoke.lua` → `test_code_to_c_smoke.lua`
  - `test_tree_to_c_semantics_smoke.lua` → `test_code_to_c_semantics_smoke.lua`
  - `test_tree_to_c_logic_select.lua` → `test_code_to_c_logic_select.lua`
- Update `lua/lalin/c_coverage.lua`
  - Remove steady-state `backend_todo`.
  - Final statuses only: `supported`, `phase_unreachable`, `language_rejected`.
- Update `tests/test_c_backend_coverage_matrix.lua`
  - Reject backend TODO rows unconditionally.
- Update `benchmarks/bench_c_vs_cranelift.lua`
  - Phase labels: `tree_to_code`, `code_validate`, `code_to_c`, `code_to_back`.
- Update `C_BACKEND_DESIGN.md`
  - Remove language allowing long-lived shims.
  - Record deleted/replaced module fates.

### Order of Operations
1. Freeze/harden ASDL schema loading and diagnostics.
2. Finalize `LalinCode` ASDL.
3. Add `code_type`, `code_validate`, `tree_to_code`.
4. Add `code_to_back`, hard-switch native path.
5. Add `code_to_c`, hard-switch C path.
6. Rewrite/delete `c_data` and `c_layout`.
7. Delete old direct Tree-to-C modules.
8. Rewrite tests and coverage matrix.
9. Update benchmark labels and docs.
10. Run final no-legacy grep and full test gates.

### Testing Strategy
Run incrementally:
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `luajit tests/test_code_validate.lua`
- `luajit tests/test_tree_to_code.lua`
- `luajit tests/test_code_to_back.lua`
- `luajit tests/test_code_to_c_smoke.lua`
- `luajit tests/test_c_backend_coverage_matrix.lua`
- `luajit tests/test_c_gcc_feature_corpus.lua`
- public API tests: `test_emit_c_api.lua`, bundle C tests
- final grep gate for forbidden old imports.

### Structured Edit Plan Sidecar
Updated main sidecar for workflow `wf-asdl-c-backend-full-support`:
- Revision: `r6`
- Tasks: `35 todo`, `0 done`
- Added/amended file-by-file tasks `T001`–`T035`
- Removed long-lived shim framing; deletion/replacement tasks are explicit.

## Worker Output — 2026-06-10 14:06:29

## Completed
- Claimed and completed edit-plan tasks `T001`–`T004`.
- Hardened ASDL schema source loading and diagnostics:
  - `schema/*.asdl` checked against loader list plus explicit `pvm_surface.asdl` exclusion.
  - `schema/*.lua` builders forbidden except `init.lua`.
  - ASDL preload loading prefers embedded `<module>_asdl`.
  - Source names and `source:line:column` parser diagnostics are now threaded through.
  - Build script validates schema ASDL preload naming and stale builder files.

## Files Changed
- `lua/lalin/schema/init.lua` - schema source guard, explicit `pvm_surface` exclusion, source-aware parsing.
- `lua/lalin/asdl_text.lua` - preload source metadata and test read-file override.
- `lua/lalin/asdl_parser.lua` - source-name API and line/column diagnostics.
- `lua/lalin/asdl_context.lua` - passes source names to parser.
- `lua/lalin/pvm_surface_model.lua` - source-aware ASDL parsing.
- `build.rs` - deterministic ASDL/Lua collection and schema input validation.
- `tests/test_schema_core.lua` - guard, embedded-preload-only, and diagnostics coverage.

## Tests Run
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `luajit tests/test_pvm_surface_builder.lua`
- `luajit tests/test_pvm_surface_schema_values.lua`
- `rustc --edition=2021 build.rs -o /tmp/lalin-build-rs-check`
- `git diff --check -- ...`

## Notes
- Next ready task is `T005` (`lua/lalin/schema/code.asdl` LalinCode contract).
- Pre-existing unrelated working tree changes remain untouched.

## Worker Output — 2026-06-15 07:59:34

## Completed
- Claimed and completed `T005`: finalized `LalinCode` ASDL contract.
- Claimed and completed `T006`: added backend-neutral CodeType helpers.
- Updated edit-plan sidecar: now `6/35 done`; next ready task is `T007` (`code_validate.lua`).

## Files Changed
- `lua/lalin/schema/code.asdl` - added stable inst/term ids, typed inst/term wrappers, data/reloc facts, memory modes, typed variant refs, imported C func ptr type, expanded validation issues.
- `lua/lalin/code_type.lua` - new LalinType → LalinCode CodeType mapping, CodeSig interning, target helpers, CodeType → CBackend type projection.
- `tests/test_schema_core.lua` - added LalinCode contract fixture assertions.
- `tests/test_code_type.lua` - new focused tests for CodeType helpers.
- `.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json` - task status updates.

## Tests Run
- `luajit tests/test_code_type.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `git diff --check -- lua/lalin/schema/code.asdl lua/lalin/code_type.lua tests/test_schema_core.lua tests/test_code_type.lua`
- grep gate confirming `code_type.lua`/test do not require retired Tree-to-C modules.

## Notes
- Did not start `T007`; it is ready next.

## Worker Output — 2026-06-15 08:14:29

## Completed
- Completed `T007`: implemented `lua/lalin/code_validate.lua`.
- Completed `T025`: added focused LalinCode validator tests.
- Blocked `T008`: full `tree_to_code.lua` normalizer is too broad for this isolated pass and should be decomposed or handled as a dedicated batch.
- Edit plan now has no ready tasks.

## Files Changed
- `lua/lalin/code_validate.lua` - new LalinCode validator with:
  - duplicate/missing id checks
  - value def/use checks
  - block transfer arity/type validation
  - function/call signature validation
  - place/global/local/data typing checks
  - memory access validation
  - data reloc target checks
  - data/code pointer discipline
  - collector integration and `CodeValidationReport`
- `tests/test_code_validate.lua` - new direct LalinCode fixtures covering valid and invalid modules.
- `.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json` - updated task statuses/evidence.

## Tests Run
- `luajit tests/test_code_validate.lua`
- `luajit tests/test_code_type.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `git diff --check -- lua/lalin/code_validate.lua tests/test_code_validate.lua`

## Notes
- `T008` remains the blocker for subsequent `tree_to_code -> code_validate -> code_to_*` pipeline tasks.
- Current edit plan: `8/35 done`, `1 blocked`, `0 ready`.

## Worker Output — 2026-06-15 08:25:13

## Completed
- Claimed and completed `T008A`.
- Added scalar `LalinTree -> LalinCode` scaffold:
  - `Define(T).module(resolved_module, opts)`
  - deterministic lowering ids/context
  - CodeType/CodeSig integration
  - function + single entry-block shell
  - params as `CodeValueId`s
  - scalar literals, refs, unary/binary/compare, machine casts, select
  - `let` aliases and return terminators
- Added validation coverage through:
  `parse -> open_expand/open_validate -> closure_convert -> tree_typecheck -> sem_layout_resolve -> tree_to_code -> code_validate`

## Files Changed
- `lua/lalin/tree_to_code.lua` - new scalar LalinCode lowering scaffold.
- `tests/test_tree_to_code.lua` - new focused scalar lowering integration test.
- `.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json` - marked `T008A` done.

## Tests Run
- `luajit tests/test_tree_to_code.lua`
- `luajit tests/test_code_validate.lua`
- `luajit tests/test_code_type.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `git diff --check -- .pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json lua/lalin/tree_to_code.lua tests/test_tree_to_code.lua`
- exact require-grep confirming `tree_to_code.lua` / test do not require retired C modules.

## Notes
- Did not start `T008B`; it is now ready and covers locals/places/memory/addressability, which is broader than the requested narrow scalar slice.

## Worker Output — 2026-06-15 08:37:09

## Completed
- Claimed and completed `T008B`.
- Extended `lua/lalin/tree_to_code.lua` with:
  - mutable/address-taken local pre-scan
  - `CodeLocal` / `CodeResidence` creation
  - `CodePlaceLocal`, `CodePlaceDeref`, `CodePlaceField`, `CodePlaceIndex`
  - `CodeInstAddrOf`, `CodeInstLoad`, `CodeInstStore`
  - basic `CodeMemoryAccess` alignment/trap facts
- Added coverage for mutable locals, address-of/deref, pointer indexing, struct field places after layout resolution, stores, and loads.
- Marked `T008B` complete in the edit plan.

## Files Changed
- `lua/lalin/tree_to_code.lua` - locals/place/addressability/memory lowering slice.
- `tests/test_tree_to_code.lua` - added place/memory tests and assertions.
- `.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json` - task status update.

## Tests Run
- `luajit tests/test_tree_to_code.lua`
- `luajit tests/test_code_validate.lua`
- `luajit tests/test_code_type.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `git diff --check -- lua/lalin/tree_to_code.lua tests/test_tree_to_code.lua .pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json`
- grep check for forbidden retired C-module requires in touched files.

## Notes
- Next ready task is `T008C` (`tree_to_code` control regions to `CodeBlock`/`CodeTerm`).
- I did not claim `T008C`; it is a broader control-flow pass and not cohesive with this locals/place/memory slice.

## Worker Output — 2026-06-15 08:51:22

## Completed
- Completed `T008C`: normalized LalinTree control lowering to explicit `CodeBlock` / `CodeTerm`.
- Completed `T008D`: added call/signature/extern/global-ref lowering.
- Stopped before `T008E` because it is a broad remaining-coverage slice, not cohesive with this pass.

## Files Changed
- `lua/lalin/tree_to_code.lua`
  - Added multi-block CFG builder.
  - Lowered `if`, `switch`, short-circuit logic, control regions, block params, jumps, yields, returns, traps/assert traps.
  - Added direct/extern/indirect/closure call target lowering.
  - Added function/extern signature precollection and `CodeExtern` emission.
- `tests/test_tree_to_code.lua`
  - Added focused tests for control CFG, switch default, counted loop/block params, expression-region yields, short-circuit logic, direct/extern/indirect calls.
- `tests/test_code_validate.lua`
  - Added missing-signature diagnostic assertion.
- `.pi/workflows/wf-asdl-c-backend-full-support.edit-plan.json`
  - Marked `T008C` and `T008D` complete.

## Tests Run
- `luajit tests/test_tree_to_code.lua`
- `luajit tests/test_code_validate.lua`
- `luajit tests/test_code_type.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `git diff --check ...`
- Forbidden retired-module require grep on touched files.

## Notes
- Next ready task: `T008E` — aggregates/views/data/atomics/variants remaining `tree_to_code` coverage.
- No retired C modules were imported.
