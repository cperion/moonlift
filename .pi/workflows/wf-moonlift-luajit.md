# Workflow 
**Started**: 2026-05-21 20:17:47
---

## Knowledge-builder Output — 2026-05-21 20:21:12

I now have sufficient data from both LuaJIT and Moonlift internals to produce the deep analysis. Here it is.

---

## What Matters Most for This Problem

The rewrite question isn't "can Moonlift do everything C can?" — it can't. The real dimensions are:

1. **Reach of Moonlift's type system**: What LuaJIT behaviors rely on C features Moonlift lacks (pointer arithmetic, tagged unions, stack introspection, computed goto, unchecked casts)?
2. **Region-modelable vs. imperative**: Can a LuaJIT subsystem be expressed as a Moonlift region (typed CFG with explicit yields/jumps) or does it fundamentally require mutable shared state across non-local control flow?
3. **Wire format boundaries**: Moonlift communicates between Lua and Rust via Flatline binary format. Which LuaJIT subsystems already have a similar boundary (bytecode, IR snapshots, trace data)?
4. **Monormophism tolerance**: LuaJIT is dynamically typed at the Lua level but monomorphic inside traces. Moonlift is monomorphic always. Which subsystems are already monomorphic in practice?

---

## Non-Obvious Observations

### 1. Architectural Tensions — Where Designs Collide

**The interpreter loop cannot be expressed in Moonlift.**

This is the single most important constraint. LuaJIT's interpreter in `vm_*.dasc` uses:
- Computed goto (direct threading): `goto *dispatch[op]`
- Tight register pinning: `BASE=edx, PC=esi, DISPATCH=ebx` (x86). These are hard-coded register assignments that span thousands of lines of assembly.
- Fall-through between opcodes with zero overhead: `|->vm_dispatch: ... |->loop_continuation:` — the `.dasc` labels become physical addresses in the code stream.
- Cross-section references: the interpreter dispatches to different code sections (opcodes, fast functions, stubs, exit handlers). All absolute or PC-relative.

Moonlift's `emit` splices a region body inline — zero-cost within a single compilation unit. But the interpreter is thousands of basic blocks connected by a virtual dispatch table (the opcode number). Moonlift has no `goto *table[op]` equivalent — `switch` requires all cases to be syntactic arms, not a computed target.

**Implication**: The interpreter stays in C/asm forever. This means Moonlift can only rewrite the *non-interpreter* parts of LuaJIT. Everything that runs inside the interpreter loop (the C helper functions like `lj_tab_get`, `lj_str_new`, etc.) must remain callable from C.

**The `BCDEF(opcode)` ordering constraint is tighter than it looks.**

The scout noted that BC_ISEQV^1 == BC_ISNEV, etc. But the ordering goes deeper: the bytecode encoding encodes `OP | A | B | C` in specific bit positions. The `B` and `C` operand *meanings* depend on the opcode's mode (BCMode enum). Moonlift's type system can model this as a tagged union, but the tight coupling between opcode number, bit layout, operand mode, and the interpreter's dispatch code means you can't change a single opcode without updating seven files. The Moonlift approach would need to define each opcode as an ASDL variant with typed operands, then generate the packed bytecode from that.

**The performance-critical path is the entire C-to-interpreter contract.**

LuaJIT's fast functions (`lj_ffh_*`, `lj_cf_*`) are called from the assembly interpreter via the DISPATCH table. They use `L->base`, `L->top`, and raw TValue access. Rewriting these in Moonlift would mean:
- Each call becomes a Cranelift-to-C transition (FFI boundary)
- All the fast-path argument checking happens in generated code, but the interpreter still needs to resume execution in assembly afterward
- Result: you've added a C→Moonlift→C crossing on every fast function call, which is already the hottest path in the system

### 2. Hidden Protocols — Beyond Switch-on-Kind

**The frame unwinding protocol is the deepest implicit contract.**

Look at `lj_frame.h` — frames encode their type in the low 3 bits of `frame_ftsz(delta)`:
```
FRAME_LUA    = 0  (PC is a BCIns pointer)
FRAME_C      = 1  (delta shift by 3)
FRAME_CONT   = 2  (continuation function pointer)
FRAME_VARG   = 3
FRAME_CP     = 5  (cpcall)
FRAME_PCALL  = 6  (protected call)
FRAME_PCALLH = 7  (protected call with hook)
```

Every function call in the interpreter and every JIT-compiled trace must conform to this encoding. The error handler in `lj_err.c` walks the stack frame-by-frame using `frame_prev()` which dispatches on these low bits.

Moonlift's regions emit flat CFG with explicit continuations — no frame introspection. You *could* model error unwinding as a region `walk_stack` with continuation exits for each frame type, but the walker would need to read the raw frame data. The problem: Moonlift has no non-type-erased way to represent a stack slot that is *sometimes* a GCobj pointer and *sometimes* a continuation address and *sometimes* a frame size delta, with the interpretation depending on 3 bits. Even a tagged union would require all variants to be known statically, but frame encoding is ABI-defined per architecture.

**The hotcounter-to-trace linkage is not a simple lookup.**

`lj_dispatch.h` shows `HotCount` is a uint16_t decremented on each loop/call. When it reaches 0, a trace recording begins. But the counter is indexed by `PC & HOTCOUNT_PCMASK`, creating a hash collision domain. Two different loop headers can share the same counter slot. When one gets hot, the other gets penalized. This is a deliberate performance tradeoff (cache-friendly packed counters), but it means the LuaJIT JIT's triggering behavior is non-deterministic — traces get recorded for whichever loop hits zero first.

Moonlift's `pvm.phase` caching uses canonical ASDL identity lookup — no hash collisions. If you rewrote the hot-counter logic in Moonlift, you'd need explicit handling for this aliasing, or accept a more expensive (per-PC) counter table.

**GCROOT_MAX is an API, not just a constant.**

The GC roots array (`g->gcroot[GCROOT_MAX]`) is indexed by a private enum scattered across multiple files. The GC marks all roots in `gc_mark_gcroot()`. Adding a new GC root means:
1. Add a new enum value to the `GCROOT_*` enum (in `lj_obj.h`)
2. Add the setgcref call that populates it (in whatever subsystem creates the root)
3. The GC *automatically* marks it — no registration code needed in the GC itself

This is a data-driven registration protocol. Every subsystem that has GC-ownable state silently participates by filling its slot. Moonlift has no GC and no equivalent protocol. If you wanted to add a new "root" for Moonlift's native heap objects, you'd need to either add them to LuaJIT's GC or manage them separately via Rust's `Arc`/`Box`.

### 3. The DynASM Replacement Problem

**DynASM does three things; Cranelift can do two of them.**

DynASM's capabilities:
1. **Instruction encoding**: Takes `.dasc` DSL with `.arch x64`, `| mov eax, ebx` syntax → produces raw bytes.
2. **Label resolution**: `|1:` forward/backward labels with displacement optimization (short/near jumps).
3. **Section layout and relocation**: `|.section code_op, code_sub` — multiple code sections with cross-section references.

Cranelift can do #1 (instruction encoding via its IR) and #2 (block labels, branch optimization). It *cannot* do #3 in the way DynASM does — Cranelift compiles one function at a time, producing a contiguous block of machine code. It has no concept of multiple code sections with cross-references that get linked at build time.

**The critical gap: DynASM produces code that is NOT a function.**

The interpreter output of DynASM is a single large blob of machine code with entry points like `lj_vm_interp`, `lj_vm_call`, `lj_vm_pcall`, `lj_vm_resume`. These are NOT C functions with standard calling conventions — they have custom register conventions, frame layouts, and error handling paths. They're entered by `lj_vm_asm_begin + offset`, and the offset is baked into the binary at build time.

Cranelift compiles functions with standard ABIs (System V, Windows x64). It cannot produce code that starts execution at offset 0x1234 from a base pointer with rdx = BASE, esi = PC, ebx = DISPATCH.

**What would need to exist**: A Cranelift-to-DynASM shim, or a separate assembler pass. You could:
- Keep DynASM for the interpreter (it works, it's battle-tested)
- Use Cranelift for everything else (IR lowering, fast functions, stub code)
- Or: write the interpreter in C with computed goto (Lua 5.4 does this) and compile with a C compiler that supports it (GCC, Clang). This loses LuaJIT's hand-optimized register allocation but removes the DynASM dependency.

**The `.actionlist` is not C — it's a generated opcode table.**

`buildvm.c` processes `.dasc` and produces `buildvm_arch.h`, which contains an embedded `actionlist` — a bytecode stream of DynASM actions (emit insn, fixup label, switch section). This actionlist is a C data array. The DynASM runtime (dasm_proto.h) interprets it at build time. In Moonlift, the equivalent would be a Lua table of `{opcode, operands}` that gets encoded at Lua → Cranelift time. But the actions are machine-code specific — `| mov rax, rbx` becomes different bytes for x86 vs arm64. You'd need a target-specific encoding table for each architecture, which is what `dasm_x86.h`, `dasm_arm64.h`, etc. already are.

**Implication**: Replacing DynASM means either:
- Transpiling `.dasc` to C computed-goto (doable, ~5000 lines of transpiler)
- Or maintaining per-arch encoding in Rust (Cranelift's MachInst layer already does this)
- Or keeping DynASM and calling into it from Moonlift's build

### 4. GC as Protocol Problem

**The tri-color invariant is fundamentally un-regionable.**

Let me be precise. The GC invariant is: *a black object never points to a white object.* This is enforced by write barriers at every store site:

```c
#define lj_gc_barriert(L, t, tv) \
  { if (tviswhite(tv) && isblack(obj2gco(t))) \
      lj_gc_barrierback(G(L), (t)); }
```

This is a *conditional mutation-time check*. A black object becomes gray (gets `black2gray`) when it receives a white reference. The check depends on:
- The *current* color of the target (black?)
- The *current* color of the value (white?)
- The *current* GC phase (must not be Spause or Sfinalize)

These are all runtime, mutable, history-dependent properties of heap objects. Moonlift's region system has:
- No mutable heap objects (SSA values only)
- No identity (two values of the same type are interchangeable)
- No mutation-time side effects (regions are pure CFG with explicit continuations)

**What CAN be modeled**: The GC state machine itself.

```moonlift
region gc_cycle(g: ptr(GCState);
    pause: cont,
    propagate: cont,
    atomic: cont,
    sweep_str: cont,
    sweep: cont,
    finalize: cont)
    
    entry start()
        jump pause()
    end
    block pause()
        -- mark roots, compute phases
        if g.state == GCSpause then 
            -- transition to propagate
            jump propagate()
        end ...
    end
    ...
end
```

But this is just the *controller*. The *actual GC work* (marking objects, sweeping, finalizing) requires heap mutations that Moonlift cannot express. The region would need to call into C functions for the actual GC work, making it a thin control layer.

**The barrier is worse than it looks for Moonlift.**

Look at the barrier conditions in `lj_obj.h` — there are 7 categories (stack slots, GC roots, lua_State fields, open upvalues, new objects, self-refs, identical source/target) where the barrier can be *omitted*. Every LuaJIT developer must internalize these rules. In Moonlift, you'd have *none* of these categories because Moonlift has no heap objects to protect. But you'd need to ensure that any LuaJIT C code you call INTO respects the barrier — and the barrier macros are scattered across every file that does a `setgcref` or `setgcV`.

**Bottom line**: The GC stays in C. Moonlift can model the control flow but not the mutations.

### 5. GG_State Consolidation — Essential, Not Accidental

Let me read what GG_State actually contains:

```c
typedef struct global_State {
    lua_Alloc allocf;         // allocator
    void *allocd;             // allocator data
    GCRef gcroot[GCROOT_MAX]; // all GC roots
    GCState gc;               // GC state machine
    ...
    jit_State jit;            // JIT compiler state (inlined!)
    HotCount hotcount[HOTCOUNT_SIZE]; // hot counters
    ...
    ASMFunction *dispatch;    // dispatch table for bytecodes
    ...
} global_State;
```

The JIT state is **inlined** into GG_State — not a pointer. This means:
- One allocation at state creation contains everything
- `G(L)` macro computes the base address from the thread pointer (stored in a register)
- DISPATCH register points into this same structure

The JIT state (`jit_State`) itself contains the entire trace compiler state: current IR buffer, snapshot list, mcode allocation, etc. It's all one contiguous allocation.

**Why this matters for Moonlift**: Moonlift's compilation model uses PVM phases with separately cached ASDL values. There is no global megastate. Each phase boundary memoizes on canonical ASDL identity. If you rewrote LuaJIT's trace compiler as Moonlift phases, you'd need to:
- Replace `J->cur` (the current trace IR) with a PVM triplet keyed by (trace_id, snapshot_number)
- Replace `J->snap[]` with a phase that produces snapshots on demand
- Replace `J->mcode` with Cranelift's `FuncCompilerState`

But the hotcounters, dispatch table, and GC state are fundamentally a single memory allocation because:
1. Hotcounters need to be in the same cache line as dispatch to reduce cache misses
2. The interpreter's `DISPATCH` register points to the middle of GG_State — it accesses hotcounters, GC step, and JIT state via small offsets from the same base
3. This register is used in every bytecode dispatch cycle

Moonlift would explode this into separate allocations connected by references, losing the cache locality. For a new implementation, this might be acceptable. For a rewrite, it changes performance characteristics significantly.

### 6. Macro-to-Lua Translation Depth

| Macro Family | LuaJIT Usage | Moonlift/Lua Equivalent |
|---|---|---|
| **BCDEF** | Enum generation + mode table + static assertions | `local BC = {}; for ... end` table of opcode descriptors. Or: ASDL variants `BC[MOV] = {kind="MOV", format="ABC", bmode="dst", cmode="var"}` |
| **IRDEF** | Enum + CSE class + operand type + fold table | ASDL variants with `IR[...] = {kind=..., flags={commutative, cse, ...}}` |
| **ERRDEF** | Enum + string message pair | `local ERR = {["name"] = "msg string"}` But also: `lj_err_allmsg` concatenation trick (offset-based lookup) → Moonlift would use a table lookup |
| **CCX** | 5-bit compressed type index: 3 bits source + 3 bits dest | A 64-entry dispatch table. In Moonlift: `switch CCX(dst, src) ... end` where the switch exhaustively covers 64 cases. C generation already auto-generates this in `buildvm_fold.c` |
| **LJLIB_CF / LJLIB_ASM** | Scanned by `buildvm_lib.c` to generate REG functions | Lua functions directly: `moon.chain` and `host.lua` already define the binding API. The buildvm scanning step becomes Lua `require` + table registration |
| **GOTDEF** | Enum + string for GOT entries | `local GOT = {["err_throw"] = ..., ["gc_step"] = ...}` — but GOT layout affects MIPS ABI. Moonlift doesn't target MIPS, so this is simpler |
| **IRFLDEF** | offsetof(GCstruct, field) pairs | In Moonlift, field layout is an ASDL definition, not `offsetof`. The Flatline wire format encodes field offsets explicitly |
| **FPMATH_DEF** | Sub-function enum | Moonlift `switch` on the FPMath sub-op inside the FPMATH handler |

**Key insight the scout missed**: The `BCDEF` and `IRDEF` macros use positional macro arguments to encode multi-dimensional data (opcode name, operand modes, CSE class, etc.). This is C's way of doing ad-hoc data-driven programming. In Lua, you'd write a table:

```lua
-- LuaJIT's approach
IRDEF(_)  -- the C preprocessor iterates

-- Moonlift's approach
local ir_defs = {
    {name="ADD", cse="C", op1="ref", op2="ref"},
    {name="SUB", cse="N", op1="ref", op2="ref"},
    ...
}
```

But there's a subtle issue: C's preprocessor lets you re-include the same macro file under different `#define` contexts to generate *different* output (enums, tables, fold rules, debug strings). In Lua, you'd iterate the same table multiple times with different processing functions — cleaner but requires that the table exists as data at load time, which it already does in Moonlift.

**The LJLIB scanning problem**: `buildvm_lib.c` reads `lj_libdef.h` and generates `lj_lib_init_*` bytecode arrays by scanning for `LJLIB_CF`, `LJLIB_ASM`, `LJLIB_LUA`, etc. This scanning is necessary because C has no reflection. In Moonlift/Lua, these libraries can register themselves:

```lua
-- Instead of:
-- /* LJLIB_CF(string_byte) */
-- static int lj_cf_string_byte(lua_State *L) { ... }

-- In Moonlift:
moon.string.byte = moon.extern_func(...)
```

The buildvm scanning entirely disappears. The registration happens at Lua load time through table assignment, not through build-time code generation. This is a real simplification.

### 7. Buildvm Dependency Mapping

| buildvm Subsystem | What It Does | Moonlift Equivalent |
|---|---|---|
| `buildvm_asm.c` | Processes `.dasc` → embeds actionlist in C | **Keep DynASM** or transpile to C computed-goto. The actionlist is architecture-specific |
| `buildvm_fold.c` | Generates `lj_opt_fold.c` from `lj_folddef.h` | PVM phase with fold rules as ASDL data. Folding becomes a pure transformation on ASDL IR nodes |
| `buildvm_lib.c` | Generates library init bytecode from `lj_libdef.h` / `lj_ffdef.h` | Lua `require` + table registration at load time. No build step needed |
| `buildvm_peobj.c` | Generates Win32 PE object files for embedding | Could generate Cranelift object file output directly |
| `genlibbc.lua` | Generates initial bytecode for Lua libraries | Lua source loaded at build time, compiled by Moonlift's compiler into Flatline format |

**What maps cleanly**: `buildvm_fold.c`, `buildvm_lib.c`, `genlibbc.lua`. These are data-to-data transformations that produce C arrays. In Moonlift, they produce Lua tables and ASDL values.

**What doesn't map**: `buildvm_asm.c`. The DynASM actionlist is machine code encoding at build time. Moonlift's equivalent would need either:
- A Rust crate that compiles `.dasc` syntax (no such crate exists)
- Or transpiling `.dasc` to C with computed gotos and calling that through the C compiler

**Important nuance**: LuaJIT's build system compiles `buildvm.c` into a *host* executable (running on the build machine), which then generates C files that are compiled into the *target* binary. This is cross-compilation safe. Moonlift's Lua-side build executes on the host LuaJIT, which is the same process. The `LUAJIT_TARGET` macros in `lj_arch.h` handle the host/target distinction — Moonlift would need a similar mechanism if cross-compiling.

### 8. Error Handling Architecture Gap

**Where longjmp is genuinely right:**

1. **Stack overflow**: When the C stack overflows, you have ~0 bytes of usable stack. You cannot call functions, allocate memory, or even do meaningful cleanup. `longjmp` out of the signal handler is the only option. Moonlift can't help here.

2. **GC barrier failures**: If a store violates a GC invariant, the GC state is corrupted. Best you can do is abort. `longjmp` to the nearest pcall boundary. Moonlift protocols can't prevent this because the GC state is imperative.

3. **Memory allocation failure**: When the allocator returns NULL, you're in the same situation as stack overflow — OS-level exhaustion. `longjmp` is the escape hatch. Moonlift's monomorphic typed system wouldn't have GC allocation failures (it uses Rust allocation), but host-side allocation failures still need this.

**Where Moonlift protocols would be better:**

1. **Type errors in FFI code**: `lj_err_optype`, `lj_err_argtype` — these are called from fast functions when argument types don't match. In Moonlift, each extern function has typed parameters. Type mismatch is caught at compile time or at the FFI boundary, not during execution. The error path becomes a protocol exit, not a longjmp.

2. **Trace abort reasons**: `lj_trace_err(J, LJ_TRERR_*)` is called when the trace compiler encounters something it can't handle. There are ~30 error codes. In Moonlift, these would be region continuation exits:

```moonlift
region record_trace(trace: ptr(TraceState);
    ok: cont(mcode: ptr(u8)),
    too_many_slots: cont,
    unsupported_op: cont(opcode: i32),
    ...)
    
    -- each guard becomes a protocol exit
    if num_slots > MAX_SLOTS then jump too_many_slots() end
    ...
end
```

3. **Bytecode verification errors**: `lj_parse.c` generates errors for malformed syntax. In Moonlift's parser (which is already in Lua), errors are protocol exits or return values, not longjmps. The PVM phase boundary naturally captures errors as phase failures.

**The hidden issue: `errfunc` and C API error handling.**

Lua's C API uses `lua_pcall(L, nargs, nresults, errfunc)`. The `errfunc` is a C function pointer called on error. This is used by `luaL_loadfile`, `xpcall`, etc. In Moonlift, you'd need to model this as a callback protocol:

```moonlift
extern lua_pcall(L: ptr(lua_State), nargs: i32, nresults: i32, msgh: i32) -> i32 as "lua_pcall" end
```

But `lua_pcall` internally uses `setjmp`/`longjmp`. You can't call into it from Moonlift and intercept the error path — the longjmp skips Moonlift's stack frames entirely. Moonlift functions called from C (via `lua_CFunction`) that raise errors via `lua_error` will longjmp past any Moonlift cleanup code.

**Mitigation**: Moonlift extern functions that call into Lua must either:
- Never raise Lua errors (return error codes instead)
- Or be wrapped in a C trampoline that setjmps before calling into Moonlift

### 9. Interpreter/JIT Split — How Moonlift Would Model This

**The interpreter itself cannot be Moonlift** (as established). But the *relationship* between interpreter and JIT can be modeled.

Current LuaJIT architecture:
```
Interpreter (DynASM) ←→ C helper functions (lj_tab_*, lj_str_*, etc.)
     ↕  (DISPATCH table)            ↕
JIT trace recorder (lj_record.c) ←→ Optimizer passes (lj_opt_*.c)
     ↕                                ↕
JIT assembler (lj_asm.c)         ←→ lj_ircall.h (C call annotations)
```

Moonlift would model this as:
```
Interpreter (stays in C/asm) ←→ C helpers (stay in C)
     ↕  (Flatline bytecode)       ↕
Trace recorder (Moonlift phase) ←→ Optimizer (Moonlift phase on ASDL IR)
     ↕                                ↕
Cranelift backend (Rust)        ←→ Moonlift extern decls
```

The critical boundary is between the C interpreter and the Moonlift trace compiler. Currently, the interpreter calls `lj_dispatch_ins` for every bytecode, which checks whether tracing is active. In Moonlift, this check becomes a region:

```moonlift
-- In the interpreter C code (stays C):
-- if (G(L)->jit.state & LJ_TRACE_ACTIVE) lj_dispatch_ins(J, pc);

-- In Moonlift (models the dispatch logic):
region dispatch_ins(J: ptr(jit_State), pc: ptr(bytecode);
    record: cont,
    patch: cont(new_pc: i32),
    none: cont)
    
    if (J.state & TRACE_ACTIVE) ~= 0 then
        if J.state == TRACE_RECORD then jump record()
        else jump none()
        end
    else
        jump none()
    end
end
```

But this region runs in Moonlift-generated code, which means the interpreter exits to Moonlift code (C→Moonlift transition) just to check a flag. That's a function call penalty. The flag check is currently a single memory load + test in the dispatch loop.

**Realistic split**: The interpreter, dispatch, and fast-path helpers stay in C/asm. The trace compiler, optimizer, and backend are Moonlift + Rust. The boundary is at `lj_dispatch_ins` / `lj_dispatch_call` — whenever the interpreter decides to record a trace, control transfers to Moonlift, which compiles the trace through its phases, then emits Cranelift machine code.

### 10. First Target Ranking — Best Subsystem for Initial Rewrite

**Rank 1: The Fold Optimizer (`lj_opt_fold.c` + `buildvm_fold.c` + `lj_folddef.h`)**

Reasons this is the best first target:

1. **Purely functional**: Takes IR → IR. No side effects, no GC, no mutation, no I/O. Ideal for Moonlift's SSA semantics.

2. **Data-driven**: The fold rules are generated from `lj_folddef.h` by `buildvm_fold.c`. The generated C is a massive switch statement with ~800 entries. In Moonlift, this becomes an ASDL-typed transformation:

```moonlift
-- Fold rule: ADD(0, x) → x
if ir.op == IR_ADD and ir.left == 0 then
    return ir.right
end
```

3. **Self-contained boundary**: Input is an IR instruction (type-stable ASDL value). Output is an IR instruction or IR_NONE. No global state needed. The PVM cache naturally memoizes fold results.

4. **Reveals the rewrite pattern**: The fold optimizer teaches you how to:
   - Represent IRDEF as ASDL variants
   - Express commutativity and associativity in the type system
   - Handle the transition from C macro-magic to Lua data-driven code
   - Validate that the rewritten optimizer produces bit-identical IR

5. **Testing is straightforward**: Feed IR instructions to the old and new optimizer, compare outputs. The Flatline wire format can serialize both for cross-validation.

**Rank 2: The bytecode loader/writer (`lj_bcread.c` + `lj_bcwrite.c`)**

These are pure serialization: bytecode ↔ in-memory Proto structures. Flatline wire format already handles binary encoding. The bytecode format has a known header and opcode layout.

**Rank 3: The trace snapshot system (`lj_snap.c`)**

Snapshot marshalling during trace recording is a state-capture operation. It's already type-stable (IRRef → TValue mapping) and has no side effects on the program state. The snapshot data flows into Cranelift's register allocation for exit stubs.

**Why NOT the obvious choices**:

- **Parser (lj_parse.c)**: Already exists in Lua in Moonlift. You'd be rewriting something already rewritten.
- **GC (lj_gc.c)**: Requires heap mutation. Cannot be expressed in Moonlift.
- **Library functions (lj_lib_*.c)**: Performance-critical, called from interpreter loop. Adding Moonlift→C transition overhead kills the fast path.
- **Trace recorder (lj_record.c)**: Complex interplay with interpreter state (slot tracking, snapshot allocation, side exit generation). Too coupled to the C-level interpreter to extract cleanly.
- **JIT assembler (lj_asm.c)**: Generates machine code. Cranelift replaces this entirely. No need to "rewrite" it — just use Cranelift's backend.

---

## Knowledge Gaps

1. **Cranelift's MachInst layer**: I need to understand whether Cranelift's per-architecture backend (MachInst) can be used standalone — i.e., can you emit a single instruction via Cranelift without compiling a full function? This matters for DynASM replacement. *Spawn scout: src/lib.rs usage of Cranelift API.*

2. **The exact contents of `ljamalg.c`**: LuaJIT can be compiled as an amalgamation (all C files #included into one TU). This affects which Moonlift rewrite targets can be extracted independently. *Spawn scout: ljamalg.c structure and dependency graph.*

3. **LJ_FR2 and its effect on all frame macros**: The 64-bit GC64 mode changes frame layout from 1-slot to 2-slot (for 64-bit GCref + PC). Every frame macro in `lj_frame.h` has `#if LJ_FR2` variants. Moonlift's Flatline format would need to parameterize by this mode. *Spawn scout: How LJ_FR2 changes struct layouts across all files.*

4. **lj_ircall.h C call annotations**: The JIT backend needs to know C calling conventions for `CALLXS` IR instructions. These annotations are generated by buildvm. Moonlift's extern declarations would replace this, but the FFI boundary must match. *Spawn scout: lj_ircall.h format and how it feeds into lj_asm.c.*

## Approach-proposer Output — 2026-05-21 20:24:31

I now have a thorough understanding of both codebases. Let me formulate the three approaches.

---

### Approach A: "Surgical Overlay" — One Subsystem at a Time

**Core idea**: Rewrite LuaJIT's optimization passes one by one into Moonlift functions that compile to Cranelift machine code, called from C via FFI trampolines, while the interpreter, recorder, assembler, and GC stay untouched in C.

**Key changes**:

1. **Phase 1 — Fold optimizer only** (`lj_opt_fold.c` → Moonlift): The ~800-entry hash-table-driven IR folding becomes a Moonlift function `fold_ir(ir: IRIns) -> IRIns`. The existing C fold optimizer's `lj_opt_fold()` is replaced by a call to Moonlift `extern` function. The fold rules become ASDL data (Moonlift `switch` on opcode pairs), not a generated C table. `buildvm_fold.c` is retired.

2. **Phase 2 — DCE, loop opt, mem opt, narrowing, sinking** follow same pattern: each `lj_opt_*.c` pass becomes a Moonlift function. These transforms are purely functional on JIT IR (IRIns → IRIns or J->cur mutation via protocol exits).

3. **Phase 3 — Snapshot system** (`lj_snap.c`): Snapshot marshalling (IRRef→TValue mapping) becomes a Moonlift region with protocol exits for each snapshot slot type.

4. **Phase 4 — Trace recorder** (`lj_record.c`): The bytecode→IR emitter becomes a Moonlift region. This is the hardest part because it reads interpreter state (L->base, L->top, slot types). Each bytecode opcode becomes a Moonlift switch arm.

5. **DynASM stays** — interpreter and fast-function stubs remain `.dasc` + DynASM.

6. **Moonlift↔C boundary**: Each replacement is a separate `.o` file compiled via Moonlift's object-emission path, linked into LuaJIT's build. The C side calls a Moonlift function pointer (from the object file), and the Moonlift function reads/writes `jit_State` through `extern`-declared struct field offsets.

7. **GC stays in C entirely**.

8. **GG_State untouched** — Moonlift functions access `J` (read from `L`) via a C struct view passed as `ptr(u8)` with byte-offset field access.

9. **Testing**: Oracle testing. Run every Moonlift replacement against the original C implementation on the LuaJIT test suite. Compare IR output bit-for-bit. For the fold optimizer specifically: feed every possible `(op, op1, op2)` triple through both implementations and compare results.

**Tradeoff**: Optimizes for **safety and incrementality**. Minimal risk because each replacement is a small, verifiable step. The rest of the system never breaks. But pays a **performance tax**: each Moonlift pass is a C→Moonlift→C function call boundary. The optimizer is already the hottest path — adding FFI overhead may regress performance by 5-15%.

**Risk**: The FFI call overhead from C to Moonlift functions could negate the benefits of rewriting. For the fold optimizer specifically, `lj_opt_fold` is called for *every IR instruction emitted* — thousands of times per trace. Each call currently is a single C function call. Adding a Cranelift-compiled function call + marshalling for ~800 table lookups could be 2-3x slower for that pass alone. The other passes (DCE, loop opt) are called once per trace and the overhead is negligible.

**Rough sketch**:
```
1. Extract IRDEF and the fold rule semantics as Moonlift ASDL types
2. Implement fold rules as Moonlift switch(ir.op, op1.op, op2.op)
3. Compile to .o via moon.emit_object
4. Link into LuaJIT build: replace lj_opt_fold call with a call to moonlift_fold
5. Run lj_tests/*.lua — verify identical trace output
6. Repeat for lj_opt_dce, lj_opt_loop, lj_opt_mem, lj_opt_narrow, lj_opt_sink
7. Then tackle lj_snap.c (higher coupling)
8. Finally lj_record.c (highest coupling, last)
```

This is ~12-18 months of work if done serially, ~6-9 months if parallelized (each pass is independent).

---

### Approach B: "Sidecar JIT" — Moonlift Compiles Traces as Cranelift Functions

**Core idea**: Replace the entire LuaJIT JIT pipeline (recorder → optimizer → assembler) with a new Moonlift-compiled trace compiler. The interpreter in C/asm remains, but when a trace is hot, Moonlift takes over: it reads the bytecode stream and the LuaJIT internal state, records a trace in Moonlift ASDL IR (not IRIns), optimizes it through Moonlift phases, and emits Cranelift machine code as a standard-ABI function. LuaJIT's assembler (`lj_asm.c`) and all `lj_opt_*.c` passes are never called — they're replaced wholesale.

**Key changes**:

1. **New trace compiler in Moonlift** under `lua/moonlift/luajit/` — modules for trace recording, snapshot management, IR optimization, and Cranelift backend linkage. This is *not* a line-for-line port of `lj_record.c`. It's a new design: bytecode → ASDL IR (not IRIns) → Moonlift optimization phases → Cranelift.

2. **Moonlift JIT calls LuaJIT C functions** for GC interactions (lj_tab_get, lj_str_new, etc.) and runtime helpers (lj_meta_call, etc.). These are declared as `extern` Moonlift functions.

3. **Interpreter modification**: The hot-count dispatch in `lj_dispatch.c` detects when a loop is hot and calls into Moonlift's trace compiler instead of `lj_trace_hot`/`lj_record.c`. Moonlift compiles the trace and returns a function pointer. The interpreter stores this in the dispatch table, replacing the bytecode entry with a direct jump to compiled code (same mechanism as existing LuaJIT).

4. **LuaJIT's `jit_State` struct** is extended with Moonlift-specific fields for the new compiler's state (Moonlift ASDL context for the trace, etc.). These are allocated separately from GG_State, not inlined.

5. **DynASM stays** — the interpreter and all fast-function stubs remain in `.dasc`. The Moonlift-compiled traces are standard-ABI functions called from the interpreter's exit stubs.

6. **GC stays in C** — Moonlift traces call `lj_gc_barrier*` via `extern`.

7. **Optimization passes** use Moonlift's PVM phase system. Each pass (fold, DCE, loop, sink) is a PVM phase boundary on ASDL IR. No hash-table generated code. No `buildvm_fold.c`.

8. **Snapshot system** is a Moonlift region that serializes Moonlift ASDL values into LuaJIT's snapshot format for side exits back to the interpreter.

9. **Fallback**: If Moonlift's trace compiler encounters something it can't handle (e.g., FFI calls, complex metamethods), it falls back to LuaJIT's original JIT by calling `lj_record.c`'s original entry point.

**Tradeoff**: Optimizes for **architectural coherence**. The trace compiler is entirely in Moonlift, with clean phase boundaries. No incremental "partial C → Moonlift" hybrid. But this is a **flag-day migration** — Moonlift's trace compiler must be good enough to handle the majority of traceable Lua code before it's useful. No gradual substitution possible.

**Risk**: The trace recorder (`lj_record.c`, 2900 lines) is one of the most complex parts of LuaJIT. It couples deeply with interpreter state (slot tracking, upvalue handling, coroutine suspension, FFI recording). Reimplementing it in Moonlift is an 18-24 month project with significant risk of subtle correctness bugs. The side exit mechanism (snapshots + exit stubs) is arch-specific — x86_64 call/return convention from compiled traces back to interpreter must match the existing system exactly or traces will corrupt the stack.

**Rough sketch**:
```
1. Build Moonlift ASDL types for LuaJIT bytecodes (BCDEF) and IR (IRDEF)
2. Design new trace format: Moonlift ASDL IR nodes (not IRIns)
3. Implement bytecode-to-IR consolidation in Moonlift (the recorder)
4. Reuse existing Moonlift PVM optimization phases (fold, DCE, etc.) on the new IR
5. Build snapshot/exit-stub generation in Moonlift (calls into C for mcode allocation)
6. Modify lj_dispatch.c to route hot loops to Moonlift compiler
7. Implement fallback to original LuaJIT JIT for unsupported bytecodes
8. Test on LuaJIT's own test suite + real-world Lua programs
9. Remove lj_record.c, lj_opt_*.c, lj_asm.c, lj_snap.c from build after validation
```

This is ~18-24 months. Can be prototyped in 6 months for a subset of bytecodes (arithmetic + table access only).

---

### Approach C: "New Backend, Same Middle" — Cranelift Replaces lj_asm.c

**Core idea**: Keep LuaJIT's trace recorder and optimizer *in C* but replace the assembler backend (`lj_asm.c`, ~2500 lines) with Cranelift. The trace recorder produces IRIns as before, and the optimizer transforms them as before. But instead of `lj_asm.c` turning IRIns into machine code via arch-specific `lj_emit_*.h` and DynASM backends, a Moonlift/Cranelift bridge reads the final IR (after all C passes) and emits it as a Cranelift function with standard ABI. The interpreter, recorder, and all optimization passes stay in C.

**Key changes**:

1. **New Cranelift backend**: A Rust crate `src/luajit_asm.rs` that takes `IRIns *ir, int nins` and produces a Cranelift function. This is *not* a Moonlift module — it's a direct Rust ↔ C FFI binding because the IR is C structs, not Moonlift ASDL.

2. **`lj_asm.c` is deleted** from the build. The function `lj_asm_trace()` is replaced by a call to `moonlift_asm_trace(J)`, which calls into Rust to compile the trace via Cranelift.

3. **Snapshot and exit-stub generation** is still in C (`lj_snap.c` stays) — it produces the data structures that the exit machinery uses. Cranelift compiles each basic block and generates the exit stubs as standard ABI calls back to the interpreter.

4. **MCode allocation** (`lj_mcode.c`) stays in C. Cranelift emits machine code bytes, which are copied into the mcode area. The existing code permission management (mprotect) and code cache invalidation continue unchanged.

5. **`J->mcode`** and the mcode management system remain. Cranelift just provides the bytes.

6. **`buildvm_fold.c` stays** — the fold hash table is still generated from `lj_folddef.h` because the optimizer is still the C implementation. The fold table is CPU-agnostic data — it doesn't change.

7. **`lj_emit_*.h` files** (lj_emit_x86.h, lj_emit_arm64.h, etc.) become unused and can be deleted. These are the arch-specific instruction emitters that `lj_asm.c` calls.

8. **`lj_ircall.h` stays** — it describes C function call annotations needed by the assembler. Cranelift can use the same annotations to emit correct call sequences.

9. **Incubation**: Initially, both `lj_asm.c` and the Cranelift backend are compiled. A runtime flag (`jit_asm_backend=2`) selects Cranelift mode. Trace assembly output is compared between the two for verification.

**Tradeoff**: Optimizes for **fastest path to value**. Only one subsystem is replaced (the assembler), and it's the most architecture-specific part — the one that benefits most from Cranelift's per-arch lowering. The complex recorder/optimizer logic stays in battle-tested C. Risk is low because the assembler's input/output contract (IRIns → machine code bytes) is narrow and well-defined. But this is the **least ambitious** rewrite — it doesn't leverage Moonlift's type system or PVM phases at all.

**Risk**: The assembler is deeply arch-specific. `lj_asm.c` contains register allocation, fusion (fold loads into addressing modes), calling convention transitions, and side-exit stub generation. Cranelift's register allocator is good but may generate different spilling decisions, leading to different performance characteristics. For comparisons in oracle mode, byte-exact output is impossible (different register allocation) — must compare functional correctness instead.

**Rough sketch**:
```
1. Write Rust function: moonlift_asm_trace(J) -> int
   - Reads J->cur.ir[nk..nins] as IRIns
   - Translates each IRIns to Cranelift IR ops
   - Compiles via Cranelift ObjectModule or JITModule
   - Copies emitted machine code bytes into J->mcode area
   - Writes J->curfinal, J->mcarea, etc.
2. Add #ifdef LUAJIT_USE_CRANELIFT around original lj_asm.c
3. Add runtime flag to switch between C and Cranelift backends
4. Verify correctness: compile Lua programs with both backends, compare results
5. Benchmark to identify performance regressions
6. Handle exit stubs (lj_asm.c's biggest arch-specific chunk)
7. Delete lj_asm.c, lj_emit_*.h, and arch-specific .dasc files
```

This is ~6-9 months. Can produce a working prototype in 3 months for x86_64 only.

---

### Comparison

| Dimension | A: Surgical Overlay | B: Sidecar JIT | C: New Backend |
|---|---|---|---|
| **Road to value** | 3-4 months (fold), then each pass adds 1-2 months | 18+ months before usable | 3-6 months for prototype |
| **Risk level** | Low (per-pass, verifiable) | High (re-creates the most complex subsystem) | Low-Medium (narrow interface) |
| **Moonlift leverage** | Medium (uses Moonlift's switch+typed ASDL for each pass) | High (full Moonlift architecture: ASDL IR, PVM phases, Cranelift) | Low (Moonlift not used; direct Rust+Cranelift on C structs) |
| **Retired code** | One .c per pass + buildvm_fold.c | lj_record.c, all lj_opt_*c, lj_asm.c, lj_snap.c, buildvm_*.c | lj_asm.c, all lj_emit_*.h |
| **Performance risk** | FFI call overhead on hot paths | Compiler quality of Moonlift-generated trace recorder | Different register allocation, fusion patterns |
| **Maintainability win** | Marginal (hybrid C+Moonlift) | Maximum (all JIT in Moonlift) | Marginal (assembler in Rust, rest in C) |
| **Can stop early** | Yes — each pass is independently useful | Not really — the recorder is the hard part | Yes — prototype proves Cranelift viability |

**When to pick each**:
- **A** if the goal is "prove Moonlift can incrementally replace performance-critical C" without betting the farm on a single rewrite. The fold optimizer is the perfect first target.
- **B** if the goal is "Moonlift becomes the trace compiler" as a long-term strategic vision, and you're willing to invest 2+ years to get there.
- **C** if the goal is "ship Cranelift in LuaJIT *now*" as a pragmatic backend replacement, treating Moonlift as a future concern rather than a current dependency.
