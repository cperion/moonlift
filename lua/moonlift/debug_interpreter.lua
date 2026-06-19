-- moonlift/debug_interpreter.lua
-- Pure-Lua BackCmd[] interpreter for block-transition debugging.
-- Maintains a virtual register file, a flat address space for memory,
-- and pauses at block boundaries for stepping control.
--
-- Usage:
--   local Interpreter = require("moonlift.debug_interpreter")
--   local interp = Interpreter.new(cmds, { Back = Back, extrn = {...} })
--   interp:step_block()  -- step one block transition

local pvm = require("moonlift.pvm")

local M = {}

local Interpreter = {}
Interpreter.__index = Interpreter

--- Create a new interpreter instance.
-- @param cmds  BackCmd[] — the flat command stream
-- @param opts  table:
--   Back: MoonBack schema table (required)
--   extrn: {[name] = function} — extern FFI functions
--   functions: {[func_id_str] = BackCmd[]} — direct function bodies
--   memory_size: number — flat address space size (default 64MB)
-- @return Interpreter instance
function M.new(cmds, opts)
    opts = opts or {}
    local Back = opts.Back
    if not Back then
        error("moonlift.debug_interpreter: Back schema required")
    end

    local self = setmetatable({
        cmds = cmds,
        cursor = 1,
        cursor_limit = #cmds,
        registers = {},        -- BackValId.text → raw_value
        current_block = nil,   -- BackBlockId.text
        paused = false,
        terminated = false,
        return_value = nil,
        trap_reason = nil,
        pending_jump_target = nil,  -- {target_bid, args[]}
        extrn = opts.extrn or {},
        functions = opts.functions or {},
        call_stack = {},       -- [{cursor, registers, current_block}]
        pending_call_args = nil,
        -- Memory
        memory_size = opts.memory_size or (1024 * 1024 * 64),
        memory = nil,          -- ffi byte array
        memory_ptr = nil,      -- ffi cast uint8_t*
        stack_slots = {},      -- slot_id.text → {offset, size}
        next_stack_offset = 0,
        data_regions = {},     -- data_id.text → {offset, size}
        next_data_offset = 0,
        -- Block metadata
        switch_to_block_map = {},
        block_entry_indices = {},
        block_params = {},     -- bid → {param_val_id_text, ...}
        current_param_names = nil,  -- param names for current block
        -- Func map
        func_map = {},
        -- Stepping
        step_mode = "none",    -- "block" | "continue" | "none"
        breakpoints_fn = nil,  -- function(bid) → boolean
        event_handler = nil,   -- function(event_type, data)
        -- Back schema reference
        Back = Back,
    }, Interpreter)

    self:_init_memory()
    self:_build_block_map()
    self:_build_block_params_map()
    self:_build_func_map()
    self:_init_handlers()

    return self
end

--- Initialize the flat address space.
function Interpreter:_init_memory()
    local ffi = require("ffi")
    self.memory = ffi.new("uint8_t[?]", self.memory_size)
    self.memory_ptr = ffi.cast("uint8_t*", self.memory)
end

--- Build a map of block boundaries from the command stream.
function Interpreter:_build_block_map()
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == self.Back.CmdSwitchToBlock then
            local bid = cmd.block.text
            self.switch_to_block_map[i] = bid
            self.block_entry_indices[bid] = i
        end
    end
end

--- Build the block_params map by scanning for CmdAppendBlockParam commands.
function Interpreter:_build_block_params_map()
    local current_bid = nil
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == self.Back.CmdCreateBlock then
            current_bid = cmd.block.text
            self.block_params[current_bid] = {}
        elseif cls == self.Back.CmdAppendBlockParam then
            if current_bid then
                self.block_params[current_bid][
                    #self.block_params[current_bid] + 1] = cmd.value.text
            end
        end
    end
end

--- Build a map from BackFuncId to function body index range.
function Interpreter:_build_func_map()
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == self.Back.CmdBeginFunc then
            self.func_map[cmd.func.text] = { start_idx = i + 1, end_idx = nil }
        elseif cls == self.Back.CmdFinishFunc then
            local func = cmd.func.text
            if self.func_map[func] then
                self.func_map[func].end_idx = i - 1
            end
        end
    end
end

--- Initialize the handler dispatch table.
function Interpreter:_init_handlers()
    local Back = self.Back
    self._handlers = {}

    local handler_map = {
        [Back.CmdCreateSig] = "_handle_noop",
        [Back.CmdDeclareData] = "_handle_declare_data",
        [Back.CmdDataInitZero] = "_handle_data_init_zero",
        [Back.CmdDataInit] = "_handle_data_init",
        [Back.CmdDataAddr] = "_handle_data_addr",
        [Back.CmdFuncAddr] = "_handle_func_addr",
        [Back.CmdExternAddr] = "_handle_extern_addr",
        [Back.CmdDeclareFunc] = "_handle_noop",
        [Back.CmdDeclareExtern] = "_handle_noop",
        [Back.CmdBeginFunc] = "_handle_noop",
        [Back.CmdCreateBlock] = "_handle_noop",
        [Back.CmdSwitchToBlock] = "_handle_switch_to_block",
        [Back.CmdSealBlock] = "_handle_noop",
        [Back.CmdBindEntryParams] = "_handle_bind_entry_params",
        [Back.CmdAppendBlockParam] = "_handle_noop",
        [Back.CmdCreateStackSlot] = "_handle_create_stack_slot",
        [Back.CmdAlias] = "_handle_alias",
        [Back.CmdStackAddr] = "_handle_stack_addr",
        [Back.CmdConst] = "_handle_const",
        [Back.CmdUnary] = "_handle_unary",
        [Back.CmdIntrinsic] = "_handle_intrinsic",
        [Back.CmdCompare] = "_handle_compare",
        [Back.CmdCast] = "_handle_cast",
        [Back.CmdPtrOffset] = "_handle_ptr_offset",
        [Back.CmdSelect] = "_handle_select",
        [Back.CmdLoadInfo] = "_handle_load_info",
        [Back.CmdStoreInfo] = "_handle_store_info",
        [Back.CmdAtomicLoad] = "_handle_load_info",
        [Back.CmdAtomicStore] = "_handle_store_info",
        [Back.CmdAtomicRmw] = "_handle_noop",
        [Back.CmdAtomicCas] = "_handle_noop",
        [Back.CmdAtomicFence] = "_handle_noop",
        [Back.CmdIntBinary] = "_handle_int_binary",
        [Back.CmdBitBinary] = "_handle_bit_binary",
        [Back.CmdBitNot] = "_handle_bit_not",
        [Back.CmdShift] = "_handle_shift",
        [Back.CmdRotate] = "_handle_rotate",
        [Back.CmdFloatBinary] = "_handle_float_binary",
        [Back.CmdMemcpy] = "_handle_memcpy",
        [Back.CmdMemset] = "_handle_memset",
        [Back.CmdMemcmp] = "_handle_memcmp",
        [Back.CmdFma] = "_handle_fma",
        [Back.CmdVecSplat] = "_handle_noop",
        [Back.CmdVecBinary] = "_handle_noop",
        [Back.CmdVecCompare] = "_handle_noop",
        [Back.CmdVecSelect] = "_handle_noop",
        [Back.CmdVecMask] = "_handle_noop",
        [Back.CmdVecInsertLane] = "_handle_noop",
        [Back.CmdVecExtractLane] = "_handle_noop",
        [Back.CmdCall] = "_handle_call",
        [Back.CmdJump] = "_handle_jump",
        [Back.CmdBrIf] = "_handle_br_if",
        [Back.CmdSwitchInt] = "_handle_switch_int",
        [Back.CmdReturnVoid] = "_handle_return_void",
        [Back.CmdReturnValue] = "_handle_return_value",
        [Back.CmdTrap] = "_handle_trap",
        [Back.CmdFinishFunc] = "_handle_noop",
        [Back.CmdFinalizeModule] = "_handle_noop",
    }

    for cls, method_name in pairs(handler_map) do
        local method = Interpreter[method_name]
        if method then
            self._handlers[cls] = method
        end
    end
end

--- Allocate a chunk in the flat address space for data.
function Interpreter:_alloc_data(size, align)
    local offset = self.next_data_offset
    if align > 1 then
        offset = offset + (align - offset % align) % align
    end
    self.next_data_offset = offset + size
    return offset
end

--- Allocate a stack slot in the flat address space.
function Interpreter:_alloc_stack(size, align)
    local offset = self.next_stack_offset
    if align > 1 then
        offset = offset + (align - offset % align) % align
    end
    self.next_stack_offset = offset + size
    return offset
end

--- Resolve address from a BackAddress structure.
function Interpreter:_resolve_address(addr)
    local base_val = 0
    local bc = pvm.classof(addr.base)
    if bc == self.Back.BackAddrValue then
        base_val = self.registers[addr.base.value.text] or 0
    elseif bc == self.Back.BackAddrStack then
        local slot = self.stack_slots[addr.base.slot.text]
        base_val = slot and slot.offset or 0
    elseif bc == self.Back.BackAddrData then
        local region = self.data_regions[addr.base.data.text]
        base_val = region and region.offset or 0
    end
    local offset = self.registers[addr.byte_offset.text] or 0
    return base_val + offset
end

--- Scalar size in bytes.
function Interpreter:_scalar_size(scalar)
    local Back = self.Back
    if scalar == Back.BackBool or scalar == Back.BackI8 or scalar == Back.BackU8 then
        return 1
    elseif scalar == Back.BackI16 or scalar == Back.BackU16 then
        return 2
    elseif scalar == Back.BackI32 or scalar == Back.BackU32 or scalar == Back.BackF32 then
        return 4
    elseif scalar == Back.BackI64 or scalar == Back.BackU64 or scalar == Back.BackF64
           or scalar == Back.BackIndex or scalar == Back.BackPtr then
        return 8
    end
    return 4
end

--- Read a typed value from flat memory.
function Interpreter:_read_memory(addr, scalar)
    local ffi = require("ffi")
    if addr < 0 or addr + self:_scalar_size(scalar) > self.memory_size then
        return 0
    end
    local ptr = self.memory_ptr + addr
    local Back = self.Back
    if scalar == Back.BackBool then
        return ptr[0] ~= 0
    elseif scalar == Back.BackI8 then
        return ffi.cast("int8_t*", ptr)[0]
    elseif scalar == Back.BackU8 then
        return ptr[0]
    elseif scalar == Back.BackI16 then
        return ffi.cast("int16_t*", ptr)[0]
    elseif scalar == Back.BackU16 then
        return ffi.cast("uint16_t*", ptr)[0]
    elseif scalar == Back.BackI32 then
        return ffi.cast("int32_t*", ptr)[0]
    elseif scalar == Back.BackU32 then
        return ffi.cast("uint32_t*", ptr)[0]
    elseif scalar == Back.BackI64 or scalar == Back.BackIndex then
        return tonumber(ffi.cast("int64_t*", ptr)[0])
    elseif scalar == Back.BackU64 then
        return tonumber(ffi.cast("uint64_t*", ptr)[0])
    elseif scalar == Back.BackF32 then
        return ffi.cast("float*", ptr)[0]
    elseif scalar == Back.BackF64 then
        return ffi.cast("double*", ptr)[0]
    elseif scalar == Back.BackPtr then
        return tonumber(ffi.cast("uintptr_t*", ptr)[0])
    end
    return 0
end

--- Write a typed value to flat memory.
function Interpreter:_write_memory(addr, scalar, val)
    local ffi = require("ffi")
    if addr < 0 or addr + self:_scalar_size(scalar) > self.memory_size then
        return
    end
    local ptr = self.memory_ptr + addr
    local Back = self.Back
    if scalar == Back.BackBool then
        ptr[0] = val and 1 or 0
    elseif scalar == Back.BackI8 then
        ffi.cast("int8_t*", ptr)[0] = val
    elseif scalar == Back.BackU8 then
        ptr[0] = val
    elseif scalar == Back.BackI16 then
        ffi.cast("int16_t*", ptr)[0] = val
    elseif scalar == Back.BackU16 then
        ffi.cast("uint16_t*", ptr)[0] = val
    elseif scalar == Back.BackI32 then
        ffi.cast("int32_t*", ptr)[0] = val
    elseif scalar == Back.BackU32 then
        ffi.cast("uint32_t*", ptr)[0] = val
    elseif scalar == Back.BackI64 or scalar == Back.BackIndex then
        ffi.cast("int64_t*", ptr)[0] = val
    elseif scalar == Back.BackU64 then
        ffi.cast("uint64_t*", ptr)[0] = val
    elseif scalar == Back.BackF32 then
        ffi.cast("float*", ptr)[0] = val
    elseif scalar == Back.BackF64 then
        ffi.cast("double*", ptr)[0] = val
    elseif scalar == Back.BackPtr then
        ffi.cast("uintptr_t*", ptr)[0] = val
    end
end

--- Execute one command and advance cursor.
-- Returns true if execution should continue, false if paused or terminated.
function Interpreter:step()
    if self.terminated then return false end
    if self.cursor > self.cursor_limit then
        self.terminated = true
        return false
    end

    local cmd = self.cmds[self.cursor]
    local cls = pvm.classof(cmd)
    local handler = self._handlers[cls]
    if handler then
        handler(self, cmd)
    end

    -- Advance cursor
    self.cursor = self.cursor + 1

    if self.paused then return false end
    return not self.terminated
end

-- Step control API

--- Execute until the next block boundary.
-- @return block_id of the block we paused at, or nil if terminated
function Interpreter:step_block()
    self.step_mode = "block"
    self.paused = false
    while true do
        self:step()
        if self.paused then
            self.step_mode = "none"
            self.paused = false  -- reset for next operation
            if self.current_block then
                return self.current_block
            end
            -- Paused but no block yet — keep going
            self.step_mode = "block"
        elseif self.terminated then
            self.step_mode = "none"
            return nil
        end
    end
end

--- Execute until a breakpoint condition is met or termination.
-- @param breakpoints_fn  function(bid) → boolean: check breakpoints at block entry
-- @return {type="breakpoint", block=bid} or {type="terminated"}
function Interpreter:continue_until(breakpoints_fn)
    self.breakpoints_fn = breakpoints_fn
    self.step_mode = "continue"
    self.paused = false
    while true do
        local continued = self:step()
        if self.paused then
            self.paused = false  -- reset for next operation
            return { type = "breakpoint", block = self.current_block }
        end
        if self.terminated or not continued then
            return { type = "terminated" }
        end
    end
end

--- Pause execution at the next opportunity.
function Interpreter:pause()
    self.paused = true
end

--- Emit an event to the registered handler.
function Interpreter:emit_event(event_type, data)
    if self.event_handler then
        self.event_handler(event_type, data)
    end
end

-- Register accessors

function Interpreter:read_register(name)
    return self.registers[name]
end

function Interpreter:read_all_registers()
    local out = {}
    for k, v in pairs(self.registers) do
        out[k] = v
    end
    return out
end

-- Combine all registers into a flat view (for call stack copy)
function Interpreter:_copy_registers()
    local copy = {}
    for k, v in pairs(self.registers) do
        copy[k] = v
    end
    return copy
end

-- Bind block parameters from pending_jump_target args
function Interpreter:_bind_block_params(bid, args)
    local param_names = self.block_params[bid]
    if not param_names then return end
    for i = 1, #param_names do
        self.registers[param_names[i]] = args[i] or 0
    end
    self.current_param_names = param_names
end

-- Resolve jump args to actual values
function Interpreter:_resolve_args(arg_ids)
    local args = {}
    for i = 1, #arg_ids do
        local id = arg_ids[i]
        if type(id) == "string" then
            args[i] = self.registers[id] or 0
        else
            args[i] = self.registers[id.text] or 0
        end
    end
    return args
end

-- No-op handler for commands with no runtime effect
function Interpreter:_handle_noop(cmd) end

-- CmdConst: dst, ty, value (BackLiteral)
function Interpreter:_handle_const(cmd)
    local Back = self.Back
    local lit = cmd.value
    local lc = pvm.classof(lit)
    local val
    if lc == Back.BackLitInt then
        val = tonumber(lit.raw)
    elseif lc == Back.BackLitFloat then
        val = tonumber(lit.raw)
    elseif lc == Back.BackLitBool then
        val = lit.value
    elseif lc == Back.BackLitNull then
        val = 0
    else
        val = 0
    end
    self.registers[cmd.dst.text] = val
end

-- CmdIntBinary: dst, op, scalar, semantics, lhs, rhs
function Interpreter:_handle_int_binary(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local val
    local op = cmd.op
    if op == Back.BackIntAdd then
        val = lv + rv
    elseif op == Back.BackIntSub then
        val = lv - rv
    elseif op == Back.BackIntMul then
        val = lv * rv
    elseif op == Back.BackIntSDiv then
        val = rv ~= 0 and math.floor(lv / rv) or 0
    elseif op == Back.BackIntUDiv then
        val = rv ~= 0 and math.floor(lv / rv) or 0
    elseif op == Back.BackIntSRem then
        val = rv ~= 0 and (lv % rv) or 0
    elseif op == Back.BackIntURem then
        val = rv ~= 0 and (lv % rv) or 0
    else
        val = lv + rv
    end
    -- Truncate to scalar width
    local scalar = cmd.scalar
    if scalar == Back.BackI8 then
        val = ffi and require("ffi").cast("int8_t", val) or val
    elseif scalar == Back.BackI16 then
        val = ffi and require("ffi").cast("int16_t", val) or val
    elseif scalar == Back.BackI32 then
        val = ffi and require("ffi").cast("int32_t", val) or val
    end
    self.registers[cmd.dst.text] = val
end

-- CmdBitBinary: dst, op, scalar, lhs, rhs
function Interpreter:_handle_bit_binary(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local val
    local op = cmd.op
    local bit = require("bit")
    if op == Back.BackBitAnd then
        val = bit.band(lv, rv)
    elseif op == Back.BackBitOr then
        val = bit.bor(lv, rv)
    elseif op == Back.BackBitXor then
        val = bit.bxor(lv, rv)
    else
        val = lv
    end
    self.registers[cmd.dst.text] = val
end

-- CmdBitNot: dst, scalar, value
function Interpreter:_handle_bit_not(cmd)
    local v = self.registers[cmd.value.text] or 0
    local bit = require("bit")
    self.registers[cmd.dst.text] = bit.bnot(v)
end

-- CmdShift: dst, op, scalar, lhs, rhs
function Interpreter:_handle_shift(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local val
    local bit = require("bit")
    local op = cmd.op
    if op == Back.BackShiftLeft then
        val = bit.lshift(lv, rv)
    elseif op == Back.BackShiftLogicalRight then
        val = bit.rshift(lv, rv)
    elseif op == Back.BackShiftArithmeticRight then
        val = bit.arshift(lv, rv)
    else
        val = lv
    end
    self.registers[cmd.dst.text] = val
end

-- CmdRotate: dst, op, scalar, lhs, rhs
function Interpreter:_handle_rotate(cmd)
    -- Simplified: just shift for now
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local bit = require("bit")
    local val
    if cmd.op == Back.BackRotateLeft then
        val = bit.lshift(lv, rv)
    else
        val = bit.rshift(lv, rv)
    end
    self.registers[cmd.dst.text] = val
end

-- CmdFloatBinary: dst, op, scalar, semantics, lhs, rhs
function Interpreter:_handle_float_binary(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local val
    local op = cmd.op
    if op == Back.BackFloatAdd then
        val = lv + rv
    elseif op == Back.BackFloatSub then
        val = lv - rv
    elseif op == Back.BackFloatMul then
        val = lv * rv
    elseif op == Back.BackFloatDiv then
        val = rv ~= 0 and lv / rv or 0
    else
        val = lv + rv
    end
    self.registers[cmd.dst.text] = val
end

-- CmdUnary: dst, op, ty, value
function Interpreter:_handle_unary(cmd)
    local v = self.registers[cmd.value.text] or 0
    local Back = self.Back
    local val
    local op = cmd.op
    if op == Back.BackUnaryIneg then
        val = -v
    elseif op == Back.BackUnaryFneg then
        val = -v
    elseif op == Back.BackUnaryBnot then
        local bit = require("bit")
        val = bit.bnot(v)
    elseif op == Back.BackUnaryBoolNot then
        val = not v
    else
        val = v
    end
    self.registers[cmd.dst.text] = val
end

-- CmdCompare: dst, op, ty, lhs, rhs
function Interpreter:_handle_compare(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local Back = self.Back
    local val = false
    local op = cmd.op
    if op == Back.BackIcmpEq then
        val = lv == rv
    elseif op == Back.BackIcmpNe then
        val = lv ~= rv
    elseif op == Back.BackSIcmpLt or op == Back.BackUIcmpLt then
        val = lv < rv
    elseif op == Back.BackSIcmpLe or op == Back.BackUIcmpLe then
        val = lv <= rv
    elseif op == Back.BackSIcmpGt or op == Back.BackUIcmpGt then
        val = lv > rv
    elseif op == Back.BackSIcmpGe or op == Back.BackUIcmpGe then
        val = lv >= rv
    elseif op == Back.BackFCmpEq then
        val = lv == rv
    elseif op == Back.BackFCmpNe then
        val = lv ~= rv
    elseif op == Back.BackFCmpLt then
        val = lv < rv
    elseif op == Back.BackFCmpLe then
        val = lv <= rv
    elseif op == Back.BackFCmpGt then
        val = lv > rv
    elseif op == Back.BackFCmpGe then
        val = lv >= rv
    end
    self.registers[cmd.dst.text] = val
end

-- CmdCast: dst, op, ty, value
function Interpreter:_handle_cast(cmd)
    local v = self.registers[cmd.value.text] or 0
    local Back = self.Back
    local val = v
    local op = cmd.op
    if op == Back.BackBitcast then
        val = v
    elseif op == Back.BackIreduce then
        val = v
    elseif op == Back.BackSextend then
        val = v
    elseif op == Back.BackUextend then
        val = v
    elseif op == Back.BackFpromote then
        val = v
    elseif op == Back.BackFdemote then
        val = v
    elseif op == Back.BackSToF or op == Back.BackUToF then
        val = tonumber(v)
    elseif op == Back.BackFToS or op == Back.BackFToU then
        val = math.floor(v)
    end
    self.registers[cmd.dst.text] = val
end

-- CmdSelect: dst, ty, cond, then_value, else_value
function Interpreter:_handle_select(cmd)
    local cond = self.registers[cmd.cond.text] or false
    if cond then
        self.registers[cmd.dst.text] = self.registers[cmd.then_value.text] or 0
    else
        self.registers[cmd.dst.text] = self.registers[cmd.else_value.text] or 0
    end
end

-- CmdPtrOffset: dst, base, index, elem_size, const_offset, provenance, bounds
function Interpreter:_handle_ptr_offset(cmd)
    local Back = self.Back
    local base_val = 0
    local bc = pvm.classof(cmd.base)
    if bc == Back.BackAddrValue then
        base_val = self.registers[cmd.base.value.text] or 0
    elseif bc == Back.BackAddrStack then
        local slot = self.stack_slots[cmd.base.slot.text]
        base_val = slot and slot.offset or 0
    elseif bc == Back.BackAddrData then
        local region = self.data_regions[cmd.base.data.text]
        base_val = region and region.offset or 0
    end
    local idx = self.registers[cmd.index.text] or 0
    local offset = idx * cmd.elem_size + cmd.const_offset
    self.registers[cmd.dst.text] = base_val + offset
end

-- CmdAlias: dst, src
function Interpreter:_handle_alias(cmd)
    self.registers[cmd.dst.text] = self.registers[cmd.src.text] or 0
end

-- CmdIntrinsic: dst, op, ty, args
function Interpreter:_handle_intrinsic(cmd)
    local Back = self.Back
    local op = cmd.op
    local arg0 = self.registers[cmd.args[1].text] or 0
    local val = arg0
    if op == Back.BackIntrinsicAbs then
        val = math.abs(arg0)
    elseif op == Back.BackIntrinsicSqrt then
        val = math.sqrt(arg0)
    elseif op == Back.BackIntrinsicFloor then
        val = math.floor(arg0)
    elseif op == Back.BackIntrinsicCeil then
        val = math.ceil(arg0)
    elseif op == Back.BackIntrinsicTruncFloat then
        val = math.floor(arg0)
    elseif op == Back.BackIntrinsicRound then
        val = math.floor(arg0 + 0.5)
    elseif op == Back.BackIntrinsicPopcount then
        val = 0  -- simplified
    elseif op == Back.BackIntrinsicClz then
        val = 0  -- simplified
    elseif op == Back.BackIntrinsicCtz then
        val = 0  -- simplified
    elseif op == Back.BackIntrinsicBswap then
        val = arg0  -- simplified
    end
    self.registers[cmd.dst.text] = val
end

-- CmdFma: dst, ty, semantics, a, b, c
function Interpreter:_handle_fma(cmd)
    local a = self.registers[cmd.a.text] or 0
    local b = self.registers[cmd.b.text] or 0
    local c = self.registers[cmd.c.text] or 0
    self.registers[cmd.dst.text] = a * b + c
end

-- CmdJump: dest, args
function Interpreter:_handle_jump(cmd)
    local args = self:_resolve_args(cmd.args)
    self.pending_jump_target = {
        target = cmd.dest.text,
        args = args,
    }
end

-- CmdBrIf: cond, then_block, then_args, else_block, else_args
function Interpreter:_handle_br_if(cmd)
    local cond_val = self.registers[cmd.cond.text] or false
    if cond_val then
        local args = self:_resolve_args(cmd.then_args)
        self.pending_jump_target = {
            target = cmd.then_block.text,
            args = args,
        }
    else
        local args = self:_resolve_args(cmd.else_args)
        self.pending_jump_target = {
            target = cmd.else_block.text,
            args = args,
        }
    end
end

-- CmdSwitchInt: value, ty, cases, default_dest
function Interpreter:_handle_switch_int(cmd)
    local val = self.registers[cmd.value.text] or 0
    local matched = false
    for _, case in ipairs(cmd.cases) do
        if tonumber(case.raw) == val then
            self.pending_jump_target = {
                target = case.dest.text,
                args = {},
            }
            matched = true
            break
        end
    end
    if not matched then
        self.pending_jump_target = {
            target = cmd.default_dest.text,
            args = {},
        }
    end
end

-- CmdSwitchToBlock: block
function Interpreter:_handle_switch_to_block(cmd)
    local bid = cmd.block.text

    -- If we have a pending jump, handle target matching
    if self.pending_jump_target then
        local target = self.pending_jump_target.target
        if target == bid then
            -- Correct target: bind params and enter
            self:_bind_block_params(bid, self.pending_jump_target.args)
            self.pending_jump_target = nil
            self.current_block = bid

            -- Pause at block boundary if stepping
            if self.step_mode == "block" then
                self.paused = true
                return
            end

            -- Check breakpoints in continue mode
            if self.breakpoints_fn then
                if self.breakpoints_fn(bid) then
                    self.paused = true
                    return
                end
            end
        else
            -- Wrong block: skip forward to the correct target block
            local target_idx = self.block_entry_indices[target]
            if target_idx and target_idx > self.cursor then
                -- Set cursor to target_idx-1 so that step() advances to target_idx
                -- On the next step() call, the target's CmdSwitchToBlock will execute
                self.cursor = target_idx - 1
                -- Keep pending_jump_target so the target's handler matches it
            else
                -- Fallback: just continue linearly (may hit wrong block code)
                self.pending_jump_target = nil
                self.current_block = bid
            end
        end
    else
        -- No pending jump: normal block entry (first block or fallthrough)
        self.current_block = bid

        -- Pause at block boundary if stepping
        if self.step_mode == "block" then
            self.paused = true
            return
        end

        -- Check breakpoints in continue mode
        if self.breakpoints_fn then
            if self.breakpoints_fn(bid) then
                self.paused = true
                return
            end
        end
    end
end

-- CmdBindEntryParams: block, values
function Interpreter:_handle_bind_entry_params(cmd)
    -- Map entry param values to registers
    if self.pending_call_args ~= nil then
        for i = 1, #cmd.values do
            self.registers[cmd.values[i].text] = self.pending_call_args[i] or 0
        end
        self.pending_call_args = nil
        return
    end
    local param_names = self.block_params[cmd.block.text]
    if param_names then
        for i = 1, #param_names do
            if i <= #cmd.values then
                self.registers[param_names[i]] = self.registers[cmd.values[i].text] or 0
            end
        end
    end
end

-- CmdReturnVoid
function Interpreter:_handle_return_void(cmd)
    if #self.call_stack > 0 then
        local frame = table.remove(self.call_stack)
        self.registers = frame.registers
        self.cursor = frame.cursor
        self.current_block = frame.current_block
        -- Don't advance past the call; cursor will advance after return
        -- but we need to skip to after the call instruction
        -- The cursor was set to the call's position; step() will advance
    else
        self.terminated = true
    end
end

-- CmdReturnValue: value
function Interpreter:_handle_return_value(cmd)
    self.return_value = self.registers[cmd.value.text] or 0
    if #self.call_stack > 0 then
        local frame = table.remove(self.call_stack)
        self.registers = frame.registers
        if frame.return_dst ~= nil then
            self.registers[frame.return_dst] = self.return_value
        end
        self.cursor = frame.cursor
        self.current_block = frame.current_block
    else
        self.terminated = true
    end
end

-- CmdTrap
function Interpreter:_handle_trap(cmd)
    self.terminated = true
    self.trap_reason = "trap"
    self:emit_event("trap", { block = self.current_block })
end

-- CmdCreateStackSlot: slot, size, align
function Interpreter:_handle_create_stack_slot(cmd)
    local slot_id = cmd.slot.text
    local offset = self:_alloc_stack(cmd.size, cmd.align)
    self.stack_slots[slot_id] = { offset = offset, size = cmd.size }
end

-- CmdStackAddr: dst, slot
function Interpreter:_handle_stack_addr(cmd)
    local slot = self.stack_slots[cmd.slot.text]
    if slot then
        self.registers[cmd.dst.text] = slot.offset
    else
        self.registers[cmd.dst.text] = 0
    end
end

-- CmdLoadInfo: dst, ty (BackShape), addr (BackAddress), memory
function Interpreter:_handle_load_info(cmd)
    local addr = self:_resolve_address(cmd.addr)
    -- Check if addr is a register (for the value base case)
    local addr_val = addr
    local shape = cmd.ty
    local sc = pvm.classof(shape)
    local scalar
    if sc == self.Back.BackShapeScalar then
        scalar = shape.scalar
    elseif sc == self.Back.BackShapeVec then
        scalar = shape.vec.elem  -- approximate: read first lane
    else
        scalar = self.Back.BackI32
    end
    local val = self:_read_memory(addr_val, scalar)
    self.registers[cmd.dst.text] = val
end

-- CmdStoreInfo: ty (BackShape), addr (BackAddress), value, memory
function Interpreter:_handle_store_info(cmd)
    local addr = self:_resolve_address(cmd.addr)
    local val = self.registers[cmd.value.text] or 0
    local shape = cmd.ty
    local sc = pvm.classof(shape)
    local scalar
    if sc == self.Back.BackShapeScalar then
        scalar = shape.scalar
    elseif sc == self.Back.BackShapeVec then
        scalar = shape.vec.elem
    else
        scalar = self.Back.BackI32
    end
    self:_write_memory(addr, scalar, val)
end

-- CmdDeclareData: data, size, align
function Interpreter:_handle_declare_data(cmd)
    local data_id = cmd.data.text
    local offset = self:_alloc_data(cmd.size, cmd.align)
    self.data_regions[data_id] = { offset = offset, size = cmd.size }
end

-- CmdDataInitZero: data, offset, size
function Interpreter:_handle_data_init_zero(cmd)
    local region = self.data_regions[cmd.data.text]
    if region then
        local start = region.offset + cmd.offset
        local ffi = require("ffi")
        if start >= 0 and start + cmd.size <= self.memory_size then
            ffi.fill(self.memory_ptr + start, cmd.size, 0)
        end
    end
end

-- CmdDataInit: data, offset, ty, value (BackLiteral)
function Interpreter:_handle_data_init(cmd)
    local region = self.data_regions[cmd.data.text]
    if not region then return end
    local Back = self.Back
    local lit = cmd.value
    local lc = pvm.classof(lit)
    local val
    if lc == Back.BackLitInt then
        val = tonumber(lit.raw)
    elseif lc == Back.BackLitFloat then
        val = tonumber(lit.raw)
    elseif lc == Back.BackLitBool then
        val = lit.value and 1 or 0
    elseif lc == Back.BackLitNull then
        val = 0
    else
        val = 0
    end
    local addr = region.offset + cmd.offset
    self:_write_memory(addr, cmd.ty, val)
end

-- CmdDataAddr: dst, data
function Interpreter:_handle_data_addr(cmd)
    local region = self.data_regions[cmd.data.text]
    if region then
        self.registers[cmd.dst.text] = region.offset
    else
        self.registers[cmd.dst.text] = 0
    end
end

-- CmdFuncAddr: dst, func
function Interpreter:_handle_func_addr(cmd)
    self.registers[cmd.dst.text] = { kind = "func", func = cmd.func.text }
end

-- CmdExternAddr: dst, func
function Interpreter:_handle_extern_addr(cmd)
    -- Store a sentinel address for extern functions
    self.registers[cmd.dst.text] = { kind = "extern", func = cmd.func.text }
end

-- CmdMemcpy: dst, src, len
function Interpreter:_handle_memcpy(cmd)
    local dst = self.registers[cmd.dst.text] or 0
    local src = self.registers[cmd.src.text] or 0
    local len = self.registers[cmd.len.text] or 0
    local ffi = require("ffi")
    if dst >= 0 and src >= 0 and len > 0
       and dst + len <= self.memory_size and src + len <= self.memory_size then
        ffi.copy(self.memory_ptr + dst, self.memory_ptr + src, len)
    end
end

-- CmdMemset: dst, byte, len
function Interpreter:_handle_memset(cmd)
    local dst = self.registers[cmd.dst.text] or 0
    local byte = self.registers[cmd.byte.text] or 0
    local len = self.registers[cmd.len.text] or 0
    local ffi = require("ffi")
    if dst >= 0 and len > 0 and dst + len <= self.memory_size then
        ffi.fill(self.memory_ptr + dst, len, byte)
    end
end

-- CmdMemcmp: dst, left, right, len
function Interpreter:_handle_memcmp(cmd)
    local left = self.registers[cmd.left.text] or 0
    local right = self.registers[cmd.right.text] or 0
    local len = self.registers[cmd.len.text] or 0
    local ffi = require("ffi")
    if left >= 0 and right >= 0 and len > 0
       and left + len <= self.memory_size and right + len <= self.memory_size then
        local result = ffi.compare(self.memory_ptr + left, self.memory_ptr + right, len)
        self.registers[cmd.dst.text] = result
    else
        self.registers[cmd.dst.text] = 0
    end
end

function Interpreter:_call_internal_func(func_id, cmd)
    local func_entry = self.func_map[func_id]
    if not func_entry then return false end
    local rc = pvm.classof(cmd.result)
    local return_dst = nil
    if rc == self.Back.BackCallValue then
        return_dst = cmd.result.dst.text
    end
    local args = {}
    for i = 1, #cmd.args do
        args[i] = self.registers[cmd.args[i].text] or 0
    end
    table.insert(self.call_stack, {
        cursor = self.cursor,
        registers = self:_copy_registers(),
        current_block = self.current_block,
        return_dst = return_dst,
    })
    self.registers = {}
    self.pending_call_args = args
    self.cursor = func_entry.start_idx - 1
    self.current_block = nil
    self.pending_jump_target = nil
    return true
end

-- CmdCall: result, target, sig, args
function Interpreter:_handle_call(cmd)
    local Back = self.Back
    local target = cmd.target
    local tc = pvm.classof(target)

    if tc == Back.BackCallExtern then
        -- Call extern function
        local func_name = target.func.text
        local fn = self.extrn[func_name]
        if fn then
            local args = {}
            for i = 1, #cmd.args do
                args[i] = self.registers[cmd.args[i].text] or 0
            end
            local ok, result = pcall(fn, unpack(args))
            local rc = pvm.classof(cmd.result)
            if ok and rc == Back.BackCallValue then
                self.registers[cmd.result.dst.text] = result or 0
            end
        end
    elseif tc == Back.BackCallDirect then
        self:_call_internal_func(target.func.text, cmd)
    elseif tc == Back.BackCallIndirect then
        local callee = self.registers[target.callee.text]
        if type(callee) == "table" and callee.kind == "func" then
            self:_call_internal_func(callee.func, cmd)
        elseif type(callee) == "table" and callee.kind == "extern" then
            local fn = self.extrn[callee.func]
            if fn then
                local args = {}
                for i = 1, #cmd.args do args[i] = self.registers[cmd.args[i].text] or 0 end
                local ok, result = pcall(fn, unpack(args))
                if ok and pvm.classof(cmd.result) == Back.BackCallValue then
                    self.registers[cmd.result.dst.text] = result or 0
                end
            end
        else
            error("debug_interpreter: indirect callee is not a function address", 2)
        end
    end
end

return M
