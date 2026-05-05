# LuaJIT Tape Machine Design

## Architecture

```
BackProgram tape
      │
      ▼
  tape_encode.lua          ← encode cmds → flat array of {tag, ...arg}
      │
      ▼
  machine_exec.lua         ← gen/param/ctrl triplet, for-loop
      │
      ▼
  LuaJIT tracer → x86-64 native
```

Two phases:
1. **Encode**: walk BackProgram, resolve block labels → PC, flatten variant
   tree into integer tags, produce `{tape, reg_names, entry_pc}`
2. **Execute**: `for pc in tape_gen, machine, entry_pc do end`

## 1. Tape format

Every BackCmd becomes one tuple: `{TAG, ...fields}`. Fields are either
register indices (integers), immediate values (strings/numbers), or PC
targets (integers). No ASDL objects survive encoding — everything is plain
Lua tables.

### Tag space

Flatten the variant tree. Each distinct BackCmd variant gets a tag.
Sub-variants (opcodes, scalar types) are also flattened — no secondary
dispatch.

```lua
T = {
    -- Constants
    CONST_INT  = 1,     -- {T.CONST_INT, dst_reg, raw_string}
    CONST_FLT  = 2,     -- {T.CONST_FLT, dst_reg, raw_string}
    CONST_BOOL = 3,     -- {T.CONST_BOOL, dst_reg, 0_or_1}

    -- Integer arithmetic (one tag per op)
    IADD       = 10,    -- {T.IADD, dst_reg, lhs_reg, rhs_reg}
    ISUB       = 11,    -- {T.ISUB, dst_reg, lhs_reg, rhs_reg}
    IMUL       = 12,
    SDIV       = 13,
    UDIV       = 14,
    SREM       = 15,
    UREM       = 16,

    -- Bitwise
    BAND       = 20,    -- {T.BAND, dst_reg, lhs_reg, rhs_reg}
    BOR        = 21,
    BXOR       = 22,
    BNOT       = 23,    -- {T.BNOT, dst_reg, src_reg}
    ISHL       = 24,
    SSHR       = 25,
    USHR       = 26,
    ROTL       = 27,
    ROTR       = 28,

    -- Float
    FADD       = 30,
    FSUB       = 31,
    FMUL       = 32,
    FDIV       = 33,

    -- Comparisons (boolean result → dst_reg = 0 or 1)
    ICMP_EQ    = 40,    ICMP_NE = 41,
    SCMP_LT    = 42,    SCMP_LE = 43,    SCMP_GT = 44,    SCMP_GE = 45,
    UCMP_LT    = 46,    UCMP_LE = 47,    UCMP_GT = 48,    UCMP_GE = 49,
    FCMP_EQ    = 50,    FCMP_NE = 51,
    FCMP_LT    = 52,    FCMP_LE = 53,    FCMP_GT = 54,    FCMP_GE = 55,

    -- Casts
    BITCAST    = 60,    -- {T.BITCAST, dst_reg, src_reg, enc_type}
    IREDUCE    = 61,    -- {T.IREDUCE, dst_reg, src_reg, mask_constant}
    SEXTEND    = 62,
    UEXTEND    = 63,
    FPROMOTE   = 64,
    FDEMOTE    = 65,
    STOF       = 66,
    UTOF       = 67,
    FTOS       = 68,
    FTOU       = 69,

    -- Unary
    INEG       = 70,    FNEG = 71,
    BOOLNOT    = 72,

    -- Intrinsics
    POPCOUNT   = 80,    CLZ = 81,    CTZ = 82,    BSWAP = 83,
    SQRT       = 84,    ABS = 85,    FLOOR = 86,  CEIL = 87,
    TRUNC      = 88,    ROUND = 89,

    -- Control flow
    JUMP       = 100,   -- {T.JUMP, dest_pc}
    BR_IF      = 101,   -- {T.BR_IF, cond_reg, then_pc, else_pc}
    SWITCH     = 102,   -- {T.SWITCH, val_reg, default_pc, {raw→pc, ...}}
    RETURN     = 103,   -- {T.RETURN, result_reg (0 if void)}
    TRAP       = 104,

    -- Memory
    LOAD       = 110,   -- {T.LOAD, dst_reg, addr_reg, elem_size, is_signed}
    STORE      = 111,   -- {T.STORE, addr_reg, value_reg, elem_size}
    PTR_ADD    = 112,   -- {T.PTR_ADD, dst_reg, base_reg, idx_reg, elem_size, const_off}
    MEMCPY     = 113,   -- {T.MEMCPY, dst_reg, src_reg, len_reg}
    MEMSET     = 114,   -- {T.MEMSET, dst_reg, byte_reg, len_reg}

    -- Stack / data
    STACK_ADDR = 120,   -- {T.STACK_ADDR, dst_reg, slot_size, slot_align}
    DATA_ADDR  = 121,   -- {T.DATA_ADDR, dst_reg, data_id}

    -- Calls
    CALL_DIR   = 130,   -- {T.CALL_DIR, result_reg, func_id_text, {arg_regs...}}
    CALL_EXT   = 131,   -- {T.CALL_EXT, result_reg, extern_id_text, {arg_regs...}}
    CALL_IND   = 132,   -- {T.CALL_IND, result_reg, callee_reg, sig_params, sig_ret}

    -- Value aliasing
    ALIAS      = 140,   -- {T.ALIAS, dst_reg, src_reg}  (copy on write)

    -- Select
    SELECT     = 150,   -- {T.SELECT, dst_reg, cond_reg, then_reg, else_reg}
    FMA        = 151,   -- {T.FMA, dst_reg, a_reg, b_reg, c_reg}

    -- Block params: assign jump args to block param registers
    BLOCK_ARG  = 160,   -- {T.BLOCK_ARG, param_reg, arg_reg}
}
```

### Register mapping

BackValId.text → integer register index. The encoder assigns sequential
indices during scan. `regs[i]` is the register value.

```lua
-- encoding phase
local reg_map = {}   -- val_id_text → integer index
local reg_count = 0
local reg_names = {} -- for debug

local function reg(id_text)
    if not reg_map[id_text] then
        reg_count = reg_count + 1
        reg_map[id_text] = reg_count
        reg_names[reg_count] = id_text
    end
    return reg_map[id_text]
end
```

### Block label → PC

During encoding, `CmdCreateBlock` records the tape position where the block
starts. `CmdSwitchToBlock` becomes a no-op (the position is implicit).
`CmdJump(dest)` and `CmdBrIf` reference the PC directly.

```lua
local block_pc = {}  -- block_id_text → tape index (1-based)
```

Note: the block body starts at the NEXT tape position after the
`CmdSwitchToBlock`. Jumps target that position.

### Entry params

`CmdBindEntryParams(block, {val_ids...})` — the entry block's params. On
function entry, the caller writes argument values into these registers
before starting the machine.

## 2. Machine execution

### gen function

One gen function per BackFunc. The shape:

```lua
local function make_gen(tape, narrow_ops)
    -- narrow_ops: array of {reg, mask} for post-op narrowing
    return function(machine, pc)
        local regs = machine.regs
        local cmd = tape[pc]
        local tag = cmd[1]
        
        if tag == T.CONST_INT then
            regs[cmd[2]] = tonumber(cmd[3])
            return pc + 1
        elseif tag == T.IADD then
            regs[cmd[3]] = regs[cmd[4]] + regs[cmd[5]]
            return pc + 1
        elseif tag == T.ISUB then
            regs[cmd[3]] = regs[cmd[4]] - regs[cmd[5]]
            return pc + 1
        ...
        elseif tag == T.JUMP then
            return cmd[2]
        elseif tag == T.BR_IF then
            return regs[cmd[2]] ~= 0 and cmd[3] or cmd[4]
        elseif tag == T.RETURN then
            machine._result = cmd[2] ~= 0 and regs[cmd[2]] or nil
            return nil  -- halt
        elseif tag == T.CALL_DIR then
            local fn = machine.funcs[cmd[3]]
            local args = {}
            for i = 1, #cmd[4] do args[i] = regs[cmd[4][i]] end
            local result = fn(unpack(args))
            if cmd[2] ~= 0 then regs[cmd[2]] = result end
            return pc + 1
        elseif tag == T.CALL_EXT then
            local fn = machine.externs[cmd[3]]
            local args = {}
            for i = 1, #cmd[4] do args[i] = regs[cmd[4][i]] end
            local result = fn(unpack(args))
            if cmd[2] ~= 0 then regs[cmd[2]] = result end
            return pc + 1
        elseif tag == T.LOAD then
            local addr = regs[cmd[3]]
            local ptr = ffi.cast(load_type(cmd[4], cmd[5]), addr)
            regs[cmd[2]] = ptr[0]
            return pc + 1
        ...
        elseif tag == T.BLOCK_ARG then
            regs[cmd[2]] = regs[cmd[3]]
            return pc + 1
        end
    end
end
```

### Execution loop

```lua
local function run_machine(gen, funcs, externs, entry_pc, entry_args)
    local regs = {}
    for _, arg in ipairs(entry_args or {}) do
        regs[arg.reg] = arg.value
    end
    
    local machine = {
        regs = regs,
        funcs = funcs,      -- fid_text → Lua function
        externs = externs,  -- eid_text → ffi function
        _result = nil,
    }
    
    -- The loop LuaJIT traces
    for pc in gen, machine, entry_pc do end
    
    return machine._result
end
```

The `for pc in gen, machine, entry_pc do end` is the trace loop. LuaJIT
traces the gen function with the loop. `pc` advances through the tape.
When gen returns nil, the loop ends.

### Narrowing

Integer narrowing (I32 → bit.band with 0xFFFFFFFF) is applied after
operations that may overflow. This is encoded as an additional tape
command, not a sub-dispatch:

```lua
-- After every IADD/ISUB/IMUL on I32, emit:
{ T.BAND, dst_reg, dst_reg, 0xFFFFFFFF }
```

Or as a post-op mask table checked inline:

```lua
local narrow = tape_post_ops[pc]  -- precomputed mask
if narrow then
    for _, n in ipairs(narrow) do
        regs[n[1]] = bit.band(regs[n[1]], n[2])
    end
end
```

The inline check is cleaner — the tracer can prove `narrow` is nil/empty
along the hot path and eliminate the branch.

## 3. Function calls

### Direct calls

`T.CALL_DIR` looks up the target function in `machine.funcs`, packs args from
registers, calls it as a Lua function, writes result back to register.

Self-calls work naturally — the function calls itself through the funcs
table. The outermost call returns when the gen loop halts.

### Extern calls

`T.CALL_EXT` looks up the extern in `machine.externs`. Externs are pre-built:

```lua
externs["malloc"] = ffi.cast("void*(*)(size_t)", ffi.C.malloc)
externs["cos"]    = ffi.C.cos
```

### Indirect calls

`T.CALL_IND` uses `ffi.cast` to convert a register value (function pointer)
into a callable function. The signature is encoded in the tape.

## 4. Module compilation

```lua
function compile(program)
    local externs = {}
    local funcs = {}
    
    -- Pass 1: build externs from CmdDeclareExtern
    -- Pass 2: encode each function body → {tape, entry_pc, entry_regs}
    -- Pass 3: compile each function via make_gen
    
    for fid, enc in pairs(encoded_funcs) do
        funcs[fid] = function(...)
            local entry_args = {}
            for i, reg_idx in ipairs(enc.entry_regs) do
                entry_args[i] = {reg = reg_idx, value = select(i, ...)}
            end
            return run_machine(enc.gen, funcs, externs, enc.entry_pc, entry_args)
        end
    end
    
    return funcs  -- table of fid_text → callable Lua function
end
```

Each call to a compiled function creates a fresh `regs` table and starts
the machine at the entry PC. Self-calls re-enter through `funcs[fid]`.

## 5. Block params and jump args

In the Cranelift model, `CmdAppendBlockParam(block, param_val, ty)` creates
a block parameter and binds it to a BackValId. `CmdJump(dest, {args...})`
passes values positionally. The Rust backend calls `builder.ins().jump(block,
&args)` which maps args to block params by position.

In the tape machine:
1. Block param registers are allocated like any other register
2. Before a jump, `T.BLOCK_ARG` commands copy jump args into block param regs
3. Then `T.JUMP` jumps to the block's PC

```lua
-- Before CmdJump(dest, {i_val, acc_val}):
--   T.BLOCK_ARG loop_i_reg, i_val_reg   → regs[loop_i] = regs[i_val]
--   T.BLOCK_ARG loop_acc_reg, acc_val_reg
--   T.JUMP loop_pc
```

This is the same pattern as `i = v5; acc = v6; goto loop` in the codegen
approach. The tracer sees the assignments followed by the jump back-edge
and treats `loop_i` and `loop_acc` as loop-carried values.

## 6. Why this traces well

LuaJIT's tracer sees:
```
for pc in gen, machine, entry_pc do end
   → trace entry at gen entry
   → cmd = tape[pc]; tag = cmd[1]
   → if tag == T.IADD then ... end  ← trace constant: tag == 10
   → pc = pc + 1
   → loop back to gen entry
```

The `tag` comparison chains compile away within a trace because `tape[pc][1]`
is constant for each PC position. The trace body is the straight-line
sequence of register operations. No dispatch overhead.

For loops: the `T.BLOCK_ARG + T.JUMP` sequence at the end of a loop body
assigns new values to block param registers and jumps back. The tracer
recognizes the back-edge and extends the trace. The block param registers
become loop-carried values in the trace — exactly like codegen.

## 7. Size estimate

- `tape_encode.lua`: ~150 lines (walk program, resolve blocks, flatten tags)
- `machine_exec.lua`: ~200 lines (gen function, run loop, narrowing)
- Total: ~350 lines

Vs current back_luajit.lua: ~670 lines (codegen + trampolines + save/restore)

The interpreter is half the size, no source generation, no trampoline bugs,
no block param ordering bugs. Each BackCmd maps directly to a tape tuple
and a dispatch branch.
