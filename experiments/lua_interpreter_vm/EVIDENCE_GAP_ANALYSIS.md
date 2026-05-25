# Evidence Gap Analysis: Real Programs vs Current Library

## Real Program Analysis

Using actual Lua 5.5 bytecode from AWFY test suite (`big.lua`):

```
Operation distribution (from compiled bytecode):
  CALL:       50.9% (23 ops / 53 total)
  LOADK:      20.8% (11 ops)
  Control:    15.1% (8 ops: FOR, JMP, TEST)
  Arith:       9.4% (5 ops: ADD)
  Table:       3.8% (2 ops: SETTABLE)
  Other:       0.0%
```

## Current Stencil Coverage

**Library: 16 stencils (11 primitives + 5 compounds)**

Stencil analysis:
- `load` stencils: 2 (covers LOADI, LOADK)
- `arith` stencils: 4 (covers ADD, SUB, MUL, DIV, etc.)
- `guard` stencils: 2 (covers type checks)
- `control` stencils: 1 (covers branching)
- `table` stencils: 1 (GETTABLE only, no SETTABLE IC variants)
- `call` stencils: 0 (ZERO call stencils)
- `edge` stencils: 1

**Measured Coverage: 18.9%**

## Critical Gaps

### 1. CALL Operations (50.9% of bytecode)
**Current:** Zero specialized stencils
**Missing:**
- `call.known_lclosure` — call to known Lua function (monomorphic)
- `call.known_cclosure` — call to known C function
- `call.generic_dispatch` — type dispatch on function value
- `call.inline_native` — inline wrapper for common natives (ipairs, pairs, etc.)

**Impact:** Cannot compile half of all hot paths

### 2. Table Operations (GETTABLE, SETTABLE)
**Current:** One generic GETTABLE primitive only
**Missing:**
- `table.gettable_array_i64_ic1` — array access with inline cache (hot path)
- `table.gettable_shape_ic1` — object field access with shape IC
- `table.settable_array_i64_ic1` — array write with IC
- `table.settable_shape_ic1` — object write with shape IC
- `table.geti_bounds` — integer-indexed array with bounds check
- `table.seti_bounds` — integer-indexed array write with bounds check

**Impact:** Table operations are 10-20% of real programs, have no IC

### 3. Loop Specialization (15.1% control)
**Current:** Generic FORPREP/FORLOOP only
**Missing:**
- `loop.forloop_i64_positive` — integer loop with known positive step
- `loop.forloop_f64` — float loop
- `loop.forloop_upval` — loop with upvalue step/limit
- `loop.tforloop_pairs` — table iteration via pairs()

**Impact:** Loops execute thousands of times, generic version too slow

### 4. Load/Move Operations (20.8% of bytecode)
**Current:** Basic LOADK, LOADI
**Missing:**
- `value.load_const_bulk` — load multiple constants (table construction helper)
- `value.move_result_to_slots` — move multi-value returns to stack
- `value.loadtrue_loadfalse` — boolean constants with IC

**Impact:** Missed optimization opportunities in common patterns

## Honest Assessment

| Component | Coverage | Status |
|-----------|----------|--------|
| Arithmetic | ✓ | **Good** (9% of code, ~100% covered) |
| Load/Move | ✓ | **Adequate** (20% of code, ~60% covered) |
| Control | ⚠ | **Partial** (15% of code, ~40% covered) |
| Table | ✗ | **Inadequate** (4% of code, ~10% covered) |
| Call | ✗ | **Absent** (51% of code, 0% covered) |

**Overall coverage: 18.9% of hot bytecode**

## Action Items for Real Coverage

### Phase L1 (evidence-driven closure):
1. Generate `call.known_lclosure` and `call.known_cclosure` stencils
2. Generate `table.gettable_ic1` and `table.gettable_shape_ic1` stencils
3. Generate `table.settable_ic1` and `table.settable_shape_ic1` stencils
4. Generate `loop.forloop_i64_positive` specialization

**Expected result:** 40-50% coverage

### Phase L2 (composed compounds):
1. Compose call + table access patterns: `call_after_get`, `get_call_result`
2. Compose loop + table: `forloop_with_table_get`
3. Compose load + call: `load_args_call`

**Expected result:** 60-70% coverage

### Phase L3 (trace-shaped):
1. Profile actual traces with instrumentation
2. Promote frequently recurring multi-operation patterns
3. IC-informed stencil variants based on runtime feedback

**Expected result:** 80%+ coverage

## Why This Gap Exists

1. **Call is 50% of bytecode** — was treated as low-priority in Phase 1
2. **Table IC not bootstrapped** — needs actual call site profiling
3. **Loop specialization missing** — generic version has too much overhead
4. **No multi-op compounds yet** — L0 → L1 closure not fully utilized

## Next Execution Steps

```bash
# 1. Extract real opcode motifs from all AWFY programs
luajit experiments/lua_interpreter_vm/tools/extract_awfy_motifs.lua

# 2. Run closure rounds with real evidence
luajit experiments/lua_interpreter_vm/tools/closure_rounds_with_evidence.lua

# 3. Generate specialized stencils for top gaps
luajit experiments/lua_interpreter_vm/tools/generate_call_table_stencils.lua

# 4. Measure new coverage
luajit experiments/lua_interpreter_vm/tests/test_real_bytecode_evidence.lua
```

## Evidence-Driven Priorities

From real programs, in order:
1. **CALL stencils** (50% → 25% gap)
2. **Table IC stencils** (10% → 5% gap)
3. **Loop specialization** (6% → 2% gap)
4. **Load/move optimization** (8% → 2% gap)
5. **Control flow** (9% → 3% gap)

Closing top 3 would achieve **50%+ coverage**.
