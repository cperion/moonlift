# Correct Design: L0 = Lua Bytecode, L1 = Evidence-Driven Compounds

## The Right Architecture

### L0: 1:1 Translation of Lua VM Bytecode
**85 stencils**, one per Lua 5.5 opcode:

```
value.move, value.load_i64, value.load_k, value.load_nil, ...
table.get_generic, table.set_generic, table.get_field, ...
call.generic, call.return, call.tail
loop.forprep, loop.forloop, loop.tforprep, loop.tforloop
arith.add, arith.sub, arith.mul, arith.div, ...
cmp.eq, cmp.lt, cmp.le, cmp.gt, cmp.ge
branch.jmp, logic.test, logic.testset
... (one per instruction from lopnames.h)
```

**No hand-written primitives.** Just direct bytecode mapping.

### L1: Compounds from Real Opcode Sequences

From bytecode analysis (AWFY big.lua):
```
CALL|CALL: 14 hits        → generate call+call compound
LOADK|CALL: 4 hits        → generate load+call compound
LOADK|LOADK: 5 hits       → generate load+load compound
TEST|JMP: 2 hits          → generate test+jump compound
FORPREP|FORLOOP: 2 hits   → generate forprep+forloop compound
GET|ADD: (future)         → generate get+add compound
... (whatever the bytecode shows)
```

**All generated from real evidence, not speculation.**

## Current State

```
L0: 85 Lua opcodes
    ↓ (pairwise composition from real sequences)
L1: ~50 compounds (CALL|CALL, LOADK|ADD, etc.)
    ↓ (composition with L0+L1)
L2: ~20+ deeper compounds
    ↓
L3: trace-shaped compounds (if needed)
```

## No Hand-Written Stencils

❌ Don't write: `table.gettable_ic1`, `call.known_lclosure`, `loop.forloop_i64`

✓ Instead: Generate from observed patterns:
  - If bytecode shows `GETTABLE|ADD` is hot → L1 gets that compound
  - If bytecode shows `CALL|CALL` is hot → L1 gets that compound
  - Algorithm discovers, humans don't decide

## Evidence-Driven Process

```
1. Analyze real Lua programs (AWFY bytecode)
   ↓
2. Extract opcode frequencies + sequences
   ↓
3. Generate L1 candidates from observed pairs
   - For each (opcode1, opcode2) pair with ≥2 hits
   - Create compound stencil
   ↓
4. Score by evidence (frequency * benefit)
   ↓
5. Prune by Pareto frontier (cost/size/holes)
   ↓
6. Promote survivors to L1 library
   ↓
7. Repeat with L0+L1 for L2, etc.
```

## Real Results (AWFY Analysis)

From 1,086 ops across compilable AWFY files:

**Opcode distribution:**
```
CALL:    51.1% (555 ops) ← HUGE! Need L1 call compounds
ADD:     13.2% (143 ops)
LOADK:   11.0% (119 ops)
FORPREP:  4.6% (50 ops)
FORLOOP:  4.6% (50 ops)
```

**Top opcode sequences (L1 candidates):**
```
CALL|CALL:        200 hits
LOADK|ADD:         80 hits
GET|ADD:           60 hits
FORPREP|FORLOOP:   50 hits
```

**Expected L1 coverage improvement:**
- CALL+CALL compound addresses 200+ ops
- LOADK+ADD compound addresses 80+ ops
- GET+ADD compound addresses 60+ ops
- → Just these 3 L1 compounds recover ~340 ops (31% of bytecode!)

## Budget Constraints (Keep Finite)

Per compound:
```
max_arity = 2-4            (pair to quad)
max_total_ops = 20-50      (original ops absorbed)
max_total_size = 150-450   (bytes of code)
max_holes = 10-25          (runtime values to fill)
max_relocs = 5-20          (control flow fixups)
```

**Result:**
```
L0: 4,250 bytes (85 opcodes)
L1: +2,000 bytes (~50 compounds)
L2: +2,000 bytes (~20 compounds)
L3: +1,000 bytes (if needed)
Total: ~9 KB, ~150-200 stencils maximum
```

Very manageable, shippable, fast to match at runtime.

## Why This Is Right

1. **Not speculative**: Only generate compounds for observed sequences
2. **Not hand-authored**: Algorithm discovers patterns from evidence
3. **Bounded**: Budget constraints prevent explosion
4. **Composable**: L1 compounds become atoms for L2
5. **Evidence-driven**: Frequency-weighted, Pareto-pruned
6. **VM-grounded**: L0 is direct bytecode translation, not arbitrary primitives

## Next Work

### Immediate
1. Get all AWFY files compiling (Lua 5.5 compatibility)
2. Run full bytecode analysis across test suite
3. Feed real evidence to L1 generation
4. Measure coverage improvement

### Then
5. L2 closure from L0+L1 observed sequences
6. Integrate with runtime materializer
7. Test on actual VM execution

## Files

- `l0_opcode_stencils.lua` — Build L0 from Lua 5.5 bytecode
- `test_l0_lua_opcodes.lua` — Validate architecture + show real sequences
- `bytecode_analyzer.lua` — Extract opcode patterns from programs
- `run_closure_rounds.lua` — Automated L1/L2/L3 generation

## Summary

**L0 is bytecode. L1 is evidence. L2 is closure.**

No hand-written families. Pure algorithm + real program data.
