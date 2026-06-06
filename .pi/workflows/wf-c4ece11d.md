# SpongeJIT LuaRT Objects Segfault Fix 
Investigate and fix the pre-existing segfault in test_spongejit_lua_compile_lua_rt_objects.lua after the SpongeJIT clean-base purge.
**Workflow ID**: wf-c4ece11d
**Started**: 2026-06-06 09:46:00
---

## Scout Output — 2026-06-06 09:53:25

## Files Retrieved

1. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua` (lines 19-23, 33-44, 46-58, 69-97)  
   - The failing fixture. Its `LuaRTTable` FFI cdef is missing `hash`, `hash_capacity`, and `hash_count`.
   - First crash occurs at line 70, inside native `get_hit(...)`.

2. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_object_model.lua` (lines 1-108)  
   - Canonical executable LuaRT string/table/hash layout.
   - Current emitted `LuaRTTable` includes:
     `array, array_len, hash, hash_capacity, hash_count, metatable_kind, ...`

3. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_value_model.lua` (lines 15-49, 78-83, 112-130)  
   - Canonical `LuaRTValue` layout and tag order.
   - `TableTag == 10`, `IntegerTag == 6`, `ShortStringTag == 8`, `AbsentKeyTag == 2`.

4. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` (lines 465-490, 710-738)  
   - `GETTABLE` lowers to `TableRawGetExpr` + `TableRawGetValueOrNilExpr`.
   - `LEN` lowers to `LenNoMetaExpr`.
   - `CONCAT` lowers to `StringConcat2Expr`.
   - `SETTABLE` lowers to `TableRawSetCanWriteExpr`, `TableRawSet`, and `TableWriteBarrier`.

5. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` (lines 412-438, 461-475, 548-567)  
   - LuaExec object expressions lower into MoonCFG runtime ops:
     `RuntimeTableRawGet`, `RuntimeTableRawSetCanWrite`, `RuntimeLenNoMeta`, `RuntimeStringConcat2`, `RuntimeTableRawSet`.

6. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` (lines 312-380, 509-525, 602-630)  
   - Emits raw hash access directly into Moonlift source.
   - `render_raw_get` builds nested `select(...)` expressions containing `tbl.hash[i]` loads.
   - `RuntimeRawGetValueOrNil` is emitted as `select(rawget.hit, rawget.value, nil)`.

7. `lua/moonlift/tree_to_back.lua` (lines 814-824, 1048-1072, 1377-1409)  
   - `ExprSelect` lowers both then/else expressions before emitting `CmdSelect`; not short-circuiting.
   - Field/index loads are lowered as actual loads before select.

8. `src/decode.rs` (lines 493-557)  
   - Backend turns `CmdLoadInfo` into Cranelift `load`.
   - Backend turns `CmdSelect` into Cranelift `select` over already-computed operands.

9. `lua/moonlift/mlua_run.lua` (lines 16-62, 77-128)  
   - Native call path:
     `moon.loadstring` → parse/lower → JIT compile → `ffi.cast(csig, ptr)` → `CompiledFunction:__call`.

10. `lua/moonlift/back_jit.lua` (lines 100-184)  
    - LuaJIT FFI bridge to Rust JIT artifact and native function pointer retrieval.

11. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` (lines 496-795, 1180-1536)  
    - ASDL definitions for LuaRT values/table states, LuaExec table expressions/ops, and MoonCFG runtime table/string ops.

12. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` (lines 160-224, 242-274)  
    - Validator checks runtime-like value shape but does not validate FFI fixture layout or non-null hash pointer requirements.

13. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_cdata_model.lua` (lines 1-58)  
    - FFI/cdata substrate uses explicit typed pointer fields and metadata, analogous direct-layout model.

14. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arithmetic.lua` (lines 17-45, 50-140)  
    - Similar fixture pattern for `LuaRTValue`/`LuaRTString`; this test passes.

15. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_stack.lua` (lines 18-50, 99-170)  
    - Similar native call pattern for stack/value fixtures; this test passes.

16. Generated `/tmp/test_rt_gettable_raw_hit.mlua` (lines 1-23)  
    - Emitted Moonlift source for first failing native function.
    - Shows emitted `LuaRTTable` layout includes `hash` fields, and function body contains direct `frame0_tables[...].hash[...]` loads.

## Key Code

### Test fixture has stale `LuaRTTable` cdef

```lua
ffi.cdef[[
typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
typedef struct { int64_t byte_len; int64_t hash; int64_t numeric_kind; int64_t numeric_i64; double numeric_f64; } LuaRTString;
typedef struct { LuaRTValue *array; int64_t array_len; int64_t metatable_kind; int64_t index_table; int64_t newindex_table; int64_t gc_color; int64_t gc_generation; int64_t gc_epoch; int64_t barrier_epoch; int64_t barrier_count; int64_t barrier_last_child_tag; int64_t barrier_last_child_payload; } LuaRTTable;
]]
```

Current object model emits:

```lua
"struct LuaRTTable array: ptr(LuaRTValue); array_len: i64; hash: ptr(LuaRTTableHashEntry); hash_capacity: i64; hash_count: i64; metatable_kind: i64; ..."
```

### First crashing call

```lua
local get_hit = compile_outcome(
  { {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} },
  "value0_payload_i64",
  "test_rt_gettable_raw_hit"
)
assert(tonumber(get_hit(tables, strings, table0, key1)) == 77)
```

Observed:

```text
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua
Segmentation fault (core dumped)
EXIT:139
```

Instrumented reproduction:

```text
compile test_rt_gettable_raw_hit
src length 24333
compile native
about to call get_hit
Segmentation fault (core dumped)
EXIT:139
```

### GDB evidence

Crash is in native JIT code called through LuaJIT FFI:

```text
Program received signal SIGSEGV, Segmentation fault.
0x00007ffff7fb7082 in ?? ()
#0  0x00007ffff7fb7082 in ?? ()
#1  0x00007ffff7d0d200 in __libc_malloc2 () from /lib64/libc.so.6
#2  0x00005555555cb17b in lj_vm_ffi_call ()
...
```

Disassembly around crash:

```asm
mov    0x18(%r8,%rax,1),%r13
mov    0x10(%r8,%rax,1),%rcx
=> mov    0x188(%rcx),%r14
```

Interpretation from data layout:
- Native expects `LuaRTTable.hash` at offset `0x10`.
- Test fixture old layout has `metatable_kind` at offset `0x10`, initialized to `0`.
- Native loads `rcx = 0`, then dereferences `hash[7]` at `0x188(%rcx)`, crashing.

### Measured FFI layout offsets

Old test layout:

```text
Old sizeof 96
Old array 0
Old array_len 8
Old metatable_kind 16
Old index_table 24
...
```

Current model-compatible layout:

```text
New sizeof 120
HashEntry sizeof 56
New array 0
New array_len 8
New hash 16
New hash_capacity 24
New hash_count 32
New metatable_kind 40
...
```

### Additional isolation

Temporary script with corrected `LuaRTTable` cdef but `hash = nil`, `hash_capacity = 0` still segfaulted on first array hit.

Temporary script with corrected cdef and allocated `LuaRTTableHashEntry[8]`, even with `hash_capacity = 0`, returned `77`.

Temporary full patched-copy fixture with corrected cdef + allocated hash bank:

```text
ok - SpongeJIT LuaRT object/table/string substrate
EXIT:0
```

This shows two first-order facts:
1. The existing test cdef layout is stale.
2. The emitted raw-get expression can touch `hash[...]` even when the logical path is an array hit / hash capacity zero, because `select` operands are eagerly lowered.

## Relationships

Pipeline for failing call:

```text
test events GETTABLE/RETURN1
→ lua_compile_unit.from_events
→ lua_src_window_collect / lua_src_from_puc_decode
→ LuaSrc.GETTABLE
→ lua_src_to_lua_exec_lower
    Exec.TableRawGetExpr
    Exec.TableRawGetValueOrNilExpr
→ lua_exec_to_moon_cfg_lower
    CFG.RuntimeTableRawGet
    CFG.RuntimeRawGetValueOrNil
→ moon_cfg_emit
    Moonlift source with LuaRTTable/hash declarations and nested select/hash probes
→ moon.loadstring
→ mlua_run.compile
→ frontend_pipeline.parse_and_lower
→ back_jit JIT compile
→ ffi.cast(csig, ptr)
→ LuaJIT FFI native call
→ segfault in JIT code
```

Data layout chain:

```text
ObjectModel.TYPE_DECL says:
  LuaRTTable.hash at offset 16
  LuaRTTable.hash_capacity at offset 24
  LuaRTTable.hash_count at offset 32
  metatable_kind at offset 40

Test fixture says:
  metatable_kind at offset 16
  index_table at offset 24
  newindex_table at offset 32
```

Select/lifetime chain:

```text
moon_cfg_emit emits select(cond, unsafe_hash_load, fallback)
→ tree_to_back lowers cond, then_expr, else_expr before CmdSelect
→ src/decode.rs emits Cranelift load before select
→ guard condition does not prevent invalid pointer load
```

## Observations

- The segfault is reproducible in current repo state, exit code `139`.
- Crash occurs at the very first native object test call: `test_rt_gettable_raw_hit`, before `get_hit:free()`.
- Other LuaRT native fixture tests passed:
  - `test_spongejit_lua_compile_lua_rt_arithmetic.lua`
  - `test_spongejit_lua_compile_lua_rt_stack.lua`
  - `test_spongejit_lua_compile_lua_rt_exec.lua`
- No evidence of a freed-artifact or lifetime-after-free issue for the first crash: all FFI cdata locals are live, and `free()` is not reached.
- The immediate ABI/layout mismatch is between the test fixture’s `LuaRTTable` cdef and `lua_rt_object_model.lua`.
- The deeper native safety fact is that emitted `select(...)` is not a control-flow guard. Unsafe memory operands inside select branches may be loaded unconditionally.
- Correct cdef alone is insufficient if `hash` is null; allocating a hash entry bank avoids the crash in evidence runs.
- There is no centralized generated FFI cdef for the test fixture; the object test manually duplicates runtime layouts.
- The MoonCFG validator validates semantic/runtime value shape but not host FFI fixture layout compatibility or non-null pointer preconditions.

## Planner Output — 2026-06-06 09:57:29

## Goal
Fix the LuaRT object segfault by aligning test FFI layouts with the runtime model and making emitted table hash access control-flow guarded rather than `select(...)`/eager-boolean guarded.

## Plan
1. Add canonical FFI cdefs:
   - In `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_value_model.lua`, add `M.FFI_CDEF` for `LuaRTValue`.
   - In `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_object_model.lua`, add `M.FFI_CDEF` for:
     - `LuaRTString`
     - `LuaRTTableHashEntry`
     - `LuaRTTable` with fields in exact `TYPE_DECL` order:
       `array, array_len, hash, hash_capacity, hash_count, metatable_kind, ...`

2. Update `test_spongejit_lua_compile_lua_rt_objects.lua`:
   - Replace the manual stale `ffi.cdef[[...]]` block with:
     ```lua
     ffi.cdef(ValueModel.FFI_CDEF .. "\n" .. ObjectModel.FFI_CDEF)
     ```
   - Add layout assertions for `LuaRTTable`:
     - `hash == 16`
     - `hash_capacity == 24`
     - `hash_count == 32`
     - `metatable_kind == 40`
   - Initialize `tables[0].hash` to null and `hash_capacity/hash_count` to `0` for the existing array-hit and miss cases, proving null/zero-capacity tables do not crash.
   - Add a hash bank later in the test:
     ```lua
     local hash = ffi.new("LuaRTTableHashEntry[8]")
     tables[0].hash = hash
     tables[0].hash_capacity = 8
     ```
   - Add coverage for hash raw get and hash raw set with key `3`, verifying occupied-entry lookup/update still works.

3. Update `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua`:
   - Add helpers near pointer/null utilities:
     - `ptr_null(type_name)`
     - `ptr_not_null(expr, type_name)`
     - fresh block-name counter reset per `render_kernel`.
   - Rewrite `render_raw_get(...)` to emit a `block ... -> LuaRTRawGetResult` expression with early `yield`s:
     - first guard `tablev.tag == TableTag`
     - then array path guarded by array bounds and non-null `array`
     - then hash path guarded by:
       - hash key type
       - `hash_capacity > 0`
       - `hash_capacity <= HASH_PROBE_LIMIT`
       - non-null `hash`
     - probe entries only inside nested `if hash_capacity > i then ... end`
     - do not put `tbl.hash[i]` loads inside `select`, eager `and`, or eager `or`.
   - Rewrite `render_table_raw_set_can_write(...)` similarly as a `block ... -> bool` expression with nested guards before any `tbl.hash[i]` access.
   - Rewrite the `CFG.RuntimeTableRawSet` emission loops to avoid combined conditions like:
     ```lua
     if not hash_done and in_cap and render_hash_match(e, key) then
     ```
     Use nested `if` blocks so `e.state/e.key/e.value` are only touched after capacity and non-null hash checks.
   - Leave `RuntimeRawGetValueOrNil` as `select(rawget.hit, rawget.value, nil)` because it only selects already-materialized safe struct fields.

4. Verification commands:
   ```sh
   cargo build --release
   luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua
   luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arithmetic.lua
   luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_stack.lua
   luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_exec.lua
   ```

## Files to Modify
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_value_model.lua` - add canonical `FFI_CDEF`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_object_model.lua` - add canonical object/table/hash `FFI_CDEF`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` - replace unsafe eager hash access emission with guarded block expressions/statements.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua` - use canonical cdefs, initialize hash fields, add null/zero-capacity and hash-bank coverage.

## New Files (if any)
None.

## Risks
- Moonlift boolean `and/or` and `select(...)` are eager at lowering time; do not use them as memory guards.
- Block expressions returning `LuaRTRawGetResult` must use unique block labels to avoid duplicate-label collisions.
- Positive `hash_capacity` with null `hash` should be treated as malformed/no-hit/no-write, not dereferenced.

## Worker Output — 2026-06-06 10:25:13

## Completed
Implemented the LuaRT objects segfault fix.

- Added canonical FFI cdefs for `LuaRTValue`, `LuaRTString`, `LuaRTTableHashEntry`, and `LuaRTTable`.
- Updated LuaRT object test to use canonical cdefs, assert layout offsets, initialize hash fields, and cover null/zero-capacity plus hash-bank get/set.
- Reworked table raw get/set emission to avoid eager `select` / boolean guarding around unsafe hash loads. Hash access is now behind explicit Moonlift control with null/capacity checks.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_value_model.lua` - added `M.FFI_CDEF`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_object_model.lua` - added canonical object/table/hash `M.FFI_CDEF`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` - guarded raw get, raw set can-write, and raw set hash access paths.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua` - replaced stale cdefs, added layout/hash coverage.

## Tests Run
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arithmetic.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_stack.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_exec.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua`
- `luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua`

## Notes
- No remaining blockers.
- Did not run `cargo build --release`; LuaJIT tests using the current native library passed.
