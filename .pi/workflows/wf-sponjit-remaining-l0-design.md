# SponJIT Remaining Exact L0 Design 
Focused workflow for designing and implementing exact no-residual coverage for remaining SponJIT L0 opcodes after the large copy-link-patch workflow exceeded context.
**Workflow ID**: wf-sponjit-remaining-l0-design
**Started**: 2026-06-01 07:19:31
---

## Scout Output — 2026-06-01 07:24:58

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` (lines 1-84) — authoritative current L0 classification; target opcodes are outside exact inline/boundary coverage.
2. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-430) — semantic SSA lowering and current explicit rejection points for missing opcodes.
3. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-480) — existing SSA node vocabulary, including field/array ops but no upvalue ops.
4. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-343) — current fact bundles for numeric, field, array, call; SETTABUP is skipped.
5. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-340) — fact lattice, dependencies, shorthand facts.
6. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-260) — 64-bit selector/fact ABI bits.
7. `experiments/lua_interpreter_vm/spongejit/src/fact_schema.lua` (lines 1-230) — higher-level fact vocabulary, including raw array/string slot/upvalue sketches.
8. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-420) — SSA→Stencil IR lowering; existing holes/roles for field and array payloads.
9. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-186) — Stencil IR op and data-hole vocabulary.
10. `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` (lines 1-184) — native lowerer whitelist; excludes array ops/array payload role and upvalues.
11. `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` (lines 1-1040) — native x64 emitter; supports slots, i64 arithmetic, guards, field load/store; no array/upvalue/pow.
12. `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` (lines 1-540) — descriptor ABI roles and validation.
13. `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` (lines 1-360) — copy/link/patch materializer; supports payload patching including `array_base_offset`.
14. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-271) — generated bank C ABI/context.
15. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-760) — generated selector ABI, L0 table, exact-native flag requirements, fact remapping.
16. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-132) — Lalin VM Value/Table/UpVal/LClosure layouts.
17. `experiments/lua_interpreter_vm/src/op/load.lua` (lines 1-175) — Lalin VM GETUPVAL/SETUPVAL semantics.
18. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-260) — Lalin VM GETTABUP/GETTABLE/GETI/SETTABUP/SETTABLE/SETI handlers.
19. `experiments/lua_interpreter_vm/src/regions_table.lua` (lines 1-360) — local raw table get/set and metamethod chains.
20. `experiments/lua_interpreter_vm/src/regions_key.lua` (lines 1-130) — local table key hash/equality/array-index protocol.
21. `experiments/lua_interpreter_vm/src/regions_upvalue.lua` (lines 1-180) — local upvalue representation/lifecycle.
22. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-260, 380-540) — local arithmetic; POW/POWK are explicit errors.
23. `.vendor/Lua/lopcodes.h` (lines 170-300) — PUC opcode operand contracts.
24. `.vendor/Lua/lvm.c` (lines 940-1120, 1270-1405, 1450-1540) — PUC opcode behavior for table/upvalue/pow.
25. `.vendor/Lua/lvm.h` (lines 70-165) — PUC fast get/set macros.
26. `.vendor/Lua/ltable.h` (lines 1-180) — PUC table fast array/hash layout and pset result semantics.
27. `.vendor/Lua/lobject.h` (lines 650-800) — PUC UpVal/LClosure/Table/Node layout.
28. `.vendor/Lua/llimits.h` (lines 250-280) — PUC numeric pow definition.
29. `experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua` (lines 1-108) — truthful semantic L0 coverage test.
30. `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua` (lines 1-580) — current native support tests and explicit missing assertions.
31. `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua` (lines 1-260) — descriptor/native lowerer coverage/rejection tests.
32. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-260) — SSA/fact invariants.
33. `experiments/lua_interpreter_vm/tests/test_spongejit_selector_no_fallback.lua` (lines 1-73) — selector must report missing coverage, not fallback.
34. `experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua` (lines 1-560) — generated bank + materializer end-to-end exact native tests.
35. `experiments/lua_interpreter_vm/tests/test_spongejit_retired_fallback.lua` (lines 1-69) — forbidden residual/helper token audit.
36. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-220), `SPONJIT_FOUNDRY_SSA.md` (lines 1-306), `SPONJIT_RUNTIME_DESIGN.md` (lines 1-240), `SPONJIT_COPY_LINK_PATCH.md` (lines 1-260) — current docs/spec boundaries.

## Key Code

### Current missing L0 coverage

Running strict semantic L0 audit reports exactly:

```text
strict semantic L0 coverage missing opcodes:
9:GETUPVAL, 10:SETUPVAL, 11:GETTABUP, 12:GETTABLE, 13:GETI,
15:SETTABUP, 16:SETTABLE, 17:SETI, 26:POWK, 38:POW
```

`opcode_coverage.lua` currently includes only:

```lua
local INLINE_FACTED = {
  ADDI = true, SHLI = true, SHRI = true,
  ADD = true, SUB = true, MUL = true, MOD = true, DIV = true, IDIV = true,
  ...
  GETFIELD = true, SETFIELD = true, SELF = true,
}
```

No target opcode is in `INLINE_FACTED` or `BOUNDARY`, so they classify unsupported.

### PUC operand semantics

From `lopcodes.h`:

```c
OP_GETUPVAL,/* A B   R[A] := UpValue[B] */
OP_SETUPVAL,/* A B   UpValue[B] := R[A] */

OP_GETTABUP,/* A B C R[A] := UpValue[B][K[C]:shortstring] */
OP_GETTABLE,/* A B C R[A] := R[B][R[C]] */
OP_GETI,    /* A B C R[A] := R[B][C] */

OP_SETTABUP,/* A B C UpValue[A][K[B]:shortstring] := RK(C) */
OP_SETTABLE,/* A B C R[A][R[B]] := RK(C) */
OP_SETI,    /* A B C R[A][B] := RK(C) */

OP_POWK,/* A B C R[A] := R[B] ^ K[C]:number */
OP_POW, /* A B C R[A] := R[B] ^ R[C] */
```

From `lvm.c`, table opcodes use fast raw access, then metamethod finish paths if empty/not-table:

```c
vmcase(OP_GETTABLE) {
  TValue *rb = vRB(i);
  TValue *rc = vRC(i);
  lu_byte tag;
  if (ttisinteger(rc)) {
    luaV_fastgeti(rb, ivalue(rc), s2v(ra), tag);
  }
  else
    luaV_fastget(rb, rc, s2v(ra), luaH_get, tag);
  if (tagisempty(tag))
    Protect(luaV_finishget(L, rb, rc, ra, tag));
}
```

`SETTABLE`/`SETI` analogously use `luaV_fastset*`; success requires `HOK`, else `luaV_finishset`.

### PUC table layout facts

`lobject.h`:

```c
typedef struct Table {
  CommonHeader;
  lu_byte flags;
  lu_byte lsizenode;
  unsigned int asize;
  Value *array;
  Node *node;
  struct Table *metatable;
  GCObject *gclist;
} Table;
```

`ltable.h` array storage is not contiguous TValue ABI:

```c
#define getArrTag(t,k) (cast(lu_byte*, (t)->array) + sizeof(unsigned) + (k))
#define getArrVal(t,k) ((t)->array - 1 - (k))
#define farr2val(h,k,tag,res) ((res)->tt_ = tag, (res)->value_ = *getArrVal(h,(k)))
```

### PUC POW numeric semantics

`POW`/`POWK` use float arithmetic, not integer result arithmetic:

```c
#define op_arithf_aux(L,v1,v2,fop) { \
  lua_Number n1; lua_Number n2; \
  if (tonumberns(v1, n1) && tonumberns(v2, n2)) { \
    pc++; setfltvalue(s2v(ra), fop(L, n1, n2)); \
  }}
```

`luai_numpow`:

```c
#define luai_numpow(L,a,b) \
  ((void)L, (b == 2) ? (a)*(a) : l_mathop(pow)(a,b))
```

### Local Lalin VM representations

`products.lua` uses a different explicit VM layout:

```lua
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]
local Table = host.struct [[struct Table gc: GCHeader; flags: u32; array_len: index; array_cap: index; array: ptr(Value); node_mask: u32; node_count: index; nodes: ptr(Node); lastfree: ptr(Node); metatable: ptr(Table); shape_epoch: u32; ... end]]
local UpVal = host.struct [[struct UpVal gc: GCHeader; v: ptr(Value); closed: Value; stack_index: index; next_open: ptr(UpVal) end]]
local LClosure = host.struct [[struct LClosure gc: GCHeader; env: ptr(Table); proto: ptr(Proto); upvals: ptr(ptr(UpVal)); nupvals: u8 end]]
```

Local VM GETUPVAL/SETUPVAL:

```lua
let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
let uv: ptr(UpVal) = cl.upvals[b]
L.stack[base + as(index, a)] = *uv.v
```

```lua
let uv: ptr(UpVal) = cl.upvals[b]
let p: ptr(Value) = uv.v
p[0] = L.stack[base + as(index, a)]
```

### Current Spon SSA gaps

`ssa_lift.lua` has array lower helpers, but dispatch rejects array opcodes:

```lua
elseif op == "GETTABLE" or op == "GETI" then
  terminal = reject(g, op, pc, ev, op == "GETI" and "array_integer_get_not_lowered" or "dynamic_table_get_not_lowered")
elseif op == "SETTABLE" or op == "SETI" then
  terminal = reject(g, op, pc, ev, op == "SETI" and "array_integer_set_not_lowered" or "dynamic_table_set_not_lowered")
```

GETTABUP/SETTABUP are explicitly rejected in field lowering:

```lua
local function lower_field_get(g, op, pc, ev)
    if op == "GETTABUP" then return reject(g, op, pc, ev, "upvalue_table_not_lowered") end
```

```lua
local function lower_field_set(g, op, pc, ev)
    if op == "SETTABUP" then return reject(g, op, pc, ev, "upvalue_table_not_lowered") end
```

POW state:

```lua
local BIN_RR = { ADD=true, SUB=true, MUL=true, DIV=true, MOD=true, IDIV=true, ... } -- POW absent
local BIN_K = { ..., POWK=true, ... }
local K_TO_BIN = { ..., POWK="POW" }
...
local supported_i64_bin = { ADD=true, SUB=true, MUL=true, MOD=true, DIV=true, IDIV=true, ... } -- POW absent
```

So `POW` is not lowered; `POWK` reaches `real_op="POW"` then rejects as not semantically lowered.

### Existing facts/payloads/relocs

Fact signature ABI:

```lua
SLOT_FACT_BASE = {
  i64 = 0, is_i64 = 0,
  table = 8, is_table = 8,
  shape_known = 16,
  metatable_absent = 24,
  array_hit = 32,
  bounds_ok = 40,
  known_call_target = 48,
  key_i64 = 0,
}

GLOBAL_FACT_BIT = {
  barrier_clean = 56,
  const_i64 = 57,
  key_const = 58,
  nonzero_i64 = 59,
  shape_payload = 60,
  array_payload = 61,
  call_target_payload = 62,
}
```

Stencil descriptor/data roles already include:

```lua
slot, slot_store, imm, const, bool,
shape_offset, shape_id, metatable_offset, field_offset,
array_base_offset, call_target, barrier
```

Materializer can patch:

```lua
shape_offsets / shape_id
metatable_offsets / metatable_offset
field_offsets / field_offset
array_base_offsets / array_base_offset
```

### Native emitter support currently present

`stencil_native_x64.lua` supports:
- `GuardI64`
- `GuardTable`
- `GuardShape`
- `GuardMetatableAbsent`
- `FieldLoad`
- `FieldStore`
- i64 arithmetic/mod/idiv/div-to-f64
- constants/slots/fallthrough/guard/boundary exits

It does **not** implement `ArrayLoad`, `ArrayStore`, `GuardArrayHit`, `GuardBounds`, upvalue loads/stores, closure/proto/upvalue context loads, or POW.

`stencil_lower.lua` whitelist likewise excludes array ops:

```lua
local SUPPORTED_OP = {
  ...
  FieldLoad = true,
  FieldStore = true,
  ExitBoundary = true,
}
```

`ArrayLoad`, `ArrayStore`, `GuardArrayHit`, `GuardBounds`, `GETUPVAL`-style ops are absent.

### Spon native ABI/context

`sponbank.h`:

```c
typedef struct SponExecCtx {
  void *stack;
  SponTValueABI *k;
  SponTValueABI scratch[256];
  uint32_t exit_kind;
  uint32_t exit_pc;
  uint32_t exit_op_idx;
  uint32_t exit_hole;
} SponExecCtx;
```

There is no closure/proto/upvalue pointer field in `SponExecCtx`.

## Relationships

- Current maintained pipeline is:

```text
opcode/facts
→ ssa_lift.lua semantic SSA
→ ssa_opt.lua
→ ssa_to_stencil.lua Stencil IR
→ stencil_lower.lua
→ stencil_native_x64.lua executable bytes + descriptor relocs
→ build_bank.lua generated selector/bank
→ materialize_native_x64.lua copy/link/patch
```

- Table field specialization path exists only for register-table + constant string key:
  - facts: `is_table`, `shape_eq`, `metatable_absent`, `key_const`, `field_offset`
  - SSA: `GuardTable`, `GuardShape`, `GuardMetatableAbsent`, `FieldLoad/FieldStore`
  - reloc roles: `shape_offset`, `shape_id`, `metatable_offset`, `field_offset`
  - native emitter: loads table pointer from stack slot and loads/stores field at patched offset.

- Array path is partially represented but not executable:
  - facts exist: `is_table`, `metatable_absent`, `array_hit`, `bounds_ok`, `array_base_offset`, optional `key_i64`
  - SSA has `ArrayLoad`/`ArrayStore`
  - Stencil IR has `ArrayLoad`/`ArrayStore` and `array_base_offset`
  - descriptor/materializer know `array_base_offset`
  - dispatch rejects GETTABLE/GETI/SETTABLE/SETI before using array lowering
  - native lowerer/emitter do not support array ops/guards.

- Upvalue path is represented in the interpreter VM, but not in Spon SSA/stencil/native:
  - local VM has `LClosure.upvals -> UpVal.v -> Value`
  - PUC has `cl->upvals[B]->v.p`
  - SponExecCtx lacks closure/upvalue access
  - no `upvalue` fact bit, data role, hole, SSA node, or reloc role exists.

- GETTABUP/SETTABUP combine both missing areas:
  - upvalue access to fetch table value
  - then table access with constant string key
  - current field specialization can cover the table field part only after a table pointer is represented as a slot-like input.

- POW/POWK require numeric-number semantics:
  - PUC converts integer/float operands to `lua_Number`
  - result is float
  - non-number path leaves arithmetic opcode for adjacent MMBIN/MMBINK metamethod handling
  - current Spon numeric facts are i64-centered; no f64 number guard/unbox/pow operation is present.

## Observations

- Current truthful L0 count is 75/85; strict missing list exactly matches the task target.
- Residual/helper/fallback tokens are actively forbidden by `test_spongejit_retired_fallback.lua`.
- Selector tests require missing opcodes to report `SPON_SELECT_NO_CANDIDATE`, not select a hidden fallback.
- `fact_schema.lua` mentions `GETTABLE` raw string slot and `GETUPVAL` `upvalue_known`, but maintained SSA/fact-axis/native paths do not implement them.
- `ssa_fact_axes.lua` includes `GETTABUP` in `FIELD_GET`, but `ssa_lift.lua` rejects it as `upvalue_table_not_lowered`.
- `ssa_fact_axes.lua` includes `SETTABUP` in `FIELD_SET`, but `bundle_field_set` immediately returns for `SETTABUP`.
- Existing field tests use a synthetic `SponTestTable` with payload offsets; they do not prove actual PUC `Table` array/hash layout handling.
- Spon native byte surface uses PUC-style `SponTValueABI { value_, tt_ }` tags (`3`, `19`, `69`, etc.), while the local Lalin VM uses `Value { tag, aux, bits }` tags (`INTEGER=4`, `NUM=5`, `TABLE=7`, etc.).
- Local Lalin VM `op_pow`/`op_powk` are explicit `ERR_ARITH` stubs, whereas PUC Lua has real float pow semantics.

## Worker Output — 2026-06-01 09:24:23

## Completed
Implemented remaining exact SponJIT L0 coverage for:

`GETUPVAL SETUPVAL GETTABUP GETTABLE GETI SETTABUP SETTABLE SETI POWK POW`

Final strict coverage:

`exact native L0 entries=85 missing=0`

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - extended `SponExecCtx`, added `SponPrimitiveTable`, new reloc roles
- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` - added upvalue, f64/pow, barrier IR support
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - lowered upvalues, upvalue table fields, arrays, pow, barrier-after-store
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` - lowered new SSA nodes/holes to Stencil IR
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` - added new ops/roles
- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` - enabled native lowering for new ops/roles
- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` - emitted native x64 for upvalues, arrays, barriers, pow
- `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` - descriptor ABI roles for new relocations
- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` - materializer patching for new roles
- `experiments/lua_interpreter_vm/spongejit/src/facts.lua` - added numeric/array facts
- `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` - selector ABI updates
- `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` - fact bundles for new exact paths
- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - classified all remaining opcodes as exact inline candidates
- `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` - concrete L0 floor generation fixes
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - exact pattern alias preservation
- `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` - always inject exact concrete L0 floors
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.[ch]` - runtime patching for new relocations/opcodes
- Tests updated under `experiments/lua_interpreter_vm/tests/`

## Tests
Passed:

- `(cd experiments/lua_interpreter_vm/spongejit && make test)`
- `(cd experiments/lua_interpreter_vm/spongejit && make stencils)`
- `(cd experiments/lua_interpreter_vm/spongejit && make bank)`
- `(cd experiments/lua_interpreter_vm/spongejit && make test-bank)`
- `SPON_STRICT_SEMANTIC_L0=1 luajit experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua`

Coverage output:

`ok - SpongeJIT generated bank reports truthful semantic L0 coverage`
