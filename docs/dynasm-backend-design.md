# DynASM Backend for MoonLift — Design

## 1. Thesis

The MoonLift compiler currently lowers the `BackCmd` IR to Cranelift IR and
then to machine code.  Cranelift is a full optimizing compiler — it does SSA
construction, global register allocation, instruction selection, loop analysis,
and ABI lowering.  It weighs ~400 kLOC and adds 30+ crates to the dependency
graph.

A DynASM backend replaces all of that with two things:

1. **A 500-line Lua module** that walks `BackCmd`, does linear-scan register
   allocation, and emits action-list bytecode.
2. **A 500-line C library** (`dasm_x86.h` compiled to a `.so`) that encodes
   action lists into executable machine code via its proven 3-pass engine.

The entire compilation pipeline moves into Lua running on the host LuaJIT.
No Rust.  No Cranelift.  The C encoding engine is a single `.h` file compiled
once into a shared library.

```
BackCmd IR (Vec<BackCmd>)
    │
    ▼
┌──────────────────────────────────────┐
│  Lua backend (moonlift/back/dasm.lua) │
│                                      │
│  1. liveness analysis                │
│  2. linear-scan register allocator   │
│  3. stack-frame layout               │
│  4. instruction selection            │
│  5. action-list builder              │
│                                      │
│  Output: action_list (string),       │
│          put_args (table of tables), │
│          globals (table),            │
│          labels (table)              │
└──────────────┬───────────────────────┘
               │ FFI
               ▼
┌──────────────────────────────────────┐
│  libdasm.so (dasm_x86.h compiled)    │
│                                      │
│  dasm_init()                         │
│  dasm_setupglobal()                  │
│  dasm_growpc()                       │
│  dasm_setup(actionlist)              │
│  dasm_put(start, regs..., labels...) │
│  dasm_link() → codesize              │
│  dasm_encode(buf) → machine code     │
└──────────────────────────────────────┘
```

---

## 2. Why This Is Simpler Than Cranelift

| Concern | Cranelift | DynASM |
|---|---|---|
| SSA construction | Required (FunctionBuilder) | Not needed — register allocator works on flat IR |
| Register allocation | Global, graph-coloring, spill-cost-model | Linear scan, ~60 lines of Lua |
| Instruction selection | Pattern-matching over CLIF IR | Direct 1:1 mapping from BackCmd |
| ABI lowering | Full platform ABI support | Manual prologue/epilogue per calling convention |
| Stack frame layout | Automatic | Manual, ~20 lines per arch |
| Branch shortening | Automatic | DynASM's pass 2 does it for free |
| Label resolution | Block-based CFG | DynASM's chain-based label system |
| Code emission | cranelift-codegen backend | dasm_encode() pass 3 |
| SIMD | Full | We'd need arch-specific lowering; deferred |
| Optimization passes | GVN, LICM, DCE, etc. | None — BackCmd is already optimized by the frontend |

The DynASM path trades away optimization for radical simplicity.  For
MoonLift's use case — compiling a LuaJIT-style trace compiler's IR — the
frontend already does the optimization.  The backend's job is just to emit
correct machine code quickly.  DynASM is a perfect fit.

---

## 3. The C Encoding Engine (libdasm.so)

We compile `dasm_x86.h` into a shared library.  This is a one-time build step
that produces `libdasm.so` (or `.dylib` on macOS).  The library exposes the
standard DynASM C API plus a few helpers.

### Source: `back/dasm_lib.c`

```c
#define DASM_CHECKS 1
#include "dasm_proto.h"
#include "dasm_x86.h"

// Memory hooks for the host allocator.
// DASM_M_GROW and DASM_M_FREE default to realloc/free,
// which is fine — we're in the host process.

// Extern resolution stub.  Actual resolution happens in Lua
// before dasm_encode.
int dasm_extern_stub(dasm_State **Dst, unsigned char *addr, int idx, int type) {
    (void)Dst; (void)addr; (void)idx; (void)type;
    return 0;  // Patched by Lua before encode
}
```

### Build

```bash
gcc -shared -fPIC -O2 \
    -I.vendor/LuaJIT/dynasm \
    -o libdasm.so back/dasm_lib.c
```

### FFI Bindings (Lua)

```lua
local ffi = require("ffi")

ffi.cdef[[
  typedef struct dasm_State dasm_State;
  void dasm_init(dasm_State **Dst, int maxsection);
  void dasm_free(dasm_State **Dst);
  void dasm_setupglobal(dasm_State **Dst, void **gl, unsigned int maxgl);
  void dasm_growpc(dasm_State **Dst, unsigned int maxpc);
  void dasm_setup(dasm_State **Dst, const void *actionlist);
  void dasm_put(dasm_State **Dst, int start, ...);
  int  dasm_link(dasm_State **Dst, size_t *szp);
  int  dasm_encode(dasm_State **Dst, void *buffer);
  int  dasm_getpclabel(dasm_State **Dst, unsigned int pc);
]]

local C = ffi.load("dasm")
```

---

## 4. The Action-List Builder (Lua)

The action list is a byte string.  DynASM's x86 action format is:

- **Bytes 0x00–0xE8**: Raw opcode bytes, emitted directly into the code buffer.
- **Bytes 0xE9–0xFF**: Action codes that trigger special encoding behavior.

We define a small set of builder primitives that produce action bytes and
collect the corresponding `dasm_put()` arguments.

### 4.1 Action codes we use

```
DISP     0xE9  — variable displacement (1 buffer pos)
IMM_S    0xEA  — signed byte immediate (1 buffer pos)
IMM_B    0xEB  — unsigned byte immediate (1 buffer pos)
IMM_W    0xEC  — unsigned word immediate (1 buffer pos)
IMM_D    0xED  — dword immediate (1 buffer pos)
IMM_WB   0xEE  — word immediate, branch-shrinkable (1 buffer pos)
IMM_DB   0xEF  — dword immediate, branch-shrinkable (1 buffer pos)
VREG     0xF0  — variable register (1 buffer pos)
REL_LG   0xF4  — local/global label relative (1 buffer pos + label arg)
IMM_LG   0xF6  — local/global label immediate (1 buffer pos + label arg)
LABEL_LG 0xF8  — define local/global label (1 buffer pos + label id)
ALIGN    0xFA  — alignment (1 buffer pos)
ESC      0xFC  — escape: next byte is raw opcode ≥ 0xE9
SECTION  0xFE  — switch section (terminal)
STOP     0xFF  — end of action fragment (terminal)
```

### 4.2 Builder API

```lua
-- Builder state
local B = {
    bytes = {},     -- accumulated action bytes (numbers 0-255)
    args  = {},     -- dasm_put args for the current fragment
    pos   = 1,      -- buffer positions used (max 25 per fragment)
    next_vreg = 0,  -- counter for allocating VREG slots
}

-- Emit a raw opcode byte.  If b >= 0xE9, wraps in ESC.
function B:raw(b)
    if b >= 0xE9 then
        self:byte(0xFC)  -- ESC
    end
    self:byte(b)
end

-- Emit a byte, no escaping.
function B:byte(b)
    self.bytes[#self.bytes + 1] = b
end

-- Emit a VREG reference.  Returns the arg index to use in dasm_put.
-- At encode time the register number (0-15) is OR'd into the preceding
-- template byte.
function B:vreg(kind)  -- kind: "rm", "reg", "base", "index", "opcode", "vex.v"
    self:byte(0xF0)    -- VREG action
    self:byte(KIND_BYTE[kind])  -- VREG sub-encoding
    local n = #self.args + 1
    self.args[n] = nil  -- placeholder, caller fills in register number
    self.pos = self.pos + 1
    return n
end

-- Emit a dword immediate (fixed value, not variable).
function B:imm32(value)
    self:raw(value & 0xFF)
    self:raw((value >> 8) & 0xFF)
    self:raw((value >> 16) & 0xFF)
    self:raw((value >> 24) & 0xFF)
end

-- Emit a signed byte immediate.
function B:imms8(value)
    if value < 0 then value = value + 256 end
    self:raw(value & 0xFF)
end

-- Emit a variable dword (value determined at dasm_put time).
-- Returns arg index.
function B:imm_d()
    self:byte(0xED)    -- IMM_D
    local n = #self.args + 1
    self.args[n] = nil
    self.pos = self.pos + 1
    return n
end

-- Emit a variable signed byte.
function B:imm_s()
    self:byte(0xEA)    -- IMM_S
    local n = #self.args + 1
    self.args[n] = nil
    self.pos = self.pos + 1
    return n
end

-- Emit a variable displacement (for ModRM memory operands).
function B:disp()
    self:byte(0xE9)    -- DISP
    local n = #self.args + 1
    self.args[n] = nil
    self.pos = self.pos + 1
    return n
end

-- Define a local label.
function B:label(id)
    self:byte(0xF8)    -- LABEL_LG
    self:byte(id)       -- local label number (1-9 fwd, 11-19 bkwd, or 10+ for globals)
    self.pos = self.pos + 1
end

-- Emit a relative reference to a local label.
-- Returns arg index for the label id.
function B:rel_lg(label_id)
    self:byte(0xF4)    -- REL_LG
    self:byte(label_id)
    local n = #self.args + 1
    self.args[n] = nil
    self.pos = self.pos + 2  -- REL_LG takes 2 buffer positions
    return n
end

-- Emit a variable displacement (like DISP, but for branch targets).
-- Same as REL_LG but used for explicit offset control.
function B:rel_label(arg_idx)
    self:byte(0xF4)    -- REL_LG
    self:byte(0)        -- placeholder, caller patches
    self.pos = self.pos + 2
end

-- End the current fragment.  Writes STOP.
function B:stop()
    self:byte(0xFF)    -- STOP
end

-- Start a new fragment (after flushing).
function B:flush()
    self:stop()
    -- The caller extracts self.bytes and self.args, then resets
end

-- Finalize: produce the packed action list string.
function B:finalize()
    return string.char(unpack(self.bytes))
end
```

### 4.3 How dasm_put is called

Each fragment (sequence of bytes ending in STOP) becomes one call:

```c
dasm_put(Dst, offset, arg1, arg2, ..., argN);
```

The `offset` is the byte offset into the action list where this fragment
begins.  The encoding engine reads the action bytes at `offset`, advances
through them, and consumes `arg1..argN` as dictated by the VREG/IMM/REL
actions.

At the Lua level, we accumulate all fragments' args into a single table:

```lua
local all_args = {}  -- concatenation of all fragment arg tables
local fragment_offsets = {}  -- start offset of each fragment
```

Then during encoding:

```lua
for i, offset in ipairs(fragment_offsets) do
    local frag_args = fragments[i].args
    -- dasm_put(Dst, offset, unpack(frag_args))
    C.dasm_put(Dst, offset, unpack(frag_args))
end
```

---

## 5. Register Allocation

We use linear-scan register allocation over the flat BackCmd instruction
stream.  This is possible because BackCmd is already in SSA-like form (each
BackValId is defined exactly once).

### 5.1 Register set (x64)

```
Caller-saved (usable by generated code):
  rax(0)  rcx(1)  rdx(2)  rsi(6)  rdi(7)  r8(8)  r9(9)  r10(10)  r11(11)

Callee-saved (require save/restore in prologue/epilogue):
  rbx(3)  rbp(5)  r12(12)  r13(13)  r14(14)  r15(15)

Reserved:
  rsp(4)  — stack pointer
  rbp(5)  — frame pointer (when used)
```

### 5.2 Algorithm

```lua
function allocate_registers(cmds)
    -- Pass 1: compute live intervals
    local intervals = {}  -- val_id → {first_use, last_use, reg, spilled}
    local active = {}     -- currently live intervals, sorted by last_use

    for i, cmd in ipairs(cmds) do
        -- Mark uses of values
        for _, val_id in uses(cmd) do
            if not intervals[val_id] then
                intervals[val_id] = {first = i, last = i}
            else
                intervals[val_id].last = i
            end
        end

        -- Mark definition
        local dst = def(cmd)
        if dst then
            intervals[dst] = {first = i, last = i}
        end
    end

    -- Pass 2: linear scan
    local free_regs = {0,1,2,6,7,8,9,10,11, 3,12,13,14,15}
    local spilled = {}   -- val_id → stack slot offset

    for i, cmd in ipairs(cmds) do
        -- Expire intervals that ended before this point
        expire_old_intervals(active, free_regs, i)

        -- Allocate register for the destination
        local dst = def(cmd)
        if dst then
            local reg = pop(free_regs)
            if reg then
                intervals[dst].reg = reg
                insert_sorted(active, intervals[dst])
            else
                -- Spill the interval with farthest last_use
                local victim = active[#active]
                spilled[victim.id] = allocate_stack_slot()
                intervals[dst].reg = victim.reg
                victim.reg = nil
                victim.spilled = true
                insert_sorted(active, intervals[dst])
            end
        end

        -- Record physical register assignments in the command
        annotate_cmd(cmd, intervals, spilled)
    end
end
```

### 5.3 Spill code insertion

When a value is spilled, we insert `LoadInfo`/`StoreInfo` commands before uses
and after definitions.  This is done as a post-pass over the annotated
commands.

```lua
-- After regalloc, for each cmd:
--   If cmd uses a spilled val_id: insert a LoadInfo from its stack slot
--     into a temporary register before this cmd.
--   If cmd defines a val_id that gets spilled: insert a StoreInfo to its
--     stack slot after this cmd.
```

### 5.4 Why linear scan works here

BackCmd is flat and the frontend already eliminates dead code.  Live ranges
are short because the IR is close to machine level.  In practice, 8–12
caller-saved registers are enough for most basic blocks without spilling.
When spilling does happen, the cost is a single load/store per value, which is
acceptable for a JIT backend.

---

## 6. Instruction Selection

Each `BackCmd` variant maps to a short sequence of x64 instructions.  The
lowering is architecture-specific but the pattern is regular.

### 6.1 Integer arithmetic (register → register)

```
Iadd(dst, ty, sem, lhs, rhs):
    if dst == lhs:
        ADD dst, rhs     ; REX.W 01 /r
    else:
        MOV dst, lhs     ; REX.W 89 /r
        ADD dst, rhs     ; REX.W 01 /r

Isub, Imul, Band, Bor, Bxor: same pattern with appropriate opcode
```

Encoding for `ADD r64, r/m64` (REX.W + 01 /r):
```
Byte 0: 0x48 | ((src_reg >> 3) << 2) | (dst_reg >> 3)   ; REX.W + R + B
Byte 1: 0x01                                               ; opcode
Byte 2: 0xC0 | ((src_reg & 7) << 3) | (dst_reg & 7)      ; ModRM (mod=11)
```

With VREG (for variable registers — used when register numbers aren't known
until dasm_put time):

```
Byte 0: 0x48                     ; REX.W with R=B=0 (template)
  VREG "vex.v", dst_vreg_slot   ; ORs dst>>3 into bit 2 of byte 0
  VREG "vex.v", src_vreg_slot   ; ORs src>>3 into bit 0 of byte 0
Byte 1: 0x01                     ; opcode
Byte 2: 0xC0                     ; ModRM template (reg=0, rm=0)
  VREG "modrm.reg", src_vreg     ; ORs (src & 7) << 3 into byte 2
  VREG "modrm.rm.r", dst_vreg    ; ORs (dst & 7) into byte 2
STOP
```

The VREG approach means we don't need to know register numbers at
action-list-build time.  We pass them as arguments to `dasm_put()`.

### 6.2 Constants

```
ConstInt(dst, ty, raw):
    if value fits in 32 bits:
        MOV dst, imm32    ; REX.W C7 /0 id
    else:
        MOVABS dst, imm64 ; REX.W B8+r io (special 10-byte form)
```

Encoding for `MOV r64, imm32` (sign-extending, 7 bytes):
```
Byte 0: 0x48 | ((dst_reg >> 3) << 2)    ; REX.W + B
Byte 1: 0xC7                             ; opcode
Byte 2: 0xC0 | (dst_reg & 7)             ; ModRM (mod=11, reg=0)
Bytes 3-6: imm32 (little-endian)
```

### 6.3 Memory operations

```
LoadInfo(dst, ty, addr, mem_info):
    MOV dst, [addr]      ; REX.W 8B /r

StoreInfo(ty, addr, val, mem_info):
    MOV [addr], val      ; REX.W 89 /r
```

With DISP action for variable offsets:

```
Byte 0: 0x48 | (dst>>3)<<2 | (base>>3)    ; REX.W + R + B
Byte 1: 0x8B                               ; MOV r64, r/m64
Byte 2: (dst&7)<<3 | (base&7)              ; ModRM (mod=00, unless disp≠0)
DISP offset_vreg                            ; variable displacement
STOP
```

### 6.4 Comparisons

```
IcmpEq(dst, ty, lhs, rhs):
    CMP lhs, rhs         ; REX.W 39 /r
    SETE al              ; 0F 94 C0
    MOVZX dst, al        ; REX.W 0F B6 /r

SIcmpLt(dst, ty, lhs, rhs):
    CMP lhs, rhs
    SETL al              ; 0F 9C C0
    MOVZX dst, al
```

### 6.5 Control flow

```
Jump(dest, args):
    JMP label_dest       ; E9 rel32 (or EB rel8 if near)

BrIf(cond, then_block, then_args, else_block, else_args):
    TEST cond, cond      ; 85 /r
    JNZ label_then       ; 0F 85 rel32
    JMP label_else       ; E9 rel32

SwitchInt(val, ty, cases, default):
    -- if ≤ 3 cases: chain of CMP/JE
    -- if > 3 cases: build jump table with indirect JMP [base + val*8]
```

Label resolution uses DynASM's REL_LG actions.  The linker's pass 2
automatically shortens JMP rel32 to JMP rel8 when the target is within 127
bytes.

### 6.6 Calls

```
CallValueDirect(dst, result_ty, func, sig, args):
    -- Move args into ABI registers (rcx, rdx, r8, r9 for Windows;
    --    rdi, rsi, rdx, rcx, r8, r9 for SysV)
    for i, arg in ipairs(args) do
        MOV abi_reg[i], arg
    end
    CALL func            ; E8 rel32 (or FF /2 for indirect)
    MOV dst, rax         ; capture return value

CallValueExtern(dst, result_ty, extern_id, sig, args):
    -- Same as direct, but func is an external symbol
    -- Resolved via DynASM's extern mechanism
```

---

## 7. Stack Frame Layout

Each compiled function manages its own stack frame.

```
        +──────────────────+
        │  return address   │  ← [rsp] on entry
        +──────────────────+
        │  saved rbp        │  ← after push rbp
        +──────────────────+
        │  saved callee-    │
        │  saved regs       │  (rbx, r12-r15 if used)
        +──────────────────+
        │  spill slots      │  (for values that didn't get registers)
        +──────────────────+
        │  locals /         │
        │  shadow space     │  (32 bytes for Windows x64 ABI)
        +──────────────────+  ← rsp after prologue
```

### Prologue (emitted at function entry)

```asm
push rbp
mov rbp, rsp
push rbx        ; if callee-saved regs are used
push r12
push r13
push r14
push r15
sub rsp, N      ; N = spill_area + shadow_space, 16-byte aligned
```

### Epilogue (emitted before each ReturnValue and ReturnVoid)

```asm
mov rsp, rbp    ; or: lea rsp, [rbp - saved_reg_bytes]
pop r15         ; reverse order
pop r14
pop r13
pop r12
pop rbx
pop rbp
ret
```

---

## 8. Module-Level Compilation

### 8.1 Data Objects

Data objects (from `DeclareData` + `DataInit*`) are allocated at compile time:

```lua
function compile_data(decl)
    local buf = ffi.new("uint8_t[?]", decl.size)
    -- Apply all DataInit operations
    for _, init in ipairs(decl.inits) do
        write_init(buf, init)
    end
    return buf  -- pointer to initialized memory
end
```

The address of each data object is registered as a global label:

```lua
C.dasm_setupglobal(Dst, globals_array, nglobals)
-- globals[data_idx] = data_buf
```

Then `DataAddr` is lowered to `LEA dst, [rip + global_label]`.

### 8.2 Function Compilation

```lua
function compile_module(program)
    -- Initialize DynASM state
    local Dst = ffi.new("dasm_State*[1]")
    C.dasm_init(Dst, 1)  -- 1 section (code)

    -- Setup globals for data objects and imported externs
    local nglobals = count_data_objects(program) + count_externs(program)
    local globals = ffi.new("void*[?]", nglobals)
    C.dasm_setupglobal(Dst, globals, nglobals)

    -- Setup PC labels for forward references between functions
    C.dasm_growpc(Dst, count_pc_labels(program))

    -- Build the action list
    local actionlist, fragments, label_map = build_actionlist(program)
    C.dasm_setup(Dst, actionlist)

    -- Feed actions
    for _, frag in ipairs(fragments) do
        C.dasm_put(Dst, frag.offset, unpack(frag.args))
    end

    -- Link and encode
    local sz = ffi.new("size_t[1]")
    C.dasm_link(Dst, sz)
    local buf = ffi.new("uint8_t[?]", sz[0])
    C.dasm_encode(Dst, buf)

    -- Extract function pointers
    local funcs = {}
    for _, decl in ipairs(program.exported_funcs) do
        funcs[decl.name] = globals[decl.global_idx]
    end

    return buf, sz[0], funcs
end
```

### 8.3 Multiple Functions in One Module

DynASM supports multiple sections.  We could compile each function in its own
section, then extract each section's code after linking.  Or we could compile
all functions into one code section and track their offsets via global labels:

```lua
-- In the action list:
--   LABEL_LG  func1_global
--   ... func1 code ...
--   LABEL_LG  func2_global
--   ... func2 code ...
```

After linking, `globals[func1_idx]` points to the start of func1.

---

## 9. Calling Conventions

### 9.1 SysV AMD64 ABI

| Arg | Register |
|---|---|
| 1 | rdi |
| 2 | rsi |
| 3 | rdx |
| 4 | rcx |
| 5 | r8 |
| 6 | r9 |
| 7+ | stack |

Return: rax (integer), xmm0 (float)

Caller-saved: rax, rcx, rdx, rsi, rdi, r8-r11, xmm0-xmm15
Callee-saved: rbx, rbp, r12-r15

Shadow space: none (SysV doesn't require it)

### 9.2 Windows x64 ABI

| Arg | Register |
|---|---|
| 1 | rcx |
| 2 | rdx |
| 3 | r8 |
| 4 | r9 |
| 5+ | stack |

Return: rax

Shadow space: 32 bytes (must be allocated even if no stack args)

### 9.3 Implementation

We detect the platform at module load time and select the appropriate ABI.
The ABI affects:

1. Which registers are used for incoming parameters (BindEntryParams).
2. Which registers are used for outgoing call arguments.
3. Whether shadow space is allocated.
4. The register allocation pool (which regs are caller-saved).

The ABI is encoded as a small configuration table:

```lua
local ABI = detect_abi()  -- "sysv" or "win64"

local PARAM_REGS = {
    sysv   = {7, 6, 2, 1, 8, 9},   -- rdi, rsi, rdx, rcx, r8, r9
    win64  = {1, 2, 8, 9},          -- rcx, rdx, r8, r9
}

local CALLER_SAVED = {
    sysv   = {0, 1, 2, 6, 7, 8, 9, 10, 11},
    win64  = {0, 1, 2, 8, 9, 10, 11},
}
```

---

## 10. Integration with MoonLift

### 10.1 Backend selection

The MoonLift frontend currently emits `BackCommandTape` text.  We add a
backend selector:

```lua
local backend = os.getenv("MOONLIFT_BACKEND") or "cranelift"

if backend == "dynasm" then
    return require("moonlift.back.dasm").compile(tape)
else
    return _host_compile(tape)
end
```

### 10.2 The `back/dasm.lua` module

```
moonlift/
  back/
    dasm.lua          -- entry point, compile(program)
    regalloc.lua      -- linear-scan register allocator
    x64/              -- x64-specific lowering
      encode.lua      -- action-list builder
      abi.lua         -- calling convention
      isel.lua        -- instruction selection (BackCmd → x64)
    arm64/            -- arm64-specific lowering (future)
      ...
```

### 10.3 What the frontend doesn't need to change

The BackCmd IR stays the same.  The frontend continues to emit the same
commands.  Only the backend consumer changes.  This means:

1. The existing Cranelift backend keeps working.
2. The DynASM backend is a drop-in replacement.
3. We can A/B test correctness and performance.

### 10.4 What goes away

When using the DynASM backend:
- No Rust compilation (no cargo build needed for codegen)
- No Cranelift dependency (~400 kLOC becomes 500 LOC of Lua + 500 LOC of C)
- No BackCommandTape serialization (the tape format exists only to cross the
  Lua→Rust boundary; with a pure Lua backend, we pass the BackCmd table
  directly)
- No `_host_compile` / `_host_symbol` machinery

---

## 11. Implementation Plan

### Phase 1: libdasm.so (1 day)

- Write `back/dasm_lib.c` (DASM_CHECKS, memory hooks, extern stub)
- Write Makefile rule to compile it
- Write Lua FFI bindings
- Test: call dasm_init/dasm_put/dasm_link/dasm_encode with a hand-crafted
  action list that produces `mov eax, 42; ret`

### Phase 2: Action-list builder (2 days)

- Implement the builder API from §4
- Implement x64 instruction encodings for: MOV, ADD, SUB, IMUL, CMP, TEST,
  JMP, Jcc, CALL, RET, LEA, PUSH, POP
- Test: build action list programmatically, encode, execute, verify result

### Phase 3: Register allocator (2 days)

- Implement linear-scan allocator from §5
- Implement spill code insertion
- Test on multi-instruction functions with register pressure

### Phase 4: BackCmd lowering (3 days)

- Implement instruction selection for all BackCmd variants
- Implement control flow: Jump, BrIf, SwitchInt
- Implement calls: CallValueDirect, CallValueExtern, CallStmt*
- Implement stack frame layout and prologue/epilogue
- Test with the existing BackCmd test suite (the Rust tests in lib.rs)

### Phase 5: Module compilation (1 day)

- Implement DeclareData/DataInit handling
- Implement function export (global labels)
- Implement extern resolution

### Phase 6: Integration (1 day)

- Wire into MoonLift's frontend
- Run existing test suite with both backends
- Benchmark: compile time and generated code quality vs. Cranelift

---

## 12. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Branch offset overflow (REL_LG range) | DynASM's pass 2 automatically switches JMP rel32 ↔ JMP rel8. For Jcc, we always emit the 6-byte form (0F 8x rel32) and let pass 2 shrink to 2 bytes when possible. |
| VREG limits (max buffer positions = 25) | Split long instruction sequences into multiple dasm_put fragments. Each fragment must fit in 25 buffer positions. This is checked by the builder. |
| Spill code explosion | Linear scan with spill-cost heuristics. In practice, MoonLift's traces are short enough that spilling is rare. |
| Float/vector operations | Deferred to phase 2. We can use scalar float instructions (MOVSS, ADDSS) for BackScalar::F32/F64. Vector ops need SIMD encoding — left for future work. |
| ABI differences (SysV vs Win64) | The ABI module is parameterized by a config table. We test on both platforms. |
| Debugging incorrect code | `MOONLIFT_DUMP_ASM=1` prints the generated assembly text. Compare against known-good Cranelift output. |
| Performance regression | Measure: if DynASM-generated code is >20% slower than Cranelift, fall back. Most of MoonLift's performance comes from the frontend (trace recording, optimization), not the backend. |

---

## 13. What We Get

1. **No Rust required for compilation**.  The entire compiler runs in LuaJIT.
   The only compiled artifact is `libdasm.so` (500 lines of C, build once).

2. **Radically simpler**.  ~1000 lines of Lua + ~500 lines of C replace
   ~400 kLOC of Cranelift + Rust infrastructure.

3. **Faster compilation**.  DynASM encoding is a linear pass over action
   bytes.  No SSA construction, no graph-coloring register allocation, no
   optimization passes.  Expect 10–50× faster compile times.

4. **Deterministic output**.  No heuristics, no phase-ordering issues.

5. **Existing investment preserved**.  The BackCmd IR, the Lua frontend, the
   test suite, and the .mlua source files all remain unchanged.

6. **Multi-architecture path**.  ARM64 uses the same design — just swap
   `dasm_x86.h` for `dasm_arm64.h` and write the ARM64 instruction selection
   module.  The register allocator and action-list builder are architecture-
   independent.
