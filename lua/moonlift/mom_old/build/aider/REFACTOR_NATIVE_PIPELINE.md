# MOM Native Pipeline Refactor — Hard Rewrite Plan

## Incentive

The current native compilation pipeline (`compile_source.mlua` + `compile_module.mlua`) uses:
- Pre-allocated workspace buffers with manual pointer arithmetic
- Flat row-major command tape (`CMD_STRIDE = 18`, `mc_push_cmd6`)
- A compatibility bridge (`compile_module.mlua`) that wraps the flat tape
- Bridge functions to copy flat tape → column arrays for validate (`mc_validate_bridge`)
- Bridge functions to read flat tape for wire output (`mom_write_schema_cmd_to_wire`)

This is dead weight. The new backend modules already implement a clean column-major architecture. The native driver must use them directly. No backward compat, no v2 naming, no bridges. Git tracks history.

## Goal

Eliminate ALL flat-tape infrastructure. The `mom` binary compiles user programs through:

```
Source → lex → parse → tree → typecheck → layout
       → lower (column-major MomCmdBuffer, direct mb_lower_module_fn call)
       → validate (column arrays straight to mb_validate, no copy)
       → JIT (Cranelift FFI from column arrays, no intermediate wire)
       → callable artifact
```

Allocation via `ffi.new`. No workspace pointer arithmetic. No compatibility bridges.

## Files to REMOVE (git rm)

### `lua/moonlift/mom/driver/compile_module.mlua`
The flat-tape compatibility bridge. Entire file deleted. Contains `mc_bridge_expr_arrays`, `mc_bridge_stmt_arrays`, `mc_lower_module`, `mcm_push_cmd6`, `mcm_fresh_value` — all garbage.

## Files to REWRITE IN-PLACE (no v2, no backward compat)

### 1. `lua/moonlift/mom/driver/compile_source.mlua`
**Was**: Full native pipeline including lex, parse, tree, typecheck, layout, flat-tape lower, flat-tape validate, wire.
**Now**: Keep phases 1-5 (lex, parse, tree, typecheck, layout). Replace phases 6-8 with new column-major backend.

**KEPT (existing, unchanged logic):**
- Lex phase helpers: `mc_lex_kinds`, `mc_lex_starts`, `mc_lex_stops`, `mc_lex_lines`, `mc_lex_cols`, `mc_lex_phase` — all kept
- Parse phase helpers: `mc_parse_arr`, `mc_init_parse_out`, `mc_parse_out_ptr`, `mc_parse_arrays`, `mc_parse_phase` — all kept
- Tree phase helpers: `mc_tree_arr`, `mc_init_tree_out`, `mc_tree_out_ptr`, `mc_tree_arrays`, `mc_tree_phase` — all kept
- Typecheck phase: `mc_typecheck_base`, `mc_typecheck_arr`, `mc_typecheck_clear`, `mc_typecheck_bind_params`, `mc_tc_*`, `mc_typecheck_phase` — all kept
- Layout phase: `mc_layout_base`, `mc_layout_arr`, `mc_layout_*`, `mc_layout_clear`, `mc_layout_find_item`, `mc_layout_phase` — all kept
- Misc helpers: `mc_normalize_param_refs`, `mc_first_func_item`, `mc_back_scalar_from_type`, `mc_token_text_eq`, `mc_parse_i32_token` — kept
- Exports: `M.mc_lex_*`, `M.mc_parse_*`, `M.mc_tree_*`, `M.mc_typecheck_*`, `M.mc_layout_*` — kept

**REMOVED (flat tape, bridges, wire):**
- All `mc_lower_*` functions: `mc_lower_state`, `mc_lower_base`, `mc_lower_arr`, `mc_lower_expr_a/b/c/d`, `mc_lower_stmt_tok/a/b/c/d/e`, `mc_lower_env_name`, `mc_lower_env_val`, `mc_lower_cmds`, `mc_lower_clear`
- `mc_patch_literal_values` — literal patching was for the bridge's copy arrays
- `mc_cmd_set`, `mc_push_cmd6` — flat tape pusher
- `mc_init_param_env` — old env init for flat tape
- `mc_lower_phase` — the whole old lower phase
- All `mc_validate_*` functions: `mc_validate_base`, `mc_validate_arr`, `mc_validate_issue_count`, `mc_v_tag`, `mc_v_a/b/c/d/e/f`, `mc_v_issue_tag/a/b/c`, `mc_v_map_state`, `mc_v_map_key`, `mc_validate_clear`, `mc_validate_bridge`, `mc_validate_phase`
- `mc_wire_builder`, `mc_wire_phase`
- `mom_driver_compile_source_to_wire`, `mom_driver_compile_source_to_object`, `mom_driver_compile_source_to_artifact`
- All `M.mc_lower_*`, `M.mc_validate_*`, `M.mc_wire_*`, `M.mom_driver_*` exports
- `LowerState` import from M

**ADDED (new column-major phases):**
```moonlift
-- New imports
local MomBackLowerCtx = M.MomBackLowerCtx
local MomCmdBuffer = M.MomCmdBuffer
local MomWireBuilder = M.MomWireBuilder
local mb_lower_module_fn = M.mb_lower_module_fn
local mb_validate = M.mb_validate
local mw_init = M.mw_init
local mw_finish = M.mw_finish
local mom_backend_compile_binary = M.mom_backend_compile_binary
local mom_backend_getpointer = M.mom_backend_getpointer
local mom_backend_free_artifact = M.mom_backend_free_artifact

-- Allocate column-major command buffer
local mc_alloc_cmd_buffer = func(cap: index) -> ptr(@{MomCmdBuffer})
    let buf_ptr: ptr(@{MomCmdBuffer}) = as(ptr(@{MomCmdBuffer}), ffi_new(...))
    -- allocate 18 column arrays
    ...
end

-- Allocate and initialize lowering context
local mc_init_lower_ctx = func(work_buf: ptr(u8)) -> ptr(@{MomBackLowerCtx})
    -- read tree, typecheck, layout pointers from work_buf
    -- allocate ctx and cmd buffer via ffi.new
    -- populate all fields
    ...
end

-- New lowering phase: call mb_lower_module_fn directly
local mc_lower_phase = func(work_buf: ptr(u8), work_cap: index) -> ptr(@{MomBackLowerCtx})
    let ctx: ptr(@{MomBackLowerCtx}) = mc_init_lower_ctx(work_buf)
    let status: i32 = mb_lower_module_fn(ctx)
    if status ~= 0 then return nil end
    return ctx
end

-- New validate phase: pass column arrays directly
local mc_validate_phase = func(ctx: ptr(@{MomBackLowerCtx}), work_buf: ptr(u8)) -> i32
    let buf: ptr(@{MomCmdBuffer}) = ctx.cmd_buffer
    -- allocate issue/map arrays in work_buf
    let issues: i32 = mb_validate(
        buf.tag, buf.w0, buf.w1, buf.w2, buf.w3, buf.w4, buf.w5,
        as(i32, buf.len),
        issue_tag, issue_a, issue_b, issue_c,
        issue_count, VALIDATE_CAP,
        map_state, map_key, VALIDATE_MAP_CAP)
    if issues ~= 0 then return -MC_VALIDATE_ERROR end
    return 0
end

-- New JIT phase: column arrays → MLBT wire → cranelift → artifact
local mc_jit_phase = func(ctx: ptr(@{MomBackLowerCtx}), work_buf: ptr(u8)) -> ptr(u8)
    let buf: ptr(@{MomCmdBuffer}) = ctx.cmd_buffer
    -- write MLBT v3 from column arrays
    let w: ptr(@{MomWireBuilder}) = ...
    mw_init(w, wire_buf, wire_cap)
    mom_write_cmd_columns_to_wire(w, buf.tag, buf.w0, buf.w1, buf.w2, buf.w3, buf.w4, buf.w5, as(i32, buf.len))
    let wire_len: index = mw_finish(w)
    -- JIT compile
    return mom_backend_compile_binary(wire_buf, wire_len)
end

-- Top-level: source → artifact
local mom_driver_compile_to_artifact = func(src: ptr(u8), src_len: index, work_buf: ptr(u8), work_cap: index) -> ptr(u8)
    -- phases 1-5 (existing, unchanged)
    let ntok_i: i32 = mc_lex_phase(src, src_len, work_buf, work_cap)
    if ntok_i < 0 then return nil end
    let nitems: i32 = mc_parse_phase(src, src_len, ntok_i, work_buf, work_cap)
    if nitems < 0 then return nil end
    let tree_items: i32 = mc_tree_phase(work_buf, work_cap)
    if tree_items < 0 then return nil end
    mc_normalize_param_refs(src, work_buf)
    let tc: i32 = mc_typecheck_phase(work_buf, work_cap)
    if tc < 0 then return nil end
    let lo: i32 = mc_layout_phase(work_buf, work_cap)
    if lo < 0 then return nil end
    -- phase 6: lower (new)
    let ctx = mc_lower_phase(work_buf, work_cap)
    if ctx == nil then return nil end
    -- phase 7: validate (new)
    let v: i32 = mc_validate_phase(ctx, work_buf)
    if v < 0 then return nil end
    -- phase 8: JIT (new)
    return mc_jit_phase(ctx, work_buf)
end

M.mom_driver_compile_to_artifact = mom_driver_compile_to_artifact
```

### 2. `lua/moonlift/mom/driver/lower_wire.mlua`
**Remove**: `mom_write_schema_cmd_to_wire` (flat-tape wire writer with `cmds[base + offset]`)
**Remove**: `mom_cmd_tape_set`, `mom_cmd_tape_clear`, `mom_cmd_tape_push`, `mom_lower_cmd_tape_to_wire` — all flat-tape helpers
**Keep**: `mw_mark`, `mw_put_u8`, `mw_write_u32`, `mw_patch_u32`, `mw_align4`, `mw_init`, `mw_finish`, `mw_write_pool_string`, `mw_write_pool_slice`, `mw_write_pool_generated`, `mw_begin_aux`, `mw_write_aux_i32s`, `mom_wire_slot_count`, `mom_schema_scalar_to_wire`, `mom_schema_cmd_tag_to_wire`, `mom_schema_lit_tag_to_wire`, `mom_wire_value_pool`
**Add**: Column-major wire writer:
```moonlift
local mom_write_cmd_columns_to_wire = func(w: ptr(@{MomWireBuilder}),
    tag: ptr(i32), w0: ptr(i32), w1: ptr(i32), w2: ptr(i32),
    w3: ptr(i32), w4: ptr(i32), w5: ptr(i32), n: i32) -> i32
    block cmds_loop(i: i32 = 0)
        if i >= n then return 0 end
        let t: i32 = tag[i]
        let schema_tag: i32 = mom_schema_cmd_tag_to_wire(t)
        if schema_tag < 0 then return -1 end
        mw_write_u32(w, schema_tag)
        let ns: i32 = mom_wire_slot_count(t)
        if ns >= 1 then mw_write_u32(w, w0[i]) end
        if ns >= 2 then mw_write_u32(w, w1[i]) end
        if ns >= 3 then mw_write_u32(w, w2[i]) end
        if ns >= 4 then mw_write_u32(w, w3[i]) end
        if ns >= 5 then mw_write_u32(w, w4[i]) end
        if ns >= 6 then mw_write_u32(w, w5[i]) end
        jump cmds_loop(i = i + 1)
    end
end
M.mom_write_cmd_columns_to_wire = mom_write_cmd_columns_to_wire
```

### 3. `lua/moonlift/mom/driver/native_entry.mlua`
**Remove**: `mom_compile_source_to_wire_internal`, `mom_compile_source_to_object_internal`, `mom_compile_source_to_artifact_internal` — old entry points
**Remove**: exports of old entry points
**Replace with**:
```moonlift
-- New: source → artifact (ptr to opaque artifact)
local mom_compile_to_artifact_internal = func(src: ptr(u8), src_len: index, work_buf: ptr(u8), work_cap: index) -> ptr(u8)
    return mom_driver_compile_to_artifact(src, src_len, work_buf, work_cap)
end

-- New: source → object bytes
local mom_emit_object_internal = func(src: ptr(u8), src_len: index, obj_out: ptr(u8), obj_cap: index, work_buf: ptr(u8), work_cap: index) -> i32
    return mom_driver_emit_object(src, src_len, obj_out, obj_cap, work_buf, work_cap)
end

-- Keep: artifact accessors, Lua open, hello, debug
M.export.mom_compile_to_artifact_internal = mom_compile_to_artifact_internal
M.export.mom_emit_object_internal = mom_emit_object_internal
-- (keep existing exports for artifact_getpointer, artifact_free, luaopen, hello, debug)
```

### 4. `lua/moonlift/mom/driver/lua_api.mlua`
Implement from stubs:
```moonlift
local mom_lua_native_loadstring = func(src: ptr(u8), src_len: index, module_name: ptr(u8), module_name_len: index, lua_state: ptr(u8)) -> i32
    -- allocate work buffer, call mom_driver_compile_to_artifact
    -- push artifact as Lua userdata
    return 0  -- success
end

local mom_lua_emit_object = func(...) -> index
    -- similar: allocate, compile, return bytes
end

local mom_luaopen_moonlift_impl = func(lua_state: ptr(u8)) -> i32
    -- register moon.native_loadstring, moon.emit_object in Lua state
end
```

### 5. `lua/moonlift/mom/build/manifest.lua`
- Remove: `"lua/moonlift/mom/driver/compile_module.mlua"`
- (compile_source.mlua stays — it's rewritten in-place)

### 6. `src/embedded_lua.rs` and `src/embedded_hosted_lua.rs`
- Remove: `compile_module.mlua` include line
- (compile_source.mlua stays)

### 7. `src/mom_main.rs`
Replace FFI extern declarations:
```rust
// OLD
fn mom_compile_source_to_wire_internal(src: *mut u8, src_len: usize, wire_out: *mut u8, wire_cap: usize, work_buf: *mut u8, work_cap: usize) -> i32;
fn mom_compile_source_to_object_internal(src: *mut u8, src_len: usize, obj_out: *mut u8, obj_cap: usize, work_buf: *mut u8, work_cap: usize) -> i32;
fn mom_compile_source_to_artifact_internal(src: *mut u8, src_len: usize, diags: *mut u8, diag_cap: usize, work_buf: *mut u8, work_cap: usize) -> i32;

// NEW
fn mom_compile_to_artifact_internal(src: *mut u8, src_len: usize, work_buf: *mut u8, work_cap: usize) -> *mut c_void;
fn mom_emit_object_internal(src: *mut u8, src_len: usize, obj_out: *mut u8, obj_cap: usize, work_buf: *mut u8, work_cap: usize) -> i32;
fn mom_artifact_getpointer(artifact: *const c_void, name: *const c_char) -> *const c_void;
fn mom_artifact_free(artifact: *mut c_void);
```

Rewrite `main()` to:
1. Allocate work buffer (~1-2 MB)
2. Read source file
3. `let artifact = mom_compile_to_artifact_internal(src, len, work_buf, work_cap)`
4. `let ptr = mom_artifact_getpointer(artifact, c"main")`
5. Cast and call
6. `mom_artifact_free(artifact)`

## Files with NO changes
- All parser modules (`document_scan.mlua`, `native_lexer.mlua`, `native_core.mlua`, `native_tree.mlua`)
- All typecheck modules (`type_check.mlua`, `type_control.mlua`)  
- All layout modules (`layout_env.mlua`, `layout_field.mlua`, `layout_resolve.mlua`)
- All backend modules (`ids.mlua`, `ops.mlua`, `env.mlua`, `lower_ctx.mlua`, `cmd.mlua`, `control.mlua`, `validate.mlua`, `back_abi.mlua`, `expr_lower.mlua`, `address.mlua`, `stmt_lower.mlua`, `control_lower.mlua`, `func.mlua`, `module.mlua`)
- All vector modules (`vec_facts.mlua`, `vec_decide.mlua`, `vec_plan.mlua`, `vec_lower.mlua`)
- Runtime modules (`builders.mlua`, `sets.mlua`)
- Schema modules
- `driver/wire.mlua`, `driver/backend_ffi.mlua`
- `assemble.lua`, `mlua_run.lua` (assembler path, unchanged)
- All Rust backend files (`ffi.rs`, `lib.rs`)
- `mom_cli.lua`, `host_mom.lua` (hosted path, unchanged)

## Implementation Order

1. Rewrite `compile_source.mlua` — strip old lower/validate/wire, add new column-major phases
2. Rewrite `native_entry.mlua` — new C exports
3. Update `lower_wire.mlua` — add column-major writer, remove flat-tape functions
4. Remove `compile_module.mlua` from disk
5. Update `manifest.lua` — remove compile_module entry
6. Update `embedded_lua.rs` and `embedded_hosted_lua.rs` — remove compile_module include
7. Update `mom_main.rs` — new FFI signatures + main()
8. Implement `lua_api.mlua` — from stubs to real
9. Build: `luajit scripts/emit_mom_precompiled.lua && cargo build --release --bin mom`
10. Fix any compile errors
11. Run tests: `test_mom_run_2plus2.lua`, `test_mom_control_lower.lua`, etc.
12. Clean up dead imports/exports

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| `ffi.new` not available | BLOCKER | Use `moon.alloc` or `ffi.C.malloc`; test early in step 1 |
| `MomBackLowerCtx` ffi.new fails | MEDIUM | Allocate as byte buffer + cast; zero-init then set fields |
| Column-major wire writer format mismatch | MEDIUM | Cross-check slot counts against `mom_wire_slot_count` |
| `var` declarations trigger CmdCreateStackSlot nil | LOW | Already fixed in tree_to_back.lua (nil guard added) |
| Tests using `mom run` break | EXPECTED | Update tests after pipeline works; they test the new path |
| Object emission not yet implemented | LOW | Stub returns NOT_IMPLEMENTED; wire path works, object is future work |

---

## Progress Checklist

**Instructions**: check `[x]` when a step is DONE. Add notes under each step.
If a step uncovers new work, add it as a sub-item or a new step at the end.
Keep this list current — it is the single source of truth for refactor progress.

### Step 1: Rewrite `compile_source.mlua`
- [ ] Strip all `mc_lower_*` functions (lines ~740–938)
- [ ] Strip all `mc_validate_*` functions (lines ~940–1060)
- [ ] Strip `mc_wire_phase`, `mc_wire_builder`
- [ ] Strip `mom_driver_compile_source_to_wire`, `mom_driver_compile_source_to_object`, `mom_driver_compile_source_to_artifact`
- [ ] Strip `mc_push_cmd6`, `mc_cmd_set`, `mc_patch_literal_values`, `mc_lower_clear`, `mc_init_param_env`
- [ ] Strip `LowerState` import from M
- [ ] Strip old `M.mc_lower_*`, `M.mc_validate_*`, `M.mc_wire_*`, `M.mom_driver_*` exports
- [ ] Keep all `mc_lex_*`, `mc_parse_*`, `mc_tree_*`, `mc_typecheck_*`, `mc_layout_*` (phases 1–5)
- [ ] Add new imports: `MomBackLowerCtx`, `MomCmdBuffer`, `MomWireBuilder`, `mb_lower_module_fn`, `mb_validate`, `mw_init`, `mw_finish`, `mom_backend_compile_binary`
- [ ] Implement `mc_alloc_cmd_buffer(cap)` — allocate 18 column arrays via ffi.new
- [ ] Implement `mc_init_lower_ctx(work_buf)` — allocate + populate `MomBackLowerCtx`
- [ ] Implement `mc_lower_phase(work_buf, work_cap)` — call `mb_lower_module_fn(ctx)`
- [ ] Implement `mc_validate_phase(ctx, work_buf)` — pass column arrays to `mb_validate`
- [ ] Implement `mc_jit_phase(ctx, work_buf)` — column arrays → wire → cranelift
- [ ] Implement `mom_driver_compile_to_artifact(src, src_len, work_buf, work_cap)` — full pipeline
- [ ] Export `M.mom_driver_compile_to_artifact`
- [ ] *Notes:*

### Step 2: Rewrite `native_entry.mlua`
- [ ] Remove `mom_compile_source_to_wire_internal`
- [ ] Remove `mom_compile_source_to_object_internal`
- [ ] Remove `mom_compile_source_to_artifact_internal`
- [ ] Remove old `M.export.*` for removed functions
- [ ] Add `mom_compile_to_artifact_internal(src, src_len, work_buf, work_cap) -> ptr(u8)`
- [ ] Add `mom_emit_object_internal(src, src_len, obj_out, obj_cap, work_buf, work_cap) -> i32`
- [ ] Export both via `M.export.*`
- [ ] Keep: `mom_artifact_getpointer`, `mom_artifact_free`, `mom_luaopen_moonlift`, `mom_debug_index_arithmetic`, `mom_hello`
- [ ] *Notes:*

### Step 3: Update `lower_wire.mlua`
- [ ] Remove `mom_write_schema_cmd_to_wire` (flat tape writer)
- [ ] Remove `mom_cmd_tape_set`, `mom_cmd_tape_clear`, `mom_cmd_tape_push`
- [ ] Remove `mom_lower_cmd_tape_to_wire`
- [ ] Remove `M.mom_*` exports for removed functions
- [ ] Add `mom_write_cmd_columns_to_wire(w, tag, w0, w1, w2, w3, w4, w5, n) -> i32`
- [ ] Export `M.mom_write_cmd_columns_to_wire`
- [ ] *Notes:*

### Step 4: Delete `compile_module.mlua`
- [ ] `git rm lua/moonlift/mom/driver/compile_module.mlua`
- [ ] *Notes:*

### Step 5: Update `manifest.lua`
- [ ] Remove `"lua/moonlift/mom/driver/compile_module.mlua"` line
- [ ] Verify manifest still has `compile_source.mlua` (rewritten in-place)
- [ ] *Notes:*

### Step 6: Update embedded sources
- [ ] `src/embedded_lua.rs` — remove `compile_module.mlua` include
- [ ] `src/embedded_hosted_lua.rs` — remove `compile_module.mlua` include
- [ ] *Notes:*

### Step 7: Update `mom_main.rs`
- [ ] Remove `mom_compile_source_to_wire_internal` FFI declaration
- [ ] Remove `mom_compile_source_to_object_internal` FFI declaration
- [ ] Remove `mom_compile_source_to_artifact_internal` FFI declaration
- [ ] Add `mom_compile_to_artifact_internal(src, src_len, work_buf, work_cap) -> *mut c_void`
- [ ] Add `mom_emit_object_internal(src, src_len, obj_out, obj_cap, work_buf, work_cap) -> i32`
- [ ] Rewrite `main()` to use new artifact-based API
- [ ] *Notes:*

### Step 8: Implement `lua_api.mlua`
- [ ] Implement `mom_lua_native_loadstring` — compile source → Lua userdata artifact
- [ ] Implement `mom_lua_emit_object` — compile source → object bytes
- [ ] Implement `mom_luaopen_moonlift_impl` — register `moon` module in Lua state
- [ ] *Notes:*

### Step 9: Build precompiled module
- [ ] `luajit scripts/emit_mom_precompiled.lua` — must succeed
- [ ] *Notes:*

### Step 10: Build mom binary
- [ ] `cargo build --release --bin mom` — must succeed
- [ ] *Notes:*

### Step 11: Run tests
- [ ] `luajit tests/test_mom_run_2plus2.lua` — basic arithmetic
- [ ] `luajit tests/test_mom_control_lower.lua` — control regions (blocks, loops)
- [ ] `luajit tests/test_mom_groundwork.lua` — foundations
- [ ] `luajit tests/test_mom_native_lexer.mlua` — lexer
- [ ] `luajit tests/test_mom_native_core.lua` — parser core
- [ ] `luajit tests/test_mom_check_correctness.mlua` — typecheck
- [ ] `luajit tests/test_mom_vec.lua` — vectorization
- [ ] `luajit tests/test_mom_wire.lua` — wire format
- [ ] `luajit tests/test_mom_source_to_binary.lua` — full pipeline
- [ ] `luajit tests/test_mom_cli.lua` — CLI
- [ ] *Notes:*

### Step 12: Cleanup
- [ ] Remove dead imports from all touched files
- [ ] Remove dead exports from all touched files
- [ ] Verify no remaining references to `compile_module` or `mc_bridge_`
- [ ] Verify no remaining `mc_push_cmd6` or `CMD_STRIDE` or flat-tape constants
- [ ] *Notes:*

### Discovered Issues (append as found)
- [ ] *None yet*
