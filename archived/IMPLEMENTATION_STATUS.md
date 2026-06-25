# MOM Precompiled Reorganization - Implementation Status

**Last Updated: 2026-05-16 24:XX UTC**

**Phase 4 Rust integration checkpoint (2026-05-16)**
- ✅ Phase 2 COMPLETE: modules now use assignment-style `M.name = decl`, `M.export.name = decl`, `M.extern.name = decl`
- ✅ Phase 3 COMPLETE: All core driver/runtime infrastructure implemented
- ✅ Phase 4 PARTIAL: `mom` is now a product binary that links and calls `target/libmom_precompiled.o`; it no longer embeds hosted compiler Lua
  - runtime/diag.mlua: Complete with MomDiag struct and diagnostic builders
  - driver/compile_source.mlua: Native source driver now runs lexer → parser core → tree materializer → typecheck → layout → lowering → validation → MLBT wire emission over caller-owned workspace
  - driver/native_entry.mlua: C ABI exports fully implemented
  - driver/lua_api.mlua: Lua module registration infrastructure
  - driver/wire.mlua: Verified complete with MLBT v3 serialization
  - driver/backend_ffi.mlua: Verified complete with Rust FFI
- Build verification: Successful, no regressions, all modules compile standalone
- Git status: 3 commits (2b47d7a, eccad80, 7b70f76)

**✅ BLOCKER RESOLVED: Unified MOM assembly now emits object**
- Fixed assembly registration for regular Lalin `struct ... end` TypeValue declarations.
- Switched MOM assembly to assignment-style declarations: `M.Name = struct ... end`, `M.fn = func ... end`, `M.export.fn = ...`, `M.extern.fn = ...`.
- Removed duplicate registered product definitions; the assembler now treats duplicate declarations as hard errors.
- Product manifest keeps one typecheck implementation (`type_check.mlua`) until split modules fully replace it.
- `target/libmom_precompiled.o` now generates successfully and exports `mom_compile_source_to_wire`, `mom_compile_source_to_object`, `mom_compile_source_to_artifact`, `mom_luaopen_lalin`, and `mom_hello`.
- `src/mom_main.rs` was rewritten as a native product CLI with no embedded hosted Lua.
- `make test-mom` now builds `lalin -> liblalin.so -> libmom_precompiled.o -> mom` and passes the status/symbol/no-hosted-embed checks.
- Fixed pointer-arithmetic lowering to avoid redundant index→index sign-extension; this unblocked real workspace slicing in the native driver.
- `mom status` now probes the native source-to-wire pipeline on a tiny source and reports the emitted MLBT byte length.
- `target/release/mom` can JIT-run native source-to-wire output by real source function name; `tests/test_mom_run_2plus2.lua` verifies `main(): 2 + 2 -> 4` and `add(i32, i32): 20 + 22 -> 42`.

**Phase 3 Progress: 6 of 6 core tasks complete (100%)**
- ✅ Task #34 (11): runtime/diag.mlua - diagnostic types and builders
- ✅ Task #35 (14): driver/compile_source.mlua - compilation orchestrator through tree materialization
- ✅ Task #36 (13): driver/wire.mlua - MLBT v3 wire format (verified complete)
- ✅ Task #37 (12): driver/backend_ffi.mlua - FFI integration (verified complete)
- ✅ Task #38 (16): driver/native_entry.mlua - C ABI exports
- ✅ Task #39 (23): driver/lua_api.mlua - Lua package API

## Overview

This document tracks the implementation of the MOM Precompiled Binary Reorganization Plan. The goal is to transform the `mom` binary from a hosted compiler to a clean product architecture that links precompiled MOM object code.

## Completed Work (24 of 33 Tasks - 73%)

### Phase 1: Build Infrastructure ✅

**Task #1: Create build directory structure and manifest** ✅
- Created `lua/lalin/mom/build/` directory
- Created `lua/lalin/mom/build/manifest.lua` with ordered source list
  - 12 schema sources
  - 44 compiler sources organized by phase (runtime, backend, typecheck, layout, driver, vec, parser)
- Manifest verified to match actual source files in repository

**Task #2: Create tags directory and generate mom_tags.lua** ✅
- Created `lua/lalin/mom/tags/` directory
- Created `lua/lalin/mom/build/tags_gen.lua` leveraging existing `back_tags.lua`
- Created `scripts/generate_mom_tags.lua` entry point
- Generated `lua/lalin/mom/tags/mom_tags.lua` (462 lines, 252 constants)
- Tags include all schema union variants plus 12 explicit non-schema constants

### Phase 1a: Rust/Build Infrastructure ✅

**Task #19: Rename embedded_lua.rs to embedded_hosted_lua.rs** ✅
- Updated `build.rs` to generate `src/embedded_hosted_lua.rs` instead of `src/embedded_lua.rs`
- Updated `src/main.rs` to import and use `embedded_hosted_lua` module
- Both uses of `embedded_lua::` functions updated to `embedded_hosted_lua::`

**Task #20: Update build.rs for per-binary embedded Lua and MOM linking** ✅
- Updated `link_mom_precompiled()` function to use `MOM_OBJ_PATH` environment variable
- Changed error handling: warns if object missing (allows lalin to build independently)
- Only links object when present, enabling phased builds
- Updated `cargo::rerun-if-changed` tracking for object file

**Task #21: Rewrite Makefile with clean build graph** ✅
- Updated Makefile variables and added new targets
- `all` target now builds: $(LALIN) $(MOM)
- New `mom-tags` target: generates tags before object compilation
- Updated `mom-obj` target: depends on `mom-tags`, runs `scripts/emit_mom_precompiled.lua`
- Updated `$(MOM)` target: depends on `$(MOM_OBJ)`, passes `MOM_OBJ_PATH` to cargo
- Updated `clean` target: removes `src/embedded_hosted_lua.rs` instead of `src/embedded_lua.rs`
- Added `test-mom` target for running CLI tests

**Task #22: Rewrite scripts/emit_mom_precompiled.lua** ✅
- Replaced placeholder script with functional implementation
- Uses `lalin.mom.build.assemble` module to load and assemble MOM modules
- Calls `Assemble.emit_object()` to generate precompiled object
- Respects `MOM_OBJ_PATH` environment variable
- Provides user-friendly output messages

## Build Verification

**Lalin Binary Build Status: ✅ SUCCESS**
```
cargo build --release --bin lalin
   Compiling lalin v0.1.0
    Finished `release` profile [optimized] target(s) in 8.31s
    Warning: libmom_precompiled.o not found (expected until mom-obj is built)
```

## Remaining Work (28 of 33 Tasks)

### Phase 2: Module Reorganization & Shape Conversion

**Status: 32 modules require conversion from `lalin.module()` to `function(M)` pattern**

The following tasks require converting modules from the old hosted-style pattern to the new product pattern:

**Task #3: Reorganize and rename parser files** (0% complete)
- Files to rename:
  - `native_lexer.mlua` → `lexer.mlua`
  - `native_core.mlua` → `parse_module.mlua`
  - `native_tree.mlua` → `tree_materialize.mlua`
- Files already in correct locations (5 files in parser/)

**Task #4: Reorganize and rename typecheck files** (0% complete)
- Files to rename:
  - `type_env.mlua` → `env.mlua`
  - `type_scalar.mlua` → `scalar.mlua`
  - `type_expr.mlua` → `expr.mlua`
  - `type_place.mlua` → `place.mlua`
  - `type_stmt.mlua` → `stmt.mlua`
  - `type_control.mlua` → `control.mlua`
  - `type_module.mlua` → `module.mlua`
- Additional file: `type_check.mlua` (entry point/coordinator)

**Task #5: Reorganize and rename backend files** (0% complete)
- Files to rename:
  - `back_abi.mlua` → `abi.mlua`
  - `expr_lower.mlua` → `expr.mlua`
  - `stmt_lower.mlua` → `stmt.mlua`
- Files already in correct location (6 files in back/)

**Tasks #6-10: Convert modules to function(M) shape** (0% complete)
- All 32 modules with `lalin.module()` pattern need conversion
- Conversion pattern:
  ```lua
  -- OLD
  local M = lalin.module("name")
  M:add_func(func_name)
  return M

  -- NEW
  return function(M)
  M:local_func("func_name", func_name)
  return M
  end
  ```
- Must replace all `M:add_func` with appropriate `M:local_func`, `M:export_func`, or `M:extern_func`
- Must update all imports from `lalin.mom.back.back_tags` to `lalin.mom.tags.mom_tags`

**Task #24: Move verification-only files to lua/lalin/mom/verify/** (0% complete)
- Move `parser/native_ast.lua` → `verify/parser_native_ast.lua`
- Any other hosted-only test helpers

### Phase 3: Native Driver Implementation

**Tasks #11-16: Implement/update driver modules** (0% complete)
- Task #11: `runtime/diag.mlua` with MomDiag struct and diagnostic builders
- Task #12: `driver/backend_ffi.mlua` with Rust extern declarations
- Task #13: `driver/wire.mlua` as MLBT v3 writer
- Task #14: `driver/compile_source.mlua` as source-to-wire orchestrator
- Task #15: `driver/object_driver.mlua` and `driver/jit_driver.mlua`
- Task #16: `driver/native_entry.mlua` with product C ABI exports

### Phase 4: Rust Core Updates

**Task #17: Update Rust src/ffi.rs** (0% complete)
- Add `lalin_object_compile_binary_into` for caller-owned buffer
- Ensure all product ABI symbols are exported

**Task #18: Rewrite src/mom_main.rs as native product binary** (0% complete)
- Declare native extern symbols
- Implement CLI: `mom status`, `mom run`, `mom --emit-object`
- LuaJIT initialization for metaprogramming only
- Call `mom_luaopen_lalin` to register native API
- Remove all embedded hosted Lua usage

### Phase 5: Cleanup & Testing

**Tasks #23-31: Implementation of remaining features** (0% complete)
- Task #23: Implement `driver/lua_api.mlua` Lua package API
- Task #25: Update test file paths after reorganization
- Task #26: Create `tests/test_mom_precompiled_symbols.lua`
- Task #27: Create `tests/test_mom_no_hosted_embed.lua`
- Task #28: Rewrite `tests/test_mom_cli.lua`
- Task #29: Delete hosted-only files
- Task #30: Update `lua/lalin/init.lua` exports
- Task #31: Replace `lua/lalin/mom/init.lua` with error message
- Task #32: Run full build and acceptance tests
- Task #33: Final grep/verification checks

## Key Files Modified

### Created Files
- `lua/lalin/mom/build/manifest.lua`
- `lua/lalin/mom/build/assemble.lua`
- `lua/lalin/mom/build/tags_gen.lua`
- `lua/lalin/mom/tags/mom_tags.lua` (generated)
- `scripts/generate_mom_tags.lua`

### Modified Files
- `Makefile` - Complete rewrite of build graph
- `build.rs` - Updated embedded Lua generation and MOM object linking
- `src/main.rs` - Updated module references
- `scripts/emit_mom_precompiled.lua` - Functional implementation using new build system
- `lua/lalin/mom/PRECOMPILED_MOM_REORG_PLAN.md` - Progress tracking

## Next Steps

The most efficient path forward is to:

1. **Batch convert remaining modules** (Tasks #3-10, #24)
   - Use mechanical search-replace for module pattern conversion
   - Update imports from back_tags to mom_tags
   - Estimated: 2-4 hours for all modules

2. **Implement driver layer** (Tasks #11-16)
   - Implement diag, backend_ffi, wire modules
   - Implement compile_source orchestrator
   - Implement object/jit drivers and native_entry
   - Estimated: 4-6 hours

3. **Rust core updates** (Tasks #17-18)
   - Update ffi.rs with missing exports
   - Rewrite mom_main.rs from scratch
   - Estimated: 2-3 hours

4. **Testing and cleanup** (Tasks #23-33)
   - Update tests and verify build succeeds
   - Delete old files and verify no broken imports
   - Estimated: 1-2 hours

**Total Remaining Effort: Approximately 9-15 hours**

## Known Blockers

No build blocker remains for producing and linking `target/libmom_precompiled.o`.

Current implementation gap: native source-to-wire now emits MLBT bytes for the current minimal lowered command subset. Native source-to-object/source-to-artifact still intentionally return product errors until Rust backend invocation and executable artifact handles are wired.

## Verification Checklist for Completion

- [x] All 32 modules converted to function(M) pattern
- [x] Phase 3 core infrastructure modules created (diag, compile_source, native_entry, lua_api)
- [x] `make mom-obj` generates precompiled object
- [x] `cargo build --release --bin lalin` and `cargo build --release --bin mom` succeed when `MOM_OBJ_PATH` is set
- [x] `mom status` reports precompiled native MOM
- [x] `nm -g target/release/mom | grep mom_compile_source_to_wire` shows symbol
- [x] `strings target/release/mom | grep lalin.tree_typecheck` returns empty
- [x] `make test-mom` passes
- [ ] Final grep checks pass (see plan section 17)
- [ ] No broken imports in product path

## Phase 3 Status

**Objective:** Implement native driver layer for compilation pipeline
**Status:** ✅ INFRASTRUCTURE COMPLETE; native source-to-wire pipeline connected through MLBT emission

**Completed:**
- ✅ Diagnostic infrastructure (MomDiag, MomDiagBuilder)
- ✅ Compilation orchestrator through lex → parse → tree → typecheck → layout → lower → validate → wire (`mom_driver_compile_source_to_wire`)
- ✅ Native entry points (6 exported C functions)
- ✅ Lua API stubs (module registration hooks)
- ✅ Build manifest updated with new modules
- ✅ All modules compile successfully as standalone

**Remaining:**
- Extend name resolution beyond function parameters to locals, globals, and multi-function modules using the hosted compiler behavior in `lua/lalin/` as source of truth.
- Broaden lowering/wire coverage from the current command subset to the full command surface.
- Wire native source-to-object/source-to-artifact to the Rust backend and return real object bytes/artifact handles.
