# Moonlift Backend: LuaJIT Cranelift Machine

**Status:** target design. Replaces `src/lib.rs` (Rust/Cranelift) with a pure
LuaJIT backend. The BackCmd tape is lowered to Lua source text, which LuaJIT
traces into native machine code.

## 1. Architecture

```
BackCmd tape (flat, verified, type-checked)
        │
        ▼
  back_luajit.lua          ← NEW: ~500 LOC
        │
  Lua source string
        │
  loadstring() → Lua function
        │
  LuaJIT tracer → x86-64 / ARM64 machine code
```

No Rust binary. No dynamic library. No Cranelift dependency. The entire
Moonlift compiler chain (parse → typecheck → lower → BackCmd → native)
runs inside LuaJIT.

## 2. The transformation

For every BackCmd variant, emit a short Lua statement. The BackCmd tape is a
flat array; the code generator walks it linearly and emits Lua source lines
into a buffer.

### 2.1 Program skeleton

```lua
-- Template for a BackProgram with N BackValIds and M BackBlockIds
local function make_back_program(program)
    local buf = {"local function compiled("}
    
    -- Entry params become function arguments
    -- (discovered from CmdBeginFunc + CmdBindEntryParams)
    
    -- Declare all BackValIds as locals
    for _, vid in ipairs(program.value_ids) do
        buf[#buf+1] = "local " .. lua_name(vid) .. "\n"
    end
    
    -- Generate code for each BackCmd
    for _, cmd in ipairs(program.cmds) do
        emit_cmd(buf, cmd, program)
    end
    
    buf[#buf+1] = "\nend"
    local src = table.concat(buf)
    return assert(loadstring(src))()
end
```

### 2.2 Command lowering

Each BackCmd variant emits 1-5 lines of Lua. The mapping is direct:

| BackCmd | Lua output |
|---------|-----------|
| `ConstInt(v, I32, "42")` | `vid = 42` |
| `ConstFloat(v, F64, "3.14")` | `vid = 3.14` |
| `Iadd(v, I32, wrap, a, b)` | `vid = va + vb` |
| `Isub(v, I32, wrap, a, b)` | `vid = va - vb` |
| `Imul(v, I32, wrap, a, b)` | `vid = va * vb` |
| `Sdiv(v, I32, wrap, a, b)` | `vid = math.floor(va / vb)` |
| `IcmpEq(v, I32, a, b)` | `vid = (va == vb)` |
| `IcmpSLt(v, I32, a, b)` | `vid = (va < vb)` |
| `Band(v, I32, a, b)` | `vid = bit.band(va, vb)` |
| `Bor(v, I32, a, b)` | `vid = bit.bor(va, vb)` |
| `Ishl(v, I32, a, b)` | `vid = bit.lshift(va, vb)` |
| `Sshr(v, I32, a, b)` | `vid = bit.arshift(va, vb)` |
| `Ushr(v, I32, a, b)` | `vid = bit.rshift(va, vb)` |
| `Bitcast(v, F32, a)` | `vid = va` (same bits, different interpretation) |
| `Ireduce(v, I8, a)` | `vid = bit.band(va, 0xFF)` |
| `Sextend(v, I64, a)` | `vid = va` (Lua numbers are f64, no extend needed) |
| `Select(v, I32, cond, a, b)` | `vid = (vcond and va or vb)` |
| `Fadd(v, F64, strict, a, b)` | `vid = va + vb` |
| `Fsub(v, F64, strict, a, b)` | `vid = va - vb` |
| `Fmul(v, F64, strict, a, b)` | `vid = va * vb` |
| `Fdiv(v, F64, strict, a, b)` | `vid = va / vb` |
| `Sqrt(v, F64, a)` | `vid = math.sqrt(va)` |
| `LoadInfo(v, I32, addr, mem)` | `vid = addr[0]` |
| `StoreInfo(I32, addr, val, mem)` | `addr[0] = vval` |
| `PtrAdd(v, base, offset)` | `vid = base + (voffset * 4)` (or 1/2/4/8 based on pointee) |
| `Memcpy(dst, src, len)` | `ffi.copy(dst, src, vlen)` |
| `Memset(dst, byte, len)` | `ffi.fill(dst, vbyte, vlen)` |
| `Jump(block, args)` | `goto block_label` |
| `BrIf(cond, t_block, t_args, f_block, f_args)` | `if vcond then goto t_label else goto f_label end` |
| `ReturnVoid` | `return` |
| `ReturnValue(v)` | `return vv` |
| `Trap` | `error("trap")` |

### 2.3 Control blocks

BackBlockIds become LuaJIT `::label::` markers:

```lua
-- CmdCreateBlock(entry_block)
::entry_1::  -- LuaJIT label

-- CmdSwitchToBlock / CmdSealBlock — no Lua output needed (the label IS the block)

-- CmdJump(loop_block, {i_val, acc_val})
-- The args are already in the local variables; no passing needed since
-- we use mutable locals
goto loop_1
```

Because BackValIds are mutable Lua locals, jumps don't need to carry
arguments. The state is in the locals; `goto` preserves them.

### 2.4 Memory model

Stack slots and data objects are backed by `ffi.new("uint8_t[?]", size)` buffers.
Pointers are ffi pointer cdata values — the LuaJIT tracer already handles ffi
pointer dereferences with direct memory loads/stores.

```lua
-- CmdCreateStackSlot(slot, 16, 8) → 16 bytes, 8-aligned
local slot_ptr = ffi.new("uint8_t[?]", 16)   -- in the generated code

-- CmdStackAddr(val, slot)
vid = slot_ptr   -- now vid is an ffi pointer

-- CmdLoadInfo(result, I32, addr, mem_info) where addr type is I32*
vid = ffi.cast("int32_t*", vaddr)[0]   -- typed load, tracer emits MOV

-- Pointer arithmetic for arrays:
vid = vbase + vi * 4   -- int* arithmetic, tracer scales correctly
-- Or: use ffi.cast for typed indexing
vid = ffi.cast("int32_t*", vbase)[vi]  -- tracer handles the scale
```

### 2.5 Extern calls

Extern functions are declared via `ffi.cdef` during the cimport phase. In the
generated code, they're referenced by name:

```lua
-- CmdCallValueExtern(result, I32, extern_id, sig, {a, b})
vid = extern_cos(va)     -- ffi.cdef'd: double cos(double)
vid = extern_malloc(vn)  -- ffi.cdef'd: void* malloc(size_t)
```

The function pointer is resolved at Lua level — no symbol table needed.

### 2.6 Function calls (direct and indirect)

```lua
-- CmdCallValueDirect(result, scalar, func_id, sig, {a, b})
vid = compiled_func_va(vb)   -- call another compiled function in the same module

-- CmdCallValueIndirect(result, scalar, ptr_val, sig, {a, b})
-- ptr_val is an ffi function pointer
vid = ffi.cast("int32_t(*)(int32_t)", vptr)(va)
```

### 2.7 Complete example

Input BackCmd tape (simplified) for `int sum(int* xs, int n)`:

```
CreateSig(sig_sum, [Ptr, I32], [I32])
DeclareFuncExport(func_sum, sig_sum)
BeginFunc(func_sum)
CreateBlock(entry)
SwitchToBlock(entry)
BindEntryParams(entry, [xs, n])
CreateBlock(loop_hdr)
CreateBlock(loop_body)
CreateBlock(exit)
ConstInt(acc, I32, "0")
ConstInt(i, I32, "0")
Jump(loop_hdr)
SwitchToBlock(loop_hdr)
IcmpSLt(cond, I32, i, n)
BrIf(cond, loop_body, {}, exit, {})
SwitchToBlock(loop_body)
PtrAdd(addr, xs, i)
LoadInfo(tmp, I32, addr, ...)
Iadd(acc, I32, wrapping, acc, tmp)
ConstInt(one, I32, "1")
Iadd(i, I32, wrapping, i, one)
Jump(loop_hdr)
SwitchToBlock(exit)
ReturnValue(acc)
SealBlock(entry)
SealBlock(loop_hdr)
SealBlock(loop_body)
SealBlock(exit)
FinishFunc(func_sum)
FinalizeModule
```

Generated Lua output:

```lua
local function compiled_sum(_xs, _n)
    local _acc, _i, _cond, _tmp, _addr, _one

    -- entry block
    _acc = 0
    _i = 0

    ::loop_hdr::
    _cond = (_i < _n)
    if _cond then goto loop_body else goto exit_block end

    ::loop_body::
    -- xs[i]: pointer arithmetic, i is element index, xs is int32_t*
    _addr = _xs + _i * 4
    _tmp = _addr[0]         -- ffi.cast("int32_t*", _addr)[0]
    _acc = _acc + _tmp
    _one = 1
    _i = _i + _one
    goto loop_hdr

    ::exit_block::
    return _acc
end
```

LuaJIT traces `compiled_sum`. The `::loop_hdr::` → `::loop_body::` → back edge
is detected as a loop. The trace body contains: comparison, conditional branch,
pointer add, load, integer add, increment, backward branch.

## 3. Scalar semantics

Lua numbers are 64-bit floats (f64). Integer operations in the float range
(-2^53 to 2^53) are exact. Moonlift scalars map as:

| BackScalar | Lua representation | Notes |
|-----------|-------------------|-------|
| Bool | `true`/`false` | Comparisons return bool; conditionals use truthiness |
| I8, U8, I16, U16 | Lua number | Mask with `bit.band(v, 0xFF)` etc. after ops |
| I32, U32 | Lua number | Exact up to 2^53 |
| I64, U64 | `ffi.new("int64_t", v)` or LLVM cdata | For correctness when > 2^53; fallback to Lua number otherwise |
| F32, F64 | Lua number | f64 is exact; f32 needs rounding |
| Ptr | ffi pointer cdata | `ffi.new("uint8_t*")` or `ffi.cast("void*", ...)` |
| Index | Lua number | Pointer-sized integer |
| Void | nil | |

For I32/U32 operations, the tracer emits x86 `ADD`/`SUB`/`IMUL` directly when
it can prove no overflow. For values outside the exact integer range, explicit
masking is needed.

For I64, options:
1. Use `ffi.new("int64_t", v)` cdata — slower due to boxing, but correct
2. Use Lua numbers with masking — fast but loses precision above 2^53
3. Use two Lua numbers (lo/hi) — complex, only for rare cases

Default: use Lua numbers for I32/U32 (the common case), emit bit.band for
narrowing operations. I64 uses Lua numbers with a correctness note.

## 4. Memory model

### 4.1 Stack slots

BackCmd stack slots become `ffi.new("uint8_t[?]", size)` allocations at
function entry. The slot pointer is stored in a local.

### 4.2 Global data

BackCmd data objects (string literals, static initializers) become module-level
`ffi.new` allocations. DataAddr returns the pointer.

### 4.3 Memory access flags

The BackMemoryInfo flags (alignment, trap behavior, motion) are ignored in
the LuaJIT backend — the tracer handles them naturally. `MayTrap` accesses in
Cranelift become ffi dereferences in LuaJIT, which the tracer also handles
(with a guard on nil/null).

## 5. Function calls

### 5.1 Direct calls (Moonlift → Moonlift)

A `CmdCallValueDirect` targeting another compiled function in the same module
becomes a direct Lua call:

```lua
vid = compiled_other(va, vb)
```

The callee is already a Lua function (compiled from another BackProgram). No
ABI boundary.

### 5.2 Extern calls (Moonlift → C)

A `CmdCallValueExtern` targeting a C symbol becomes an ffi call:

```lua
vid = ffi.C.malloc(vn)       -- for libc functions
vid = lib_math.cos(va)       -- for dynamically loaded libraries
```

The function must be registered with `ffi.cdef` during the cimport phase.

### 5.3 Indirect calls

`CmdCallValueIndirect` with a function pointer value:

```lua
vid = ffi.cast("int32_t(*)(int32_t)", vptr)(va)
```

## 6. Integration with the pipeline

The `back_luajit` module replaces both `back_jit.lua` and `src/lib.rs`:

```lua
-- lua/moonlift/back_luajit.lua
local M = {}

function M.Define(T)
    local Back = T.MoonBack
    
    local function compile(program)
        assert(pvm.classof(program) == Back.BackProgram)
        local src = generate_source(program)
        local fn = assert(loadstring(src))()
        return fn
    end
    
    return { compile = compile }
end
```

Usage in `host_module_values.lua`:

```lua
-- Before:
local Jit = require("moonlift.back_jit")
local jit_api = Jit.Define(T)
local artifact = jit_api.jit():compile(program)

-- After:
local BackLuaJIT = require("moonlift.back_luajit")
local backend = BackLuaJIT.Define(T)
local fn = backend.compile(program)  -- returns a callable Lua function
```

No artifact, no `:getpointer()`, no `:free()`. Just a Lua function.

## 7. Comparison with Cranelift backend

| | Cranelift (src/lib.rs) | LuaJIT machine (back_luajit.lua) |
|---|---|---|
| Dependency | Rust toolchain + cranelift crates | LuaJIT only |
| Compilation time | Cranelift IR → machine code | Lua source gen + LuaJIT trace |
| Code quality | Cranelift optimizer passes | LuaJIT tracer + backend |
| Control flow | Cranelift blocks | LuaJIT `goto`/`::label::` traces |
| Regalloc | Cranelift regalloc | LuaJIT SSA + regalloc (via tracer) |
| Integer semantics | Exact (i8/i16/i32/i64) | Lua number (f64) with masking |
| I64 | Native | Ffi cdata or f64 with precision loss above 2^53 |
| Floats | IEEE 754 strict | Lua f64 (x86 SSE) |
| Size | ~6000 LOC Rust | ~500 LOC Lua |
| Build | `cargo build` (minutes) | `require()` (instant) |
| Object emission | `.o` / `.so` via cranelift-object | Not available (pure JIT) |

## 8. Limitations

- **No object emission.** The LuaJIT backend is JIT-only. For `.o`/`.so` output,
  the Cranelift backend is still needed.
- **I64 precision.** Values > 2^53 lose precision. For correct I64, use
  `ffi.new("int64_t")` cdata (slower) or keep the Cranelift backend.
- **No struct-by-value ABI planning.** The Cranelift backend handles aggregate
  passing through ABI plans. The LuaJIT backend passes aggregates through
  memory (pointer + memcpy).
- **FFI dependency.** Requires LuaJIT FFI for pointer operations and C calls.
  Plain Lua 5.1/5.2/5.3 is not sufficient.

## 9. Implementation

The `back_luajit.lua` module:

```lua
-- ~500 LOC
-- Phase 1: collect all BackValIds, BackBlockIds, BackSigIds, BackExternIds
-- Phase 2: assign Lua local names to each BackValId
-- Phase 3: emit Lua source line per BackCmd
-- Phase 4: loadstring → function → return

local function compile(program)
    local ids = collect_ids(program)
    local locals = assign_names(ids)
    local buf = {"local function compiled("}
    
    -- Entry params
    buf[#buf+1] = table.concat(ids.entry_params, ", ")
    buf[#buf+1] = ")\n"
    
    -- Locals
    for _, name in ipairs(locals) do
        buf[#buf+1] = "local " .. name .. "\n"
    end
    
    -- Commands
    for _, cmd in ipairs(program.cmds) do
        emit_cmd(buf, cmd, locals, ids)
    end
    
    buf[#buf+1] = "\nend"
    return assert(loadstring(table.concat(buf)))()
end
```

The `emit_cmd` function is a simple dispatch table: `cmd_handlers[cmd._variant](buf, cmd, locals, ids)`.

## 10. Project impact

This backend removes the Rust/Cranelift dependency entirely for JIT mode.
Moonlift becomes a single-file LuaJIT application:

```
moonlift.lua  (or init.lua orchestrating the modules)
  ├── pvm.lua                 1335 LOC
  ├── asdl_context.lua         734 LOC
  ├── triplet.lua             1179 LOC
  ├── c/  (C frontend)        8228 LOC
  ├── back_luajit.lua         ~500 LOC   ← NEW
  ├── tree_typecheck.lua       ...
  ├── tree_to_back.lua         ...
  └── ...
```

No `moonlift.so`. No `cargo build`. No Cranelift. Pure LuaJIT from parse
to native code.

For production use (`.o`/`.so` emission, I64 correctness, aggregate ABI),
the Cranelift backend is retained as the `back_jit` / `back_object` path.
The LuaJIT backend is the fast-iteration development backend and the
pure-LuaJIT deployment backend.
