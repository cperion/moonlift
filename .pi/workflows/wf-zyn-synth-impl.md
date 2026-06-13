# Zyn Moonlift Synth Implementation 
Plan implementation of examples/synth/zyn_moonlift_synth_impl.mlua from zyn_moonlift_synth_headers.mlua and zyn_moonlift_synth_spec.md, following THE_MOONLIFT_DESIGN_BIBLE discipline. Implementation must transcribe the spec: internal regions/protocols, ABI status only at F.* seals, no hidden state or convenient exits.
**Workflow ID**: wf-zyn-synth-impl
**Started**: 2026-06-13 09:00:09
---

## Edit-planner Output — 2026-06-13 09:03:37

### Precondition Checks

- Confirm `examples/synth/zyn_moonlift_synth_impl.mlua` still does **not** exist.
- Confirm `examples/synth/zyn_moonlift_synth_headers.mlua` remains the source of truth:
  - Encodings at lines 52-209.
  - Products at lines 213-758.
  - Regions at lines 760-1179.
  - ABI function headers at lines 1181-1203.
- Confirm `examples/synth/zyn_moonlift_synth_spec.md` still contains:
  - ABI mapping lines 20-46.
  - Storage contract lines 48-98.
  - Patch format lines 100-268.
  - Program prep lines 270-292.
  - Event/voice/DSP/render/parameter semantics lines 294-442.
  - Admission rule lines 445-450.
- Use `LANGUAGE_REFERENCE.md` header/implementation closure pattern: implementation should call header closures with body strings/bindings, not duplicate signatures.

---

### Files to Modify

No existing files should be modified. The header and spec are contracts only.

---

### New Files

#### `examples/synth/zyn_moonlift_synth_impl.mlua`

**Purpose**: Implement every region and ABI seal declared by `zyn_moonlift_synth_headers.mlua`, faithfully transcribing `zyn_moonlift_synth_spec.md`.

**Contents sketch / edit blocks**

1. **Lines 1-35: Add module scaffold**
   - Load header:
     - `local H = dofile("examples/synth/zyn_moonlift_synth_headers.mlua")`
     - bind `M/E/T/R/F`.
   - Add comment: implementation bodies are transcription of the sibling spec.
   - Return `M` at end after replacing closures with implemented bodies.
   - Do **not** mutate header file.

2. **Lines 36-140: Add constants and helper binding tables**
   - Add Lua constants for:
     - magic `0x5a594e4d`
     - version `1`
     - free-list empty sentinel `0xffffffff`
   - Build reusable body binding table containing `T`, `R`, `F`, helper fragments, and needed constants.
   - Do not create hidden runtime state in Lua tables.

3. **Lines 141-320: Add internal helper regions/exprs**
   - Checked arithmetic:
     - `checked_add_index`
     - `checked_mul_index`
     - `align_up_index`
   - Arena:
     - `arena_alloc_bytes`
     - `arena_alloc_array_*` helpers or one typed byte allocator plus typed casts.
   - Patch reads:
     - little-endian `read_u16_le`, `read_u32_le`, `read_f32_le`.
   - Validation:
     - byte range/alignment checks
     - view/buffer validation
     - finite f32 check
     - clamp/min/max/abs
   - DSP:
     - deterministic RNG/noise step
     - denormal clamp.
   - All helpers must use named exits, e.g. `ok(...) | overflow | malformed(...) | exhausted`.

4. **Lines 321-520: Implement storage ABI**
   - `F.synth_required_storage`
     - Transcribe spec lines 48-52 and layout order lines 64-81.
     - Return `0` on invalid config or overflow.
   - `F.synth_init`
     - Validate inputs per lines 53-63.
     - Lay out storage in exact order lines 64-81.
     - Initialize all fields per lines 83-98.
     - Map only here to `E.AbiStatus`.

5. **Lines 521-760: Implement memory/lifetime regions**
   - Header lines 769-816:
     - `R.borrow_published_program`
     - `R.publish_prepared_program`
     - `R.retire_prepared_program`
     - `R.borrow_voice_state`
     - `R.borrow_effect_state`
     - `R.borrow_pad_table`
     - `R.reset_render_scratch`
     - `R.enter_render_memory`
     - `R.close_synth_storage`
   - Preserve generation checks and explicit stale/missing/bad-state exits.

6. **Lines 761-1060: Implement patch decoding**
   - Header lines 823-832:
     - `R.decode_patch_source`
     - `R.next_patch_section`
   - Transcribe Patch Format V1 lines 100-174:
     - magic/version
     - section directory layout
     - sorted `(kind,index)`
     - non-overlap
     - bounds/alignment
     - unknown kind → `unsupported_section`
     - malformed structure → `malformed`.

7. **Lines 1061-1500: Implement primitive plan preparation**
   - Header lines 834-904:
     - tuning, envelope, LFO, filter, modulation, additive, subtractive, pad, effect slot, effect bus.
   - Parse only fixed records specified in lines 175-268.
   - Allocate arrays only through explicit arena products.
   - No default/disabled/bypass exit unless the spec says so.

8. **Lines 1501-1800: Implement layer/part/program prep**
   - Header lines 880-920:
     - `prepare_layer`
     - `prepare_part`
     - `prepare_program`
     - `validate_program`
     - `rebuild_pad_cache`
   - Restore `arena.used` on failure.
   - Build one immutable `PreparedProgram`.
   - Validate all rules from spec lines 251-268.

9. **Lines 1801-2120: Implement events/control**
   - Header lines 927-978:
     - `classify_host_event`
     - `classify_midi_event`
     - `update_control`
     - `resolve_parameter`
     - `apply_parameter_event`
     - `apply_transport_event`
     - `apply_midi_event`
     - `apply_host_events`
   - Event rules from spec lines 294-313.
   - `classify_*` regions are the only owners of event kind tags.

10. **Lines 2121-2500: Implement voice pool/lifecycle**
    - Header lines 984-1029:
      - layer iteration
      - allocation
      - stealing
      - start/release/all-notes/panic
      - lifecycle
      - retire
    - Dense active list, free-list, generation checks, and tie rules exactly from spec lines 315-359.

11. **Lines 2501-2920: Implement modulation/envelope/LFO/filter**
    - Header lines 1036-1061.
    - Transcribe DSP rules lines 362-395.
    - Tag owner regions must exhaustively switch declared tag encodings.

12. **Lines 2921-3300: Implement tone fields**
    - Header lines 1069-1091:
      - additive
      - subtractive
      - pad
      - tone-mask routing
    - Render exactly `ctx.shape.frame_count`.
    - `route_layer_tone_generators` owns `E.ToneMask`.

13. **Lines 3301-3700: Implement audio/effects/metering**
    - Header lines 1099-1144:
      - clear
      - mix
      - pan/gain
      - effect slot/bus
      - inserts/sends
      - finalize
    - Follow mixing/effects/finalize rules lines 396-406.

14. **Lines 3701-4050: Implement render orchestration**
    - Header lines 1151-1179:
      - `render_voice`
      - `render_part_voices`
      - `render_all_parts`
      - `render_block`
    - Render order must be exactly spec lines 408-421.

15. **Lines 4051-4300: Implement remaining ABI seals**
    - Header lines 1185-1203:
      - `synth_prepare_program`
      - `synth_render_block`
      - `synth_set_parameter`
      - `synth_note_on`
      - `synth_note_off`
      - `synth_all_notes_off`
      - `synth_panic`
    - ABI status integers appear only in these `F.*` bodies.

**Patterns to enforce**

- Internal regions return named protocol exits only.
- `E.AbiStatus` values are used only by `F.*` functions.
- Stored tags are consumed only by their declared owner regions.
- All pointer/view access must be guarded by explicit bounds/null validation before use.
- No “temporary convenient” exits; every exit must be justified by the spec.

**Danger zones**

- Storage layout order/alignment must exactly match spec lines 64-81.
- `arena.used` rollback on failed program prep is required.
- `render_block` order must not be rearranged.
- Do not mutate immutable `PreparedProgram` in parameter handling.
- Do not scatter switches over `kind`, `tone_mask`, effect kind, filter model, etc.

---

#### `tests/test_zyn_moonlift_synth_impl.lua`

**Purpose**: Compile/load and smoke-test the implementation against the spec.

**Contents sketch**

- Load implementation with `moonlift.mlua_run`.
- Assert every `M.R.*` and `M.F.*` header entry is now implemented.
- Bundle/compile all implemented regions/functions.
- Add minimal FFI-backed checks:
  - storage size/init happy path
  - invalid config → status
  - malformed patch → bad patch
  - event classification paths
  - voice allocate/start/release/retire
  - silent render returns `ok`.

---

### Order of Operations

1. Create `examples/synth/zyn_moonlift_synth_impl.mlua` scaffold.
2. Add internal helpers before any region body depends on them.
3. Implement storage sizing/init first; many later regions depend on initialized storage shape.
4. Implement borrow/lifetime regions.
5. Implement patch decoding and preparation bottom-up.
6. Implement event/control routing.
7. Implement voice pool/lifecycle.
8. Implement modulation/DSP/tone/effect primitives.
9. Implement render orchestration.
10. Implement ABI seals last, because they map all internal outcomes.
11. Add compile test.
12. Add behavioral smoke tests.
13. Run verification commands.

---

### Testing Strategy

Run incrementally:

```sh
cargo build --release
luajit tests/test_zyn_moonlift_synth_impl.lua
```

After scaffold/helper work:
- Load implementation only; ensure no parse errors.

After each region family:
- Bundle/compile that family and dependencies.
- Add one minimal smoke assertion where possible.

Final checks:
- Full test file.
- Compile/load `examples/synth/zyn_moonlift_synth_impl.mlua`.
- Evidence should include commands run and exact failures if blocked by compiler/backend limitations.

---

### Structured Edit Plan Sidecar

Updated structured edit plan for workflow `wf-zyn-synth-impl`, default sidecar `main`, revision `r1`.

Created tasks `T001`–`T017` covering:
- implementation scaffold,
- helper fragments,
- storage,
- memory/lifetime,
- patch prep,
- events,
- voice lifecycle,
- DSP/tone/effects/render,
- ABI seals,
- compile and behavioral tests,
- verification commands.

---

### Pattern Memo

- ABI status integers only in `F.*` bodies.
- Internal failure/success is always a named region continuation.
- Each encoded tag has exactly one owner region.
- Arena allocation is explicit, monotonic, and rolled back on failed program prep.
- Render order must match spec exactly.
- No hidden Lua runtime state; Lua may generate/bind declarations only.

## Worker Output — 2026-06-13 09:10:12

## Completed
Implemented T001 only: created the synth implementation scaffold and verified the correct `.mlua` header/body idiom before writing it.

- Uses `moon.dofile(...)` to load the `.mlua` header, because standard Lua `dofile` cannot parse Moonlift islands.
- Binds `M/E/T/R/F`.
- Adds compile-time constants and a future body binding table.
- Leaves all region/function bodies unimplemented for later tasks.

## Files Changed
- `examples/synth/zyn_moonlift_synth_impl.mlua` - new scaffold module.

## Notes
Verification run:

```sh
luajit -e 'package.path="./lua/?.lua;./lua/?/init.lua;"..package.path; local moon=require("moonlift"); local M=moon.dofile("examples/synth/zyn_moonlift_synth_impl.mlua"); print("loaded_impl", type(M), type(M.R.borrow_published_program), M.R.borrow_published_program.kind, M.F.synth_required_storage.kind)'
```

Result: scaffold loads successfully.

Marked edit-plan task `T001` done with evidence.

## Worker Output — 2026-06-13 09:33:50

## Completed
- Completed `T002`: implemented primitive helper fragments under `M.HLP`.
- Claimed `T003` and implemented a substantial partial storage sizing/init body, but blocked it because `synth_init` is not compile-verified.

## Files Changed
- `examples/synth/zyn_moonlift_synth_impl.mlua`
  - Added helpers: checked add/mul, align, byte range validation, byte/view/stereo validation, arena allocation, LE u16/u32/f32 readers, finite/clamp/min/max/abs, RNG/noise, denormal clamp.
  - Added partial `F.synth_required_storage`.
  - Added partial `F.synth_init`.

## Notes
Verification:
- Module loads successfully.
- `read_u32_le` helper compiled/executed in a probe and returned expected `1515802189` for bytes `4d 4e 59 5a`.

Blocked:
- `T003` marked blocked in edit plan.
- `F.synth_required_storage:compile()` via Cranelift timed out after 60s.
- C backend lowering reached tcc but failed on generated C.
- `F.synth_init:compile()` currently hits:
  - `(asdl.gc_ctor.1.false):10: bad arg #1 to 'MoonTree.ExprTyped': expected 'MoonType.Type' got 'nil'`

Workflow ID: `wf-zyn-synth-impl`

## Worker Output — 2026-06-13 09:54:14

## Completed
- Completed `T005`: implemented patch source/header decoding and section directory iteration.
- Claimed `T006` and implemented all primitive patch preparation region bodies, but marked it **blocked** because several wrappers still fail backend lowering.
- Did not attempt `T007`; no ready tasks remain.

## Files Changed
- `examples/synth/zyn_moonlift_synth_impl.mlua`
  - Added `R.decode_patch_source`
  - Added `R.next_patch_section`
  - Added primitive prep bodies:
    - `R.prepare_tuning`
    - `R.prepare_envelope`
    - `R.prepare_lfo`
    - `R.prepare_filter`
    - `R.prepare_modulation`
    - `R.prepare_additive_plan`
    - `R.prepare_subtractive_plan`
    - `R.prepare_pad_plan`
    - `R.prepare_effect_slot`
    - `R.prepare_effect_bus`
  - Fixed `HLP.checked_mul_index` zero exits to return `as(index, 0)`.

## Notes
Verification:
- Module load succeeds.
- `T005` wrapper probes compile successfully.
- `T006` partial compile status:
  - Compile OK: `prepare_envelope`, `prepare_lfo`, `prepare_filter`, `prepare_pad_plan`, `prepare_effect_slot`
  - Compile fails: `prepare_tuning`, `prepare_modulation`, `prepare_additive_plan`, `prepare_subtractive_plan`, `prepare_effect_bus`
  - Error:
    ```text
    ./lua/moonlift/tree_to_back.lua:2344:
    moonlift tree_to_back unsupported lowering:
    aggregate let initializer could not be lowered
    ```
  - Appears tied to aggregate products containing `view(...)` fields.

Edit plan:
- `T005` marked done.
- `T006` marked blocked with precise evidence.
- No ready task remains.

## Scout Output — 2026-06-13 10:06:20

## Files Retrieved

1. `lua/moonlift/tree_to_back.lua` (lines 93-103, 265-354) - Backend environment representation for scalar/stack/view locals; view/aggregate classification and layout helpers.
2. `lua/moonlift/tree_to_back.lua` (lines 901-920, 1299-1349, 1450-1457, 1668-1772, 2332-2350, 2559-2624, 2735-2786) - Expression/call/aggregate/view lowering, aggregate `StmtLet` failure site, function ABI lowering.
3. `lua/moonlift/type_size_align.lua` (lines 1-180) - Memory layout classification; `TView` layout is `{ptr,index,index}`.
4. `lua/moonlift/type_to_back_scalar.lua` (lines 1-85) - Backend scalar availability; `TView`, slices, arrays, aggregates unavailable as scalar values.
5. `lua/moonlift/type_abi_classify.lua` (lines 1-82) - ABI class decisions; views/closures/slices descriptors, aggregates indirect.
6. `lua/moonlift/type_func_abi_plan.lua` (lines 1-91) - Executable function ABI; view params flattened to data/len/stride, aggregate params by pointer, view result out pointer.
7. `lua/moonlift/schema/tree.asdl` (lines 25-31, 130-143, 271-284) - AST/schema for views, aggregate exprs, backend expression result variants.
8. `lua/moonlift/schema/open.asdl` (lines 1-56, 120-139) - Open slots and slot values including `ExprSlot`, `FuncSlot`, `SlotValueFunc`.
9. `lua/moonlift/host.lua` (lines 299-392, 58-84) - `moon.func` header/body closure implementation and `CallableFunc:compile` dependency bundling.
10. `lua/moonlift/chain.lua` (lines 68-132) - Full quote `{bindings}` path: fills splices, expands open slots, attaches `_dep_values`.
11. `lua/moonlift/host_splice.lua` (lines 130-197) - Expression splice coercion; function-like host value becomes `ExprRef(ValueRefName(name))`.
12. `lua/moonlift/parse.lua` (lines 827-831, 977-1015, 2524-2533) - Expression holes parse as `ExprSlotValue(ExprSlot(..., ty=nil))`; calls wrap hole as callee.
13. `lua/moonlift/tree_typecheck.lua` (lines 387-395, 629-645, 675-722, 869-870) - Ref/call typing, aggregate typing, `ExprSlotValue` typing failure site.
14. `lua/moonlift/open_expand.lua` (lines 420-451, 612-619, 673-688, 818-845) - Open-slot lookup/expansion for expression refs and calls.
15. `lua/moonlift/sem_layout_resolve.lua` (lines 217-281) - Field/size/align resolution and aggregate recursion.

## Key Code

### Blocker 1: aggregate lowering with view fields

`tree_to_back.lua` separates scalar values from view descriptors:

```lua
local function expr_value(result)
    if pvm.classof(result) == Tr.TreeBackExprValue then return result end
    return nil
end

local function expr_view_value(result)
    local cls = pvm.classof(result)
    if cls == Tr.TreeBackExprView or cls == Tr.TreeBackExprStridedView then return result end
    return nil
end
```

`TView` is not an aggregate in backend classification:

```lua
local function is_view_type(ty)
    return pvm.classof(ty) == Ty.TView
end

local function is_aggregate_type(ty)
    local cls = pvm.classof(ty)
    return cls == Ty.TArray or cls == Ty.TNamed
end
```

`ExprView` lowers to `view_to_back`, producing `TreeBackExprStridedView`, not `TreeBackExprValue`:

```lua
[Tr.ExprView] = function(self, env)
    return pvm.once(view_to_back:one_uncached(self.view, env))
end
```

`ExprAgg` requires every field initializer to be `expr_value(...)`:

```lua
local field_val = expr_value(expr_to_back:one_uncached(fi.value, current))
...
if field_val == nil then
    return pvm.once(Tr.TreeBackExprUnsupported(current, cmds, "struct field value unsupported"))
end
```

Aggregate `let` requires the whole initializer to be `TreeBackExprValue`; unsupported aggregate init becomes the current blocker:

```lua
local lowered = expr_to_back:one_uncached(self.init, env)
local init = expr_value(lowered)
if init == nil then lowering_unsupported("aggregate let initializer could not be lowered") end
```

Schema confirms view values have separate backend result variants:

```asdl
TreeBackExprResult =
    TreeBackExprValue(... BackValId value, BackScalar ty)
  | TreeBackExprView(... BackValId data, BackValId len)
  | TreeBackExprStridedView(... BackValId data, BackValId len, BackValId stride)
  | TreeBackExprUnsupported(...)
```

Layout/ABI facts:

```lua
-- type_size_align.lua
[Ty.TypeClassView] = function(self, ty, env, target)
    local ptr = raw_layout(ptr_layout(target))
    local index = raw_layout(index_layout(target))
    return pvm.once(product_layout({ ptr, index, index }))
end
```

```lua
-- type_to_back_scalar.lua
[Ty.TypeClassView] = function(self, ty)
    return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
end
```

```lua
-- type_func_abi_plan.lua
if pvm.classof(param.ty) == Ty.TView then
    return Ty.AbiParamView(... data, len, stride)
end
```

Observed repro:

```text
./lua/moonlift/tree_to_back.lua:2344:
moonlift tree_to_back unsupported lowering:
aggregate let initializer could not be lowered
```

With a minimal `HasView { xs: view(i32), n: index }`, module layout facts showed:

```text
LayoutNamed HasView size 32 align 8
  xs offset 0 TView
  n  offset 24 TScalar
```

### Blocker 2: function-header body closures and `@{dep}(x)`

Full quote binder path in `chain.lua`:

```lua
local binding = hs.fill(session, ss.slot, v, ...)
...
env = e.env_with_fills(env, bindings)
local expanded = expand_fn(e, parsed.value, env)
local result = wrap_fn(expanded, parsed, T, src, bound_values)
...
result._dep_values = bound_values
```

`host_splice.lua` turns function-like expression splices into name refs:

```lua
if kind == "func" or kind == "extern_func" then
    expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(rawget(value, "name") or "?"))
end
```

Function header body path in `host.lua` does not use the quote binder expansion path for body splices:

```lua
local full = strip_bodyless_decl_end(header_src) .. "\n" .. arg .. "\nend"
local res = require("moonlift.parse").Define(T2).parse_func(full)
...
return setmetatable({ kind = "func", ... func = fv, item = Tr2.ItemFunc(fv), ... }, CallableFunc)
```

Parser fact: expression hole is an `ExprSlotValue` with `ExprSlot(..., ty=nil)`:

```lua
if k == TK.hole then
    local slot = O.ExprSlot(self:splice_key("expr", text), text, nil)
    self:record_splice_slot(text, O.SlotExpr(slot), "expr")
    return Tr.ExprSlotValue(Tr.ExprSurface, slot)
end
```

Typechecker failure site:

```lua
[Tr.ExprSlotValue] = function(self, ctx)
    return pvm.once(result_expr(
        Tr.ExprSlotValue(Tr.ExprTyped(self.slot.ty), self.slot),
        self.slot.ty,
        {}
    ))
end
```

If `self.slot.ty == nil`, ASDL constructor throws:

```text
(asdl.gc_ctor.1.false):10:
bad arg #1 to 'MoonTree.ExprTyped':
expected 'MoonType.Type' got 'nil'
```

Observed AST for body-header repro `h{dep=dep}[[ return @{dep}(x) ]]`:

```text
func class FuncLocal main
stmt class StmtReturnValue
expr class ExprCall h ExprSurface
callee class ExprSlotValue h ExprSurface
slot key splice:expr:splice.1
slot ty nil
parse slots: dep / SlotExpr / role expr
```

Observed contrast: full quote path works:

```lua
local f = moon.func{dep=dep}[[
func main(x: i32): i32
  return @{dep}(x)
end
]]
```

Result:

```text
result 42
compile ok? true
```

AST for full quote path:

```text
expr class ExprCall
callee ExprRef
callee ref class ValueRefName dep
_dep_values table present
```

## Relationships

- `parse.lua` creates open slots for `@{...}`.
- `chain.lua` is the normal binder path for `moon.func{...}[[...]]`; it calls `host_splice.fill`, then `open_expand`, then wraps the expanded function and attaches `_dep_values`.
- `host.lua` function-header body closure reconstructs source text and calls `parse_func(full)` directly. It only text-substitutes header type bindings, not body expression splices.
- Therefore `@{dep}` inside a body-only implementation remains an `ExprSlotValue` with nil `ExprSlot.ty`.
- `tree_typecheck.lua` attempts to construct `ExprTyped(self.slot.ty)` for any remaining `ExprSlotValue`; nil causes the ASDL error.

- `type_size_align.lua` gives views a 24-byte descriptor layout on 64-bit targets.
- `type_to_back_scalar.lua` makes views unavailable as scalar backend values.
- `tree_to_back.lua` has special locals/results for views (`TreeBackViewLocal`, `TreeBackExprStridedView`).
- `tree_to_back.lua` aggregate construction expects all field initializers to lower as scalar/address `TreeBackExprValue`.
- A view field initializer lowers as `TreeBackExprStridedView`, so `ExprAgg` returns unsupported; aggregate `StmtLet` reports the generic line-2344 error.

## Observations

- Current backend has two separate value channels: scalar/address `TreeBackExprValue` and view descriptor `TreeBackExprView` / `TreeBackExprStridedView`.
- Aggregate initialization only consumes the scalar/address channel.
- Non-aggregate `StmtLet` has a special case for view initializer bindings, but aggregate field initialization does not.
- Function ABI lowering knows how to flatten top-level view parameters, but ordinary `ExprCall` lowering currently consumes arguments via `expr_value(...)`.
- `moon.func` header body closures differ materially from `moon.region` headers: region headers call `M.region(merged)(full)` when bindings exist; function headers call raw `parse_func(full)`.
- The exact nil-typed expression slot path is: `@{dep}` in expression position → `ExprSlotValue(ExprSlot ty=nil)` → no expansion → `tree_typecheck ExprSlotValue` → `ExprTyped(nil)` constructor error.
