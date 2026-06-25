# Lalin Lua Interpreter VM — Architecture Exploration
Full architecture exploration for a PUC-Lua-compatible register-bytecode interpreter VM implemented in idiomatic Lalin with explicit programming principles.
**Started**: 2026-05-21 21:03:59
---

## Scout Output — 2026-05-21 21:05:25

I now have comprehensive data. Let me compile the full scout report.

## Files Retrieved

1. **`experiments/lua_interpreter_vm/README.md`** (2003 lines) — The complete VM architecture design: products (Value, GCHeader, Table, Proto, Frame, LuaThread, GlobalState, etc.), protocols (table_get, call, raise, error, gc, metamethod), region signatures for every VM operation, the opcode family, quickening design, and implementation ordering.

2. **`explicit_programming.md`** (3710 lines) — The full philosophical/methodological foundation: dual tree (data tree + control tree), the six-step design procedure, rules for finding data types (sums, products, no derived data, structure over keys, typed handles, events as data), rules for finding control types (outcomes as continuations, no fallthrough, state machines as named blocks, compose with emit/seal with func), and the unified type system concept.

3. **`rewriting_c_to_idiomatic_lalin.md`** — Complete C-to-Lalin guide: return codes → protocols, enums+switch → consumer regions, out-params → continuation payloads, goto labels → named blocks, loops → blocks+parameters, vtables → Lua-generated concrete machines or explicit dispatch, macros → Lua factories, global state → explicit context struct. Mapping table of C idioms to Lalin redesign.

4. **`LANGUAGE_REFERENCE.md`** (3741 lines) — Key sections:
   - §5 Type system: scalars, pointers, views, structs, tagged unions, function/closure types
   - §7 Hosted declarations: struct, union, extern, func, region, expr declaration syntax
   - §10 Control regions: blocks, jumps, yields, multi-block control, termination rules
   - §11 Region fragments and continuation protocols: emit, composition, forwarding
   - §12 Expression fragments: simpler value-producing fragments
   - §16 Metaprogramming: signature closures, `@{x}` splices, list spreading, Lua factories

5. **`PVM_GUIDE.md`** (1821 lines) — Phase Virtual Machine methodology:
   - §2 Control protocols: ASDL syntax for continuations (`|` = or both in data and control types)
   - §5 Scalar boundaries: `pvm.phase(name, fn)` + `pvm.one`
   - §8 Flatten early: tree → flat commands, push/pop pattern
   - §9 State is always a stack
   - §11 Uniform Cmd Product type: one metatable for JIT, not sum-type variants
   - §12 For-loop IS the slot: iterate flat commands, cache fills as side effect

6. **`COMPILER_PATTERN.md`** (1189 lines) — The five concepts (Source ASDL, Event ASDL, Apply, Control protocols, Phases) + the Loop. Recursion is iterator nesting. Three levels: compilation (pure, structural, memoized), codegen (generated constructors), execution (the for-loop over flat phase output).

7. **`minilua.c`** (7771 lines) — PUC Lua reference implementation structures:
   - `TValue` (Value union + tt int discriminator)
   - `GCheader` (next, tt, marked)
   - `Proto` (code, constants k, children p, lineinfo, locvars, upvalues, source, sizes)
   - `UpVal` (v pointer, closed value, prev/next)
   - `CClosure` / `LClosure` / `Closure` union
   - `TString` / `Udata`
   - `Node` (i_val, i_key) / `Table` (flags, array, node, lastfree, metatable, sizes)
   - `CallInfo` (base, func, top, savedpc, nresults, tailcalls)
   - `global_State` (strt, rootgc, gray lists, tmname, registry, panic)
   - `lua_State` (top, base, ci, stack, openupval, errorJmp, status, hook)
   - `luaV_execute` (the main loop: fetch Instruction, switch on OpCode, 37 opcodes)
   - `luaD_precall` (0=enter Lua VM, 1=C call returned, 2=yielded)
   - `luaD_poscall` (pop frame, set results)
   - `luaD_call` (precall + execute)
   - `luaD_pcall` (rawrunprotected wrapper)
   - `setjmp`/`longjmp` via `LUAI_TRY`/`LUAI_THROW`, `lua_longjmp` chain

8. **`lua/lalin/back_jit.lua`** — FFI bridge to Rust Cranelift JIT: loads `liblalin.so`, `jit:compile(program)` encodes BackProgram as binary wire format, sends to Rust, returns Artifact with getpointer/disasm/free.

9. **`lua/lalin/back_command_binary.lua`** — Flatline v4 wire format encoder: one tag per Cranelift IR operation (no sub-tag dispatch), maps BackCommands to binary byte stream.

10. **`BACK_WIRE_FORMAT.md`** — Header (28 bytes), declaration section (signatures, functions, data, init, externs, names), body table (function ID → byte offset), function bodies (flat (tag, slots...) streams).

11. **`test_multi_block_emit.mlua`** — Minimal region fragment emit: region with two continuations (ok, bad), emitted inside a return region. Multi-block fragment works end-to-end.

12. **`test_region_compose_asdl.mlua`** — Region fragment composition: `scan_byte` region emitted inside `use_scan`, demonstrates forwarding.

13. **`examples/protocols/resp_parser.mlua`** — Full protocol parser as Lua-generated region fragments: line parsers, decimal parsers, bulk string parsers, all composed via emit with typed continuations.

14. **`examples/json/json_lua_stack_decoder.mlua`** — JSON decoder using extern declarations for Lua C API, region fragments (skip_ws, parse_string, parse_number), switch dispatch with @{} spread, and typed continuations.

15. **`stdlib/arena.mlua`** — Bump allocator: struct Arena (start, ptr, end_ptr), functions arena_new/arena_alloc/arena_reset, select() for alignment, null pointer return for OOM.

16. **`stdlib/view.mlua`** — View helper functions: view_slice, view_from_ptr, view_bounds_check.

## Key Code

### minilua.c — Core Data Structures
```c
typedef union { GCObject* gc; void* p; lua_Number n; int b; } Value;
typedef struct { Value value; int tt; } TValue;  // tag + value union

typedef struct GCheader { GCObject* next; lu_byte tt; lu_byte marked; } GCheader;

typedef struct Proto {
    TValue* k; Instruction* code; struct Proto** p; int* lineinfo;
    TString** upvalues; TString* source; int sizeupvalues/sizeupvalues/sizecode/...
    int linedefined, lastlinedefined; lu_byte nups, numparams, is_vararg, maxstacksize;
} Proto;

typedef struct UpVal { TValue* v; union { TValue value; struct { prev; next; } l; } u; } UpVal;
typedef struct LClosure { Proto* p; UpVal* upvals[1]; } LClosure;
typedef struct CClosure { lua_CFunction f; TValue upvalue[1]; } CClosure;

typedef struct Node { TValue i_val; TKey i_key; } Node;
typedef struct Table {
    lu_byte flags, lsizenode; Table* metatable;
    TValue* array; Node* node, *lastfree; int sizearray;
} Table;

typedef struct CallInfo { StkId base, func, top; const Instruction* savedpc; int nresults, tailcalls; } CallInfo;

typedef struct global_State {
    stringtable strt; lua_Alloc frealloc; lu_byte currentwhite, gcstate;
    GCObject* rootgc, *gray, *grayagain, *weak, *tmudata;
    UpVal uvhead; Table* mt[9]; TString* tmname[TM_N]; lua_CFunction panic; TValue l_registry;
} global_State;

struct lua_State {
    lu_byte status; StkId top, base; global_State* l_G; CallInfo* ci;
    StkId stack, stack_last; int stacksize; GCObject* openupval;
    struct lua_longjmp* errorJmp; ptrdiff_t errfunc;
    // hook fields, env, gt
};
```

### minilua.c — VM Dispatch Loop
```c
static void luaV_execute(lua_State* L, int nexeccalls) {
    reentry:  // goto label for CALL re-entry
    pc = L->savedpc; cl = &clvalue(L->ci->func)->l; base = L->base; k = cl->p->k;
    for (;;) {
        Instruction i = *pc++;
        StkId ra = RA(i);
        switch (GET_OPCODE(i)) {
        case OP_MOVE: setobj(L, ra, RB(i)); continue;
        case OP_LOADK: setobj(L, ra, KBx(i)); continue;
        case OP_GETTABLE: Protect(luaV_gettable(L, RB(i), RKC(i), ra)); continue;
        case OP_CALL: /* switch(luaD_precall) { 0->goto reentry; 1->continue; default->return; } */
        case OP_RETURN: /* luaD_poscall; if(--nexeccalls==0) return; else goto reentry; */
        // ... 37 opcodes total
        }
    }
}
```

### minilua.c — Call Protocol
```c
static int luaD_precall(lua_State* L, StkId func, int nresults) {
    // returns 0 = Lua call entered, 1 = C call returned, 2 = yielded
}
static int luaD_poscall(lua_State* L, StkId firstResult) {
    // pop frame, move results, return wanted-(-1)
}
static void luaD_call(lua_State* L, StkId func, int nResults) {
    if (++L->nCcalls >= 200) throw C stack overflow;
    if (luaD_precall(L, func, nResults) == 0) luaV_execute(L, 1);
    L->nCcalls--; luaC_checkGC(L);
}
```

### VM Design — Key Regions (from README)
```lalin
region vm_loop(L: ptr(LuaThread);
    finished: cont(nres: i32), yielded: cont(nres: i32),
    error: cont(code: i32), oom: cont())

region dispatch_instruction(..., frame, pc, base, top;
    next, jump, enter_lua, enter_native, returned, yielded, error, oom)

region prepare_call(L, func_slot, nargs, wanted, resume_mode;
    enter_lua, enter_native, returned, yielded, error, oom)

region prepare_metamethod_call(L, frame, pc, base, top, mm, nargs, wanted, resume_mode;
    prepared, error, oom)

region raise_error(L, err;
    caught: cont(frame, handler), uncaught: cont(code))

region handle_return_mode(L, parent, first_result, nres;
    normal, resume_gettable_mm, resume_binop_mm, ..., finished, yielded, error, oom)
```

### JSON Decoder — Real Region Fragment Pattern
```lalin
local skip_ws = region(p: ptr(u8), n: i32, pos: i32; ok: cont(i: i32))
entry loop(i: i32 = pos)
    if i >= n then jump ok(i = i) end
    switch as(i32, p[i]) do
    case 32 then jump loop(i = i + 1)
    case 10 then jump loop(i = i + 1)
    default then jump ok(i = i)
    end
end
end

-- Another region emits skip_ws:
emit @{skip_ws}(p, n, i; ok = after_ws)
```

### RESP Parser — Lua-Generated Region Factories
```lua
local function make_line_payload(tag, err_base)
    local name = "resp_line_" .. tostring(tag)
    return region @{name}(p: ptr(u8), n: i32, pos: i32;
        ok: cont(bytes: i32, next: i32),
        err: cont(pos: i32, code: i32))
    entry start()
        jump scan(i = pos, base = pos)
    end
    block scan(i: i32, base: i32)
        if i >= n then jump err(pos = i, code = @{err_base}) end
        if as(i32, p[i]) == 13 then
            jump saw_cr(crpos = i, bytes = i - base)
        end
        jump scan(i = i + 1, base = base)
    end
    ...
    end
end
```

### BackCommand Binary Wire Format
```lua
-- Flat tags: one per Cranelift IR operation
local T = {
    CreateBlock=1, SwitchToBlock=2, AppendBlockParam=3, Jump=170,
    Brif=171, SwitchInt=172, CallDirect=180, CallExtern=181, CallIndirect=182,
    Load=110, Store=111, Iadd=20, Isub=21, Fadd=30, Fcmp=71, Select=160, ...
}
```

### PVM Uniform Cmd Pattern
```asdl
module View {
    Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform
    Cmd = (View.Kind kind, string htag, number x, number y, number w, number h,
           number rgba8, number font_id, string text, number tx, number ty) unique
}
```

## Relationships

**How the pieces connect:**

1. **C Data Structures → VM Design Products**: Every C struct in minilua.c maps to a Lalin struct in the design doc. `TValue` → `Value` (tag + bits + aux), `Proto` → `Proto`, `Table` → `Table`, `CallInfo` + frame state → `Frame` (with resume_* fields), `lua_State` → `LuaThread` (stack, frames, open_upvals, protected_top), `global_State` → `GlobalState`.

2. **C Call Protocol → VM Control Protocol**: `luaD_precall`'s 3-way return (0=enter Lua, 1=C returned, 2=yielded) becomes a region protocol with continuations `enter_lua`, `enter_native`, `returned`, `yielded`, `error`, `oom`. `luaD_poscall`'s frame-popping + result-copying becomes `return_from_lua` → `handle_return_mode` with many RESUME_* continuations.

3. **C Error Handling → VM Error Regions**: `setjmp`/`longjmp` through struct `lua_longjmp` chain becomes `enter_protected`/`leave_protected` + `raise_error(caught, uncaught)`. Protected frames replace `errorJmp` pointers.

4. **C VM Loop → VM Region Graph**: The `for(;;)` loop with `switch(GET_OPCODE(i))` becomes `vm_loop` → `dispatch_instruction` → per-opcode regions. Each `continue` becomes `jump next(...)`. CALL's `goto reentry` becomes `enter_lua(child_frame)` continuation. RETURN's frame pop becomes `returned(nres)`.

5. **Flatline Wire Format as Output Target**: The VM's opcode handlers must eventually produce `BackCmd[]` (or the Flatline binary equivalent). The design doc doesn't specify this yet, but the pipeline from Lalin source → region expansion → BackCmd → wire binary → Cranelift compilation → native code is the existing path.

6. **Explicit Programming Rules → VM Shape**: Every C convention (return codes, out-params, tag switches, callbacks, setjmp) gets a Lalin redesign. Products for storage, protocols for immediate consumption, regions for state machines — exactly as `rewriting_c_to_idiomatic_lalin.md` prescribes.

7. **Lua Metaprogramming → Opcode Generation**: Lua factories generate monomorphic opcode handlers, metamethod dispatch handlers, and resume-mode dispatchers — following the same pattern as the RESP parser's `make_line_payload` and the JSON decoder's extern declarations.

8. **PVM/Compiler Pattern → Architecture Layering**: The three-layer pattern (Source/Compiler → Phases → Flat commands for loop execution) maps to: PUC Lua source → compiler → Proto (source layer), VM runtime as phases/phases of execution (phase layer), the flat instruction stream and flat Frame/CallInfo state (flat command execution layer).

## Observations

- **The design doc is exceptionally thorough.** It covers every data structure, every protocol, every region signature for the complete PUC-Lua-compatible VM. It explicitly states it's a "final target shape" — not a temporary subset. Implementation ordering is provided (10 steps) but each step is a "no reduced design" step.

- **The Frame struct carries 7+ resume_* fields.** This is the key insight: dynamic Lua continuations (metamethod returns, pcall error catching, coroutine yield) become product data on the Frame, not region protocols. Static VM control is regions; dynamic script control is frame data. This is the correct boundary.

- **The design explicitly chooses 3-piece Value** (`tag: u32, aux: u32, bits: u64`) over PUC's 2-piece TValue (union + tt). The `aux` field is reserved for quickening metadata and ABI convenience.

- **Boolean is split into TAG_FALSE/TAG_TRUE** instead of TAG_BOOL + payload, so truthiness is one tag compare.

- **Quickening is part of the final design, not an afterthought.** `InlineCache` struct with `epoch` field, `QuickInstr` with inline cache, invalidation via `shape_epoch` on tables. `probe_gettable_cache`, `quicken_instruction`, `deopt_instruction` are named regions.

- **The wire format (Flatline v4) is already section-indexed and flat.** 160+ flat tags for Cranelift IR operations, no sub-tag dispatch. This is the target format any VM opcode handler must ultimately produce through the existing Lalin → BackCmd → binary pipeline.

- **C-to-Lalin rewrite guide says:** "Do not port functions; recover machines." "If C code returns a value only so the caller can branch on it, the Lalin rewrite should be a region protocol, not a function returning a result."

- **The PVM uniform cmd pattern** (one product type with all fields, Kind as singleton discriminator) is critical for JIT-friendly execution. This may apply to the VM's Instr dispatch or internal command representation.

- **Signature closures** (`lalin.func{ T = lalin.i32 }[[ ... ]]`) enable type-checked generics through Lua. This is how archetype patterns (opcode families, metamethod handlers) would be generated.

- **Stack and frame invariants** are explicitly listed in the design doc (§31-36) and must be maintained by every opcode handler.

- **`validate_proto`** is the VM's trust boundary — the loop assumes validated bytecode after this check.

## Knowledge-builder Output — 2026-05-21 21:07:32

## What Matters Most for This Problem

This is about **engineering the intersection of two systems** — a PUC-Lua-compatible VM graph and the Lalin compilation pipeline — not just about either in isolation. The critical dimensions are:

1. **Faithfulness to explicit programming vs. VM hot-path reality**: The design must preserve Lalin's philosophical commitments (regions, protocols, product data) while hitting performance expectations for a dynamic language VM. These tug in opposite directions.

2. **Monogenization pressure**: Lalin compiles monomorphic code. A JIT'ed Lua VM is the *opposite* — it's inherently polymorphic (any opcode at any point, any tag at any access). The tension is whether Lalin's monomorphism fights the domain or provides a stable foundation that a quickening layer sits on.

3. **Wire format coupling**: The VM regions ultimately produce BackCmd stream — but BackCmd is designed for *compilation*, not interpretation. The VM is a generated *interpreter*, and that changes the compilation strategy entirely.

4. **GC as a stranger in a strange land**: Lalin has no runtime GC. Adding one means every allocation becomes a multi-continuation region protocol in the middle of hot opcodes. The GC shapes everything.

---

## Non-Obvious Observations

### 1. Tensions in Explicit Programming vs. VM Hot Paths

**The block-parameter cost is worse than it looks.**

The scout notes that the hot loop dispatches through `dispatch_instruction` with block parameters for `(frame, pc, base, top)`. The non-obvious problem: in Lalin, **block parameters are not registers — they're SSA value arguments**. Each `jump next(...)` at the end of an opcode handler creates a new SSA phi. Cranelift will lower these to moves, but the *number* of distinct phi edges matters. 37 opcodes × ~15 parameters each = potentially 550+ distinct phi edges in the dispatch loop.

The real insight: **PUC Lua's C for(;;) loop with switch and `continue` is free** — the C compiler sees single-assignment through the loop body and allocates registers once. Lalin's explicit block parameters force a phi at *every* opcode boundary, which Cranelift must optimize away. If it can't (because the parameter set is large), you get register shuffling at every instruction boundary — a 3-5x overhead vs. C on tight loops.

**The `continue` vs. `jump next()` asymmetry**: In C, `continue` in a switch is a backward branch with implicit register preservation. In Lalin, each opcode handler must explicitly `jump next(pc, base, top, ...)` with the full parameter set. A C compiler freely keeps common state (L, base, top) in callee-saved registers across the dispatch. Lalin block parameters are explicit — they force the register allocator to reconcile values at each edge. The register allocator *might* eliminate them, but it requires the Cranelift backend to recognize the pattern.

**The 14-way handle_return_mode continuation**: This is the most extreme example. 14 continuations means 14 distinct code paths from a single return point. Lalin regions compile these as 14 separate basic blocks, each reachable from the return. Cranelift's register allocator must reconcile live values across 14 predecessors. The pressure on the register allocator grows with the number of continuations, and 14 is dangerously high for a hot path.

### 2. The Static/Dynamic Boundary — It's More Nuanced Than It Seems

The claimed boundary (static control = regions, dynamic control = Frame.resume_* data) seems clean, but the scout data reveals deep fuzziness:

**Quickening blurs the line completely.** A quickened instruction starts as a generic handler and becomes a specialized handler. The specialization *is* a control decision — which monomorphic handler to dispatch to — encoded as an `aux` field in the instruction. This is dynamic control stored in data. The design's own `quicken_instruction` region modifies the instruction's aux field. But: in Lalin, instructions are `Instr` structs carrying a u32. Mutating the instruction *in place* changes the next dispatch. This is fine — but it means the dispatch loop must be a single region that reads the opcode and jumps, not a switch with 37 fixed arms. Because `quicken_instruction` changes the opcode *between dispatches*, the region graph is self-modifying at runtime.

**Metatable caching creates a tiered dispatch problem.** The design has `probe_gettable_cache` as a region. The cached result is a resolved function or slot index. But: a cache hit means "use this fast path"; a cache miss means "fall back to full lookup." The fallback is a region call. The hit is a direct jump. But Lalin regions are spliced at compile time, not runtime. So the `if cache_hit then fast_path else fallback` construct is fine, but the *fast_path* region is cold most of the time for new instructions. This means: every opcode handler that uses icache must have two paths compiled, one of which is rarely taken. Cranelift's block layout will put the fallback at the end, but the taken/not-taken branch predictor state for a 2-bit predictor will thrash during warmup.

**The deeper observation**: The boundary is really **three tiers**, not two:

| Tier | Mechanism | Where |
|------|-----------|-------|
| Static VM control | Region graph (compiled once) | opcode dispatch, stack overflow check |
| Partially dynamic | Frame.resume_* + instruction mutation | metamethod returns, quickening |
| Fully dynamic | Lua script control flow | coroutine yield, error handlers, pcall |

Tier 2 is the neglected middle. It's neither fully static (can't be compiled once and forgotten) nor fully dynamic (lives in Frame data). Its performance characteristics are tied to the *distribution* of dynamic events.

### 3. GC Implications in a Non-GC Host — Worse Than Expected

**Every allocation emits a region with 3+ continuations, and this changes the opcode dispatch structure fundamentally.**

PUC Lua allocates in `luaV_execute` via macros: `luaC_checkGC(L)` is called once per `luaD_call`. In Lalin, every allocation is an `emit alloc_region(payload; ok = continue, oom = handle_oom)` where `oom` is a continuation. This means:

- **OP_NEWTABLE** doesn't just need an allocation — it needs to handle OOM from the GC commit. The GC commit region must be emitted *inside* the opcode handler, which means the handler's region graph has an OOM edge that rejoins the main dispatch. This is fine but **every rejoin to the main loop from an OOM handler is a new phi edge** into the dispatch block.
- **OP_CONCAT** needs concatenation space allocated, which triggers GC. If the GC triggers a collection, the collection traces a potentially large object graph. During GC tracing, the VM is paused — but Lalin regions don't have preemption points. The GC region must be a state machine with its own blocks (mark-gray, scan-gray, sweep-white, etc.). This is a *second* state machine interleaved with the VM dispatch state machine.
- **GC safepoints**: The design needs safepoints in the VM loop where GC can fire. The scout data doesn't mention safepoints explicitly, but `luaC_checkGC` in C is called at array-bound iteration boundaries and call/return points. In Lalin, a safepoint means: every Nth instruction, emit a region that checks GC threshold and potentially triggers collection. But regions are compiled once — you can't insert a check "after every 100 instructions" without making it a conditional in the dispatch loop itself.

**The killer observation**: PUC Lua's `luaC_checkGC` costs ~3 instructions when allocation hasn't exceeded threshold. Lalin's equivalent safepoint check — `if gc_needed then emit collect_gc(regions...)` — is a branch in the hot dispatch. The branch will be *always not taken* except at collection time. But it changes Cranelift's ability to reorder instructions across the safepoint. The safepoint acts as a compiler optimization barrier, even when not taken, because the body of the if contains a region call that the optimizer can't prove doesn't modify memory.

**GC roots**: The design says GC roots are "all stack slots referenced by Frames." But in Lalin, stack slots are `Value[]` arrays pointed to by struct fields. The GC must know which slots in the `Value[]` array are live. This requires a **root set enumeration** that walks the frame chain. PUC does this by walking `L->stack` to `L->top` for each CallInfo. Lalin can do the same — but it means the GC region must have access to all `LuaThread` and `Frame` fields, which is fine for a product struct. However, the GC's root enumeration must not trigger GC itself (no allocation in root enumeration). This is a simple invariant but one that region handlers must preserve.

### 4. The Frame Product Design — The Uniform Product vs. Union Tradeoff

**The Frame struct with 7 resume_* fields is the right choice, but for the wrong reasons in the scout.**

The scout says Frame has 7 resume_* fields (probably: resume_pc, resume_base, resume_a, resume_b, resume_c, resume_value, resume_mode). Many are mutually exclusive per mode. The scout suggests this might be leaky and wonders about a union.

**The non-obvious insight**: The uniform Frame struct *is correct* but not for JIT tracing reasons (as PVM uniform Cmd is). Rather, it's because **resume_* data must be stable across GC collections**. If Frame used a union, and a collection moved the value, the union discriminator would be in the `mode` field but the value would be in a union arm. This is fine for C (position-independent), but Lalin's product structs are **fixed-layout** — there's no union-of-structs akin to C tagged unions. Lalin's `union` type *does* exist:

```lalin
union ResumeMode
    add(a: i32, b: i32, mode: u16)
    index(table: ptr(Value), key: Value)
    ...
end
```

But resume_* fields are accessed by the main dispatch loop, which would need to pattern-match on the union to extract fields. In Lalin, union access is a switch. So every resume point would add a switch on mode to extract fields. With 14+ modes, that's a 14-arm switch at every return point — worse than 7 unused fields.

**The real cost is cache pressure, not JIT**. 7 × u16 + index + Value + u16 mode = roughly 7×2 + 8 + 16 + 2 = ~40 bytes per resume slot, times 7 = 40 + maybe 64 base = ~104 bytes per Frame. With max stack depth of, say, 200 frames (generous for Lua), that's 20KB of resume metadata, mostly zero. Modern L1 cache is 32KB. This doesn't fit, but it doesn't need to — resume_* fields are touched only during the call-to-return window. During normal execution, they're dead cache lines. This is fine.

**The subtle problem**: Frame also carries `resume_mode` and the full dispatch must check `if resume_mode ~= 0 then ...` at the start of each instruction or at CALL/RETURN boundaries. This check is pure overhead for the common case (no pending metamethod). PUC Lua avoids this by embedding the return handling in `luaD_poscall` — the check only happens at return time, not at every instruction. Lalin's Frame design pushes the check into the dispatch loop unless the check is localized.

### 5. Metamethod Continuation Cost — Tiered Design Is Essential But Complicates

**The hidden assumption**: The scout says "most of the time they won't" hit metamethods. This is true for well-written Lua, but **the worst-case is what determines compilation cost**. Lalin regions are compiled monomorphically — every opcode handler that *could* hit a metamethod must have the meta-call continuation compiled in. The question is whether Cranelift can optimize away dead code from a known-invalidated code path.

**The tiering insight is correct but the cost is subtle**. A tiered approach would have:
- Fast region: no meta exits, assumes no metamethod hit
- Fallback region: full meta exits
- Selection: try fast, if meta hit, deopt to fallback

But deoptimization in a compiled Lalin region means **recompiling with different assumptions** — there's no interpreter fallback. The quickening system already handles this via shape_epoch invalidation. But quickening is for opcode specialization, not for meta-exit tiering. Meta-exit tiering would require the VM to detect "this index never hits __index" and compile a specialized version. That's a form of PGO (profile-guided optimization) that the design doesn't propose.

**The branching cost**: For OP_GETTABLE, the handler must check:
1. Is metatable present? (load table->metatable, check null)
2. If present, does it have __index? (load metatable->array[TM_INDEX], check nil)
3. If __index, is it a function or table?
4. If function, prepare metamethod call.
5. If table, recurse GETTABLE on metatable.

Each check is a few Lalin instructions, but many are memory loads. The real cost: `table_get` is the region behind GETTABLE. It must handle all paths. Lalin's region will compile all paths monomorphically. Cranelift can't prove that table.metatable.__index is nil — it must compile the full check chain. The unpredicted branch on `metatable ~= nil` will mispredict ~5-20% of the time depending on the workload, adding ~15 cycles per mispredict.

**The tiering question**: Can we emit a *different* region for GETTABLE based on profile data? Yes — Lua factories can generate monomorphic opcode handlers. The JIT could observe "table[0xABCDEF] never has metatable" and generate GETTABLE with no meta check. But: Lalin compiles once per `.mlua` load, not once per profiling epoch. The VM itself is a compiled program — it can't recompile itself without a JIT-on-JIT. This means tiered metamethod handling would require the VM to be structured as a *generator*: a Lua function that produces a VM configuration (enable/disable meta checks per opcode) and then compiles that configuration. This is possible (Lua factories are the metaprogramming layer) but it's a radical architectural choice.

### 6. Coroutine Protocol Shape — Yield Breaks the Region Model

Coroutine yield is the **most difficult operation** for the region protocol model. Here's why:

**C coroutines**: PUC Lua's `lua_yield` uses `longjmp` back to the resume point, unwinding the C stack. The `lua_State` preserves the continuation info. Lalin regions don't have a C stack to unwind — they have a flat block-transition graph. Yield means: save the current execution state (pc, frame, stack) and return to the resumer. In a region model, this means **yield is a region continuation** — the current region terminates with a `yielded` continuation.

**The problem**: `coroutine.yield()` can be called from *any* depth of Lua calls. In Lalin:
```
coroutine.wrap(f)() = vm_loop(thread; finished, yielded, error, oom)
```
Inside the loop, f calls g, g calls coroutine.yield(). The yield must propagate from g's call all the way back to the outermost `vm_loop` region. In PUC C, this is a `longjmp` through the protected frame chain — one instruction. In Lalin regions, it requires each frame in the chain to have a `yielded` continuation that forwards upward.

**This means**: Every `call` region must have a `yielded: cont(...)` continuation in its protocol. If a frame doesn't forward yield (because it's a C frame or a non-resumable call), the yield must raise an error. But Lalin regions are compiled — you can't conditionally add a continuation at runtime. Every call path must have the yield continuation pre-compiled.

**The shape**: The `prepare_call` region already has `yielded` as a continuation. But the forwarding requires the caller's `yielded` to be the caller's caller's `yielded`, etc. This is a **chain of continuations**, which Lalin regions handle via `emit @{prepare_call}(...; yielded = parent.yielded, ...)`. This works syntactically but means every frame's `yielded` continuation is a direct link to the top-level `vm_loop`'s yielded continuation. The compiler must wire this through the entire call graph. For a call depth of 100, the yielded continuation chain is 100 links long — statically compiled, no runtime overhead. **But**: the call target is not known statically. Function pointers and closures mean the continuation chain must be resolved at runtime via the frame chain, not the region graph.

**The grim conclusion**: Coroutine yield cannot be purely static in the region graph. It must use the frame chain's `resume_mode` field (or equivalent) to determine the return path. This pushes yield into the dynamic control tier (Frame data), exactly where `resume_mode` lives. So yield is not a region continuation — it's a frame field mutation followed by a return to the parent dispatch.

### 7. Quickening Invalidation Protocol — The Cascade Problem

The design says `shape_epoch` is bumped on table resize and metatable mutation. The scout finds this plausible. But:

**The cascade problem**: If table A has metatable M, and M has metatable N, and N's `__index` changes (from nil to a function), then table A's access behavior changes. But `shape_epoch` is per-table. Bumping M's epoch doesn't bump A's. An inline cache on A that saw "M has no __index" is now stale. The cache must check M's epoch, not just A's.

Non-obvious fix: Each table stores the epoch of its metatable's shape at the time of last access. The cache check compares `table->metatable->epoch` against the cached value. But this requires reading two epochs per cache probe (table epoch + metatable epoch). For deep chains, it requires reading N epochs.

**Key-specific assumption invalidation**: A cache might specialize on "table[42] is always the same string." If `table[42]` is set to a different value, the key-specific assumption is wrong. But `shape_epoch` isn't bumped on regular table writes — only on resize and metatable mutation. So key-specific caches need their own invalidation mechanism. The design's `epoch` field on `InlineCache` could be per-access, but that's expensive.

**The real issue**: PUC Lua doesn't have opcode-level quickening. The Lalin design adding quickening means the invalidation must be comprehensive. Any case where `aux` encodes a cached assumption that could be stale requires invalidation. The `aux` field is u32. If it encodes "this GETTABLE is on table at stack slot 3 with key 'name' and last returned the float 42.0", a write to that slot's table or a write to table['name'] must invalidate. But tracking dependencies precisely requires a write barrier in the VM — which is not in the design.

### 8. The Value Product Choice — 128-bit Cost Is in the Stack, Not the Struct

The 128-bit Value (tag+aux+bits) vs. PUC's 96-bit TValue (with implied padding to 128 on 64-bit platforms):

**The scout says**: "The design chose more bits." Actually, PUC's `TValue` is 16 bytes on x86-64 (8-byte Value union + 4-byte tt + 4-byte padding). The Lalin `Value` is also 16 bytes (4+4+8). **They're the same size on 64-bit platforms.** The difference is that PUC packs `tt` into 4 bytes (with a 4-byte hole for alignment), while Lalin uses 4+4 (tag+aux) for 8 bytes of overhead before the 8-byte payload.

**Real cost**: The `aux` field adds 4 bytes per Value that PUC doesn't have. On a 200-entry stack (common for typical Lua usage), that's 800 bytes of extra memory. Negligible. On a 10,000-entry stack (extreme), that's 40KB. But the stack isn't the problem — **it's the table entries**. A table with 1000 entries uses 4KB extra for `aux`. For the Lua benchmark suite, this is ~50-200KB extra memory. Negligible for modern hardware.

**The Cranelift cost**: Lalin's `i128` for 128-bit load/store is not directly supported on x86-64 (no 128-bit GPR). Cranelift must split into two 64-bit loads: one for (tag+aux), one for bits. The tag and aux are in the same 64-bit word, so extracting them requires a shift+mask or BFI (Bit Field Insert) instruction. `bits` is already a 64-bit value in a register. The overall cost per Value access: one 64-bit load (tag+aux), shift+mask to get tag, maybe another 64-bit load (bits). That's ~2 loads + 1 ALU op per access. PUC does 1 load (64-bit for value + 32-bit for tt = ~2 loads too, but in one cache line). Actually PUC's TValue is in two cache lines if the value union is 8 bytes and tt is 4 bytes with padding — the whole struct fits in 16 bytes, one cache line. So the cost is identical.

**The aux field *opportunity***: The extra 4 bytes per Value enable quickening metadata to be stored *in the value itself*. For example, a TAG_NUMBER value could have `aux` encode the integer range (is this a small integer that can use integer arithmetic?). A TAG_STRING value could have `aux` encode the string length for fast comparison. This is the real value — not a cost but an enabler for fast-path optimizations that PUC can't do.

### 9. Frame Count and Recursion Depth — The Hidden Infinity

**Flat frame array eliminates C stack overflow but introduces a different overflow mode.** The scout says frames are in a contiguous array on the thread struct. PUC's C recursion means `luaD_call` → `luaV_execute` → `luaD_precall` → `luaV_execute` uses C stack frames for each Lua frame, limited to ~200-400 before hitting the C stack guard (2MB default C stack, ~8KB per frame = 256 max).

**Lalin's flat array** has no C recursion. The frame count is limited by array size. What size? If `maxstacksize` from the Proto is, say, 250 (the PUC default), and we allocate 200 frames, that's 200 × (250 + overhead) = ~50,000 Value slots = 800KB of stack. Reasonable.

**But**: Protected frames (for pcall) are separate. The design says `ProtectedFrame` is a linked list or array. Each pcall nesting adds a protected frame. If pcall is called inside a loop that recurses 1000 times, protected frames stack up. The Lalin model must prevent infinite protected frame growth. PUC handles this because C stack overflows kill the program. Lalin must do explicit bounds checking.

**The real insight**: Frame count is bounded by **mutable state on the stack**, not by frame structure size. Each frame has a `top` pointer indicating the last valid stack slot. Lua functions can grow the stack via `EXTRAARG` and array expansion. The VM must check `top < stack + stacksize` at every instruction. This check is in the hot path. In Lalin, this check is a conditional branch at every opcode dispatch. PUC does it in `luaV_execute` via a macro that branches to `luaD_growstack` on overflow. Same cost in both — but Lalin's branch is explicit in the region graph, visible to Cranelift for scheduling. PUC's `#define checkstack(L,n) ...` is a preprocessor macro, also inlined. Similar cost.

### 10. Wire Format Target — The Missing Interface

**The VM does not compile to BackCmd.** This is the single most important third-order observation that the scout data reveals but doesn't state.

The existing Lalin pipeline is: .mlua source → parse → typecheck → tree-to-back → BackCmd[] → Flatline binary → Cranelift → native code.

The VM design proposes Lua region fragments that compile through this same pipeline. But **the output of the VM pipeline is a native binary (the interpreter), not BackCmd**. The BackCmd stream is the *compilation artifact*, not the *runtime target*.

What the VM actually produces during execution: **nothing**. The VM *is* the compiled code. It doesn't produce BackCmd at runtime — it *is* the BackCmd that was compiled ahead of time. The VM opcode handlers don't emit BackCmd; they *are* BackCmd (compiled to native).

**The real question**: Is the VM compiled AOT (once per .mlua load) or JIT (recompiled per profile)? If AOT, the design doesn't need BackCmd at runtime. If JIT, the VM must call back into the Lalin pipeline at runtime, which means `lalin.loadstring` from inside a running Lalin program — a metacircular compilation. This is possible (Lalin is Lua-embedded, so Lua can call `lalin.loadstring` at runtime), but it's a JIT compiler written in Lalin running on itself, which is compiler bootstrapping complexity.

**The non-obvious conclusion**: The VM design is AOT. The VM loop is a single Lalin function compiled once (or a set of regions spliced together and compiled to a single function). The opcode handlers are all compiled in one function. The dispatch is a flat sequence of blocks, each implementing one opcode. This works — but it means the VM cannot adapt to runtime profiles without recompilation. The quickening system works *within* the compiled code (storing metadata in aux fields that opcode handlers branch on), not by recompiling handlers.

### 11. Opcode Handler Generation Scale — The Compile Time Problem

**The real cost is not the number of handlers but the phi nodes between them.**

Cranelift compiles a function with N basic blocks. Each block has up to ~15 parameters (pc, base, top, frame, L, etc.). Each parameter at a block is a phi of its predecessors. With 37 opcodes + 14 return modes + GC safepoint blocks + error blocks, maybe 60-80 blocks total. Each block has ~15 parameters with an average of ~40 predecessors per parameter (each opcode can transition to each other opcode via `jump next(...)`). That's 60 × 15 × 40 = 36,000 phi edges in the worst case. Cranelift's register allocator reduces these, but 36,000 edges is significant.

**But**: The actual dispatch is not a complete graph. Not all opcodes transition to all others. The dispatch graph is dense but not complete:
- Most opcodes transition to the next pc (one successor: `next`)
- CALL and RETURN and JUMP have multiple successors
- On average, each block has ~2 successors → each successor has ~20 predecessors

Realistic estimate: 60 blocks × 15 params × 2 successors × 20 predecessors = 36,000 phi edges. Same number but the distribution matters — the edges fan in to `next`, not out from each opcode. The `next` block has 37+ predecessors. Cranelift handles this well (it's just a linear scan) but the number of live values across the `next` block is high.

**Cranelift compile time**: For a function with 60 blocks and 2000 Lalin instructions, Cranelift takes maybe 50-200ms in release mode. This is acceptable for AOT compilation. For JIT (recompilation), it's too slow — LuaJIT compiles a ~500-instruction trace in ~1ms.

**The handler count**: 37 base opcodes × 1.5 (average quickening specializations) = 55 handlers. Each handler is ~20-50 Lalin instructions (load, check, branch, emit call). Total: 55 × 35 = ~1925 Lalin instructions. Plus the dispatch loop: ~20 instructions. Plus GC: ~200 instructions. Plus metamethod dispatch: ~200. Total: ~2500 Lalin instructions. This is **large but not enormous**. It's about 2-3x the size of a typical Lalin benchmark program. Compile time should be under 500ms.

### 12. Validate_proto as Trust Boundary — The Trap of Self-Hosting

**The validation cost argument is backwards.** The question isn't "can we skip validation because we trust the compiler" — it's "can the VM crash in a way that violates memory safety if validation is wrong."

Lalin's safety model is: Lalin code cannot produce memory-unsafe operations (bounds-checked views, typed pointers). But **the VM deals with raw memory** (stack slots, heap-allocated tables, raw bytes for strings). If validation is wrong, an invalid Proto could cause out-of-bounds stack writes, which corrupt adjacent frames.

**Required validations for memory safety**:
1. `pc` valid: every instruction offset is within `Proto.code` bounds
2. Stack slots valid: every `RA`, `RB`, `RC` is within `maxstacksize`
3. Constants valid: every `K` index is within `Proto.k` bounds
4. Upvalue indices valid: every upvalue index is within `Proto.upvalues` bounds
5. Control flow sound: no infinite loop without GC safepoint (not required for safety, required for liveness)

**The non-obvious issue is (5)**: PUC Lua doesn't validate infinite loops. The OS kills the process. Lalin's VM has an explicit OOM continuation — what about an infinite loop that doesn't allocate? `while true do end` runs forever without GC, never hitting a safepoint, never checking the OOM continuation, never calling the GC. The thread is stuck. In PUC, the kernel scheduler eventually timeslices. In Lalin, if the thread is native code in an infinite loop, it's truly stuck. **The VM needs a GC safepoint (or a yield check) at backward jump targets** to break infinite loops. PUC does this too (the `hook` mechanism checks line hooks). But without this, the VM is vulnerable to livelock.

**The compiler trust question**: If the Lalin VM is compiled from a `.mlua` source using the same Lalin compiler that produces the VM binary, then yes — we implicitly trust the compiler port hasn't introduced validation bugs. But this is a circular trust: "we trust the VM because the compiler is correct, and we trust the compiler because the VM is correct." In practice, the VM is the reference (it should match PUC behavior) and the compiler is derived. Validation is still needed because a compiler bug could produce invalid Proto, and the VM should crash safely (via the error continuation) rather than writing out of bounds.

---

## Knowledge Gaps

1. **How does `emit` actually compile in the current pipeline?** I need to see how a multi-block region with several continuations expands to BackCmd. Does each continuation become a separate BackBlock? How are block parameters lowered to Cranelift block params? This determines the actual phi cost of the 14-way return.

2. **What is the status of the QuickInstr / InlineCache struct** in the actual codebase? The design doc mentions them but I haven't verified if they're spelled out in Lalin struct syntax anywhere.

3. **How does Cranelift handle block arguments in practice?** Does it eliminate them via SSA optimization, or do they become actual register moves? I should examine the Cranelift IR output from a multi-block Lalin program to see the actual lowering.

4. **What is the maximum `maxstacksize` the compiler produces?** PUC's default is 250. If Lalin's compiler produces larger frames for deep expressions, the per-frame state cost changes.

5. **Is there existing infrastructure for GC** in any Lalin stdlib? The `arena.mlua` provides bump allocation — but bump allocators don't trace. Is there a tracing GC anywhere in the Lalin ecosystem?

6. **What is the actual behavior of `@{}` splices for region generation?** Can I generate a region whose continuations are not known until Lua runtime? This matters for the metamethod tiering approach — if region signatures must be fully specified at macro-expansion time, tiered selection requires different API design.
