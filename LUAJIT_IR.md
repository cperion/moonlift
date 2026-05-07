# LuaJIT IR — Complete Reference

## IR instruction format

```text
64-bit IRIns:

  +----------+----------+------+------+------+------+
  |   op1    |   op2    |  t   |  o   |  r   |  s   |  (pre-regalloc view)
  +----------+----------+------+------+------+------+
  |        i / gcr / ptr        |  ot  |  prev    |  (alternative)
  +----------+----------+------+------+------+------+
  |             TValue / 64-bit const               |  (2nd slot for 64-bit consts)
  +----------+----------+------+------+------+------+

  op1, op2 : IRRef (16-bit) — SSA references to operand instructions
  t        : IRType (8-bit)  — result type + guard/phi/mark flags
  o        : IROp   (8-bit)  — opcode
  r, s     : uint8  — post-regalloc: register + spill slot

Constants: IR_KINT stores i32 in the `i` field; IR_KNUM stores f64 in the
following IR slot. IR_KGC stores a GCref in the `gcr` field (GC objects
are referenced by 32-bit offset from GG_State, so Pointer-Seek-Free GC).

REF_BIAS = 0x8000 separates constants (below) from instructions (above).
Constants grow down from REF_BIAS; instructions grow up from REF_BIAS+1.
```

---

## SSA references (TRef)

A TRef is a 32-bit tagged reference:

```text
  +----------------+----------+--------------------+
  |     irt (8)    | flags(8) |     ref (16)       |
  +----------------+----------+--------------------+

  irt: copy of the IR result type — enables fast type checks
  ref: IR reference index (IRRef1)
  flags: TREF_FRAME, TREF_CONT, TREF_KEYINDEX

Fixed refs:
  REF_TRUE  = 0x7FFD
  REF_FALSE = 0x7FFE
  REF_NIL   = 0x7FFF
  REF_BASE  = 0x8000   ← constants grow down, instructions grow up
  REF_FIRST = 0x8001   ← first real IR instruction
```

---

## IR opcodes — complete list

### Guards
`[G]` = GUARD flag set on the IR type. These exit the trace if the
condition fails. Must be properly aligned to flip opposites with `^1`
and unordered with `^4`.

```
IR_LT    [G]  ref, ref     signed less-than        ← flip: IR_GE = LT^1
IR_GE    [G]  ref, ref     signed greater-or-equal
IR_LE    [G]  ref, ref     signed less-or-equal     ← unordered flip: ULT = LT^4
IR_GT    [G]  ref, ref     signed greater-than
IR_ULT   [G]  ref, ref     unsigned less-than
IR_UGE   [G]  ref, ref     unsigned greater-or-equal
IR_ULE   [G]  ref, ref     unsigned less-or-equal
IR_UGT   [G]  ref, ref     unsigned greater-than
IR_EQ    [G]  ref, ref     equality
IR_NE    [G]  ref, ref     inequality
IR_ABC   [G]  ref, ref     array bounds check
IR_RETF  [G]  ref, ref     return from fast function
```

### Miscellaneous
```
IR_NOP        ___, ___     no-op (dead instruction placeholder)
IR_BASE       lit, lit     base reference (frame base pointer)
IR_PVAL       lit, ___     parent value (inherited from parent trace)
IR_GCSTEP     ___, ___     GC step barrier (periodic GC check)
IR_HIOP       ref, ref     high-word op (for 64-bit on 32-bit archs)
IR_LOOP       ___, ___     loop marker (back-edge, end of trace)
IR_USE        ref, ___     keep operand alive (prevents DCE)
IR_PHI        ref, ref     phi node (loop-carried value merge)
IR_RENAME     ref, lit     rename register (for PHI resolution)
IR_PROF       ___, ___     profiler hook
```

### Constants
```
IR_KPRI       ___, ___     primitive constant (nil, false, true)
IR_KINT       cst, ___     32-bit integer constant (in `i` field)
IR_KGC        cst, ___     GC object constant (string, proto, tab, func)
IR_KPTR       cst, ___     pointer constant (lightuserdata)
IR_KKPTR      cst, ___     kernel pointer constant
IR_KNULL      cst, ___     NULL pointer constant
IR_KNUM       cst, ___     64-bit float constant (in next IR slot)
IR_KINT64     cst, ___     64-bit integer constant (in next IR slot)
IR_KSLOT      ref, lit     stack slot reference (base + offset)
```

### Bit ops
```
IR_BNOT       ref, ___     bitwise NOT
IR_BSWAP      ref, ___     byte swap (endian conversion)
IR_BAND  [C]  ref, ref     bitwise AND         ← commutative
IR_BOR   [C]  ref, ref     bitwise OR          ← commutative
IR_BXOR  [C]  ref, ref     bitwise XOR         ← commutative
IR_BSHL       ref, ref     bit shift left
IR_BSHR       ref, ref     bit shift right (logical)
IR_BSAR       ref, ref     bit shift right (arithmetic)
IR_BROL       ref, ref     bit rotate left
IR_BROR       ref, ref     bit rotate right
```

### Arithmetic
```
IR_ADD   [C]  ref, ref     addition             ← commutative
IR_SUB        ref, ref     subtraction
IR_MUL   [C]  ref, ref     multiplication       ← commutative
IR_DIV        ref, ref     division
IR_MOD        ref, ref     modulo
IR_POW        ref, ref     power
IR_NEG        ref, ref     negate
IR_ABS        ref, ref     absolute value
IR_LDEXP      ref, ref     ldexp (scale by power of 2)
IR_MIN        ref, ref     minimum
IR_MAX        ref, ref     maximum
IR_FPMATH     ref, lit     FP math (sqrt, log, floor, ceil, trunc, sin, cos, ...)
```

### Overflow-checking arithmetic
```
IR_ADDOV [CW] ref, ref     addition + overflow check (guard)
IR_SUBOV [NW] ref, ref     subtraction + overflow check
IR_MULOV [CW] ref, ref     multiplication + overflow check
```

### Memory references
```
IR_AREF       ref, ref     array element reference (base + index*scale)
IR_HREFK      ref, ref     hash reference, key is constant
IR_HREF       ref, ref     hash reference, key is variable
IR_NEWREF     ref, ref     new hash reference (allocates slot)
IR_UREFO      ref, lit     open upvalue reference
IR_UREFC      ref, lit     closed upvalue reference
IR_FREF       ref, lit     field reference (struct field by FLOAD index)
IR_TMPREF     ref, lit     temporary reference (call arg/result)
IR_STRREF     ref, ref     string reference (string + offset)
IR_LREF       ___, ___     local reference (frame slot)
```

### Loads
```
IR_ALOAD      ref, ___     array load (from AREF)
IR_HLOAD      ref, ___     hash load (from HREF/HREFK)
IR_ULOAD      ref, ___     upvalue load (from UREFO/UREFC)
IR_FLOAD      ref, lit     field load (from GCobj at offset lit)
IR_XLOAD      ref, lit     external load (from pointer at offset lit)
IR_SLOAD      lit, lit     stack slot load (from slot index lit)
IR_VLOAD      ref, lit     variant load (tagged union field)
IR_ALEN       ref, ref     array length
```

### Stores
```
IR_ASTORE     ref, ref     array store
IR_HSTORE     ref, ref     hash store
IR_USTORE     ref, ref     upvalue store
IR_FSTORE     ref, ref     field store
IR_XSTORE     ref, ref     external store (to pointer)
```

Load/Store delta: `IR_XSTORE - IR_XLOAD == IR_ASTORE - IR_ALOAD` — stores
are at a fixed offset from their corresponding loads.

### Allocations
```
IR_SNEW       ref, ref     string new (CSE-safe)
IR_XSNEW      ref, ref     string new (allocating, not CSE-safe)
IR_TNEW       lit, lit     table new (hash size, array size)
IR_TDUP       ref, ___     table dup (from template)
IR_CNEW       ref, ref     cdata new (ctype + size)
IR_CNEWI      ref, ref     cdata new immutable (CSE-safe)
```

### Buffers
```
IR_BUFHDR     ref, lit     buffer header (reset/append/write)
IR_BUFPUT     ref, ref     buffer put (write data)
IR_BUFSTR     ref, ref     buffer to string
```

### Barriers (GC write barriers)
```
IR_TBAR       ref, ___     table barrier (after table store)
IR_OBAR       ref, ref     object barrier (upvalue/store to GC object)
IR_XBAR       ___, ___     external barrier (general GC barrier)
```

### Type conversions
```
IR_CONV       ref, lit     type conversion (source type→dest type encoded in lit)
IR_TOBIT      ref, ref     convert to bit (force integer bits view)
IR_TOSTR      ref, lit     convert to string (int, num, or char mode)
IR_STRTO      ref, ___     string to number
```

### Calls
```
IR_CALLN      ref, lit     call (normal, returns ref)
IR_CALLA      ref, lit     call (allocating, may allocate GC objects)
IR_CALLL      ref, lit     call (lowering: unresolved target)
IR_CALLS      ref, lit     call (side-effect only, no return value)
IR_CALLXS     ref, ref     call (external side-effect, variable args)
IR_CARG       ref, ref     call argument (pairs argument with call)
```

---

## IR modes

Each opcode has a 4-bit mode field encoding operand behavior:

```
IRMref   = 0  — operand is an IR reference
IRMlit   = 1  — operand is a 16-bit literal
IRMcst   = 2  — operand is a constant (int, GCref, or pointer)
IRMnone  = 3  — operand is unused

Mode bits (upper):
  IRM_C   = 0x10  — commutative (op1 and op2 can be swapped)
  IRM_N   = 0x00  — normal (no allocation, no load, no store)
  IRM_A   = 0x20  — allocating (may trigger GC)
  IRM_L   = 0x40  — load (reads memory)
  IRM_S   = 0x60  — store (writes memory, side-effect)
  IRM_W   = 0x80  — weak guard (may be eliminated if type is known)
```

The mode determines which optimizations apply: CSE works on non-allocating
non-storing ops, DCE skips side-effecting ops, stores can be sunk to exit
stubs, etc.

---

## IR type system

```
IRT_NIL     = 0    4 bytes    nil
IRT_FALSE   = 1    4 bytes    false
IRT_TRUE    = 2    4 bytes    true
IRT_LIGHTUD = 3    8/4 bytes  lightuserdata (64-bit on LJ_64)
IRT_STR     = 4    PGCSize    string (GC object)
IRT_P32     = 5    4 bytes    32-bit pointer (internal, never in TValue)
IRT_THREAD  = 6    PGCSize    thread (GC object)
IRT_PROTO   = 7    PGCSize    prototype (GC object)
IRT_FUNC    = 8    PGCSize    function (GC object)
IRT_P64     = 9    8 bytes    64-bit pointer (internal)
IRT_CDATA   = 10   PGCSize    cdata (GC object)
IRT_TAB     = 11   PGCSize    table (GC object)
IRT_UDATA   = 12   PGCSize    userdata (GC object)
IRT_FLOAT   = 13   4 bytes    single-precision float
IRT_NUM     = 14   8 bytes    double-precision float
IRT_I8      = 15   1 byte     signed 8-bit integer
IRT_U8      = 16   1 byte     unsigned 8-bit integer
IRT_I16     = 17   2 bytes    signed 16-bit integer
IRT_U16     = 18   2 bytes    unsigned 16-bit integer
IRT_INT     = 19   4 bytes    signed 32-bit integer
IRT_U32     = 20   4 bytes    unsigned 32-bit integer
IRT_I64     = 21   8 bytes    signed 64-bit integer
IRT_U64     = 22   8 bytes    unsigned 64-bit integer
IRT_SOFTFP  = 23   4 bytes    soft-float (internal, on non-FP archs)

IRT_PTR     = IRT_P64 or IRT_P32   (native pointer)
IRT_INTP    = IRT_I64 or IRT_INT   (pointer-sized integer)

Type flags (in upper bits of the type byte):
  IRT_MARK   = 0x20    marker for optimization passes
  IRT_ISPHI  = 0x40    PHI operand marker (loop-carried dependency)
  IRT_GUARD  = 0x80    guard flag (instruction is a guard)
```

Type checking predicates: `irt_isint(t)`, `irt_isnum(t)`, `irt_isgcv(t)`,
`irt_isinteger(t)` (I8 through INT), `irt_isaddr(t)` (pointer or GC obj),
`irt_is64(t)` (any 64-bit type), `irt_isfp(t)` (FLOAT or NUM).

---

## Trace structure

```text
GCtrace (one per compiled trace):

  ir[REF_BIAS..REF_BIAS+nins]    IR instruction buffer
    [REF_BIAS-1] = REF_NIL       (sentinel)
    [REF_BIAS]   = REF_BASE      (root sentinel)
    [REF_BIAS+1] = first real IR (typically IR_KPRI or guard)

  snap[0..nsnap-1]               Snapshot array (one per guard)
  snapmap[0..nsnapmap-1]         Snapshot map (what to restore at each exit)

  mcode[0..szmcode]              Compiled machine code
  mcloop                         Offset of loop back-edge in mcode

  startpc                        Bytecode PC where trace starts
  startpt                        Prototype containing startpc

  traceno                        This trace's number
  link                           Linked trace (or self for root-loop traces)
  root                           Root trace (0 for root, parent# for side)
  nextroot                       Next root trace in prototype chain
  nextside                       Next side trace in root's chain
  nchild                         Number of child (side) traces

  linktype:
    LJ_TRLINK_NONE     incomplete trace
    LJ_TRLINK_ROOT     root trace, linked to self (loop)
    LJ_TRLINK_LOOP     root trace, linked to another root trace
    LJ_TRLINK_TAILREC  root trace, linked through tail-recursion
    LJ_TRLINK_UPREC    root trace, linked through up-recursion
    LJ_TRLINK_STITCH   side trace, linked by stitching exit stub
```

### Trace topology

```text
Root trace (linktype = ROOT, link = self):
  ┌──────────────────────────────────────┐
  │  Guard: IR_LT  ra, rb               │ ← snapshot at this point
  │    if fail → exit stub → exit_handler │
  │  Guard: IR_NE  rc, rd               │ ← snapshot
  │    if fail → exit stub → exit_handler │
  │  ... body ...                        │
  │  IR_LOOP                             │ ← back edge, links to self
  └──────────────────────────────────────┘

Side trace (linktype = STITCH, root = parent, link = next):
  ┌──────────────────────────────────────┐
  │  IR_PVAL  parent_value              │ ← inherit state from parent
  │  IR_SLOAD slot, IRSLOAD_PARENT      │ ← coalesce stack slot from parent
  │  ... body ...                        │
  │  IR_LOOP                             │
  └──────────────────────────────────────┘

When side trace is compiled, the parent's exit stub is patched:
  Before: jmp vm_exit_handler
  After:  jmp side_trace.mcode         ← "stitching"
```

### Snapshot — exit state reconstruction

```text
SnapShot header:
  mapofs:  offset into snapmap array
  ref:     IR ref of the guard that owns this snapshot
  nslots:  number of stack slots captured
  nent:    number of entries in the snapshot map
  count:   exit count (heuristic for trace blacklisting)

SnapEntry (per slot):
  Bits encode what to restore:
    SNAP_NORESTORE    slot is dead, don't restore
    SNAP_SOFTFPNUM    slot holds a soft-float number
    SNAP_FRAME        slot is a frame link
    ref & 0xFFFF      restore from IR instruction at this index

On trace exit:
  1. Exit stub saves all live registers to ExitState
  2. vm_exit_handler calls lj_trace_exit(J, ex)
  3. lj_snap_replay walks snapmap, copies IR constants/values to Lua stack
  4. Interpreter resumes at the exit point
```

---

## Trace lifecycle

```text
Interpreter loop:
  hotcount[hash(PC)]--
  if hotcount == 0:
    lj_trace_hot(J, PC)
      → trace_start(J)
      → while recording:
          lj_record_ins(J)   // each bytecode → 1-5 IR insns + guards
          lj_snap_add(J)     // snapshot at guard points
      → trace_stop(J)
          lj_opt_fold(J)     // constant folding
          lj_opt_cse(J)      // common subexpression elimination
          lj_opt_dce(J)      // dead code elimination
          lj_opt_sink(J)     // sink stores to exit stubs
          lj_opt_split(J)    // split wide ops
          lj_opt_loop(J)     // detect loop-carried deps, insert PHI nodes
          asm_gen_trace(J,T) // register allocation + x64 codegen
      → patch bytecode: BC_LOOP → BC_JLOOP

Trace exit:
  guard fails → exit stub pushes exit# → vm_exit_handler
    → lj_trace_exit(J, ex)
        lj_snap_replay(J, T, ex)    // rebuild Lua stack
        if side trace exists:
          jump to stitched side trace
        else:
          try lj_trace_hot(J, exit_PC)  // record side trace
          if success: link + stitch
          else: fall back to interpreter
```

---

## Moonlift → IR lowering map

```text
Moonlift                              LuaJIT IR
────────                              ─────────

let x: i32 = 42                       IR_KINT 42
let y: i32 = x + 1                    IR_ADD  INT  x, IR_KINT 1
let z: i32 = x - y                    IR_SUB  INT  x, y
let b: bool = x < y                   IR_LT  [G] INT  x, y      (guard)
let m: i32 = x * y                    IR_MUL  INT  x, y
let d: i32 = x / y                    IR_DIV  INT  x, y

let p: ptr(u8) = ...                  IR_KPTR / IR_KGC / IR_XLOAD
let v: u8 = p[0]                      IR_XLOAD  U8  p, 0
p[4] = v                              IR_XSTORE  p+4, v

let s: view(i32) = view(buf, n)       IR_XLOAD PTR buf, offset + IR_KINT n
let w: i32 = s[i]                     IR_XLOAD INT base, i*4
s[i] = 42                             IR_XSTORE base+i*4, IR_KINT 42

if cond then ... else ... end         IR_NE cond, 0 → GUARD → side trace

return region -> T                     root trace
entry start(...)                       IR_BASE + IR_SLOAD stack slots
  ... body ...
block done(result: T)                  side trace (stitched from exit)
  yield result                         IR_RETF  result
block error(code: i32)                 side trace
  yield -code

jump loop(i = i + 1)                   IR_PHI i, i_next → IR_LOOP

emit @{frag}(args; done = block)       inline frag IR + exit stitch to block

load(p: ptr(T))                        IR_XLOAD T, p
store(p: ptr(T), v)                    IR_XSTORE p, v + IR_TBAR/IR_XBAR (if GC)

extern func puts(s: ptr(u8)) -> i32    IR_CALLN puts, s
```

---

## Key invariants

1. **Guard alignment**: `IR_EQ ^ 1 == IR_NE`, `IR_LT ^ 1 == IR_GE`, `IR_LT ^ 4 == IR_ULT`.
   The recorder flips opcodes to express "opposite" conditions.

2. **Load/store delta**: `IR_XSTORE - IR_XLOAD == IR_ASTORE - IR_ALOAD`.
   A store opcode is always at a fixed offset from its load counterpart.

3. **REF ordering**: constants < REF_BIAS < instructions. `irref_isk(ref)` is
   just `ref < REF_BIAS`, enabling fast constant checks in CSE and DCE.

4. **Side effects**: any op with `IRM_S` (store), `IRM_A` (allocation), or
   the `IRT_GUARD` flag has side effects and cannot be eliminated by DCE.

5. **GC barriers**: every store to a GC-tracked location must be followed by
   a barrier (TBAR for tables, OBAR for objects, XBAR for external).

6. **PHI nodes**: loop-carried values get a PHI(node_first_iteration, node_loop_backedge).
   The `IRT_ISPHI` flag marks operands that participate in PHIs.

7. **SINK**: stores to Lua stack slots can be sunk to exit stubs — the store
   only executes if the guard actually exits, not on the fast path.
