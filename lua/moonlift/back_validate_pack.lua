-- back_validate_pack.lua — pack MoonBack.BackProgram into a flat i32 array
-- consumable by native PVM-LL validation regions.
--
-- Layout:
--   [0]           total command count N
--   [1]           intern count I
--   [2..I+1]      intern string lengths (each length in chars)
--   [I+2..]       intern string characters (packed 1 char per i32)
--   after that:   command data
--     per command: [escaped_length, tag, field0..fieldN]
--   after all cmds: issue buffer start offset (set by native code)
--
-- The issue buffer is placed after the command data; native code writes
-- issues into it as [count, kind, index, payload...].
--
-- ID references (SigId, FuncId, etc.) are packed as intern indices.
-- Scalars are packed as their numeric kind (1=BackBool .. 13=BackIndex).
-- Literals use sub-tags.

local pvm = require("moonlift.pvm")
local math_ceil = math.ceil

local SECTION = {
    CMD_COUNT   = 0,
    INTERN_COUNT = 1,
}

local CMD_TAG = {
    CmdTargetModel      = 0,
    CmdCreateSig        = 1,
    CmdDeclareData      = 2,
    CmdDataInitZero     = 3,
    CmdDataInit         = 4,
    CmdDataAddr         = 5,
    CmdFuncAddr         = 6,
    CmdExternAddr       = 7,
    CmdDeclareFunc      = 8,
    CmdDeclareExtern    = 9,
    CmdBeginFunc        = 10,
    CmdFinishFunc       = 11,
    CmdCreateBlock      = 12,
    CmdSwitchToBlock    = 13,
    CmdSealBlock        = 14,
    CmdBindEntryParams  = 15,
    CmdAppendBlockParam = 16,
    CmdCreateStackSlot  = 17,
    CmdAlias            = 18,
    CmdStackAddr        = 19,
    CmdConst            = 20,
    CmdUnary            = 21,
    CmdIntrinsic        = 22,
    CmdCompare          = 23,
    CmdCast             = 24,
    CmdPtrOffset        = 25,
    CmdLoadInfo         = 26,
    CmdStoreInfo        = 27,
    CmdIntBinary        = 28,
    CmdBitBinary        = 29,
    CmdBitNot           = 30,
    CmdShift            = 31,
    CmdRotate           = 32,
    CmdFloatBinary      = 33,
    CmdAliasFact        = 34,
    CmdMemcpy           = 35,
    CmdMemset           = 36,
    CmdSelect           = 37,
    CmdFma              = 38,
    CmdVecSplat         = 39,
    CmdVecBinary        = 40,
    CmdVecCompare       = 41,
    CmdVecSelect        = 42,
    CmdVecMask          = 43,
    CmdVecInsertLane    = 44,
    CmdVecExtractLane   = 45,
    CmdCall             = 46,
    CmdJump             = 47,
    CmdBrIf             = 48,
    CmdSwitchInt        = 49,
    CmdReturnVoid       = 50,
    CmdReturnValue      = 51,
    CmdTrap             = 52,
    CmdFinalizeModule   = 53,
}

local SCALAR_KIND = {
    BackVoid  = 0,  BackBool  = 1,  BackI8   = 2,  BackI16  = 3,
    BackI32   = 4,  BackI64   = 5,  BackU8   = 6,  BackU16  = 7,
    BackU32   = 8,  BackU64   = 9,  BackF32  = 10, BackF64  = 11,
    BackPtr   = 12, BackIndex = 13,
}

local ALIGN_KIND  = { BackAlignKnown = 1, BackAlignAtLeast = 2, BackAlignAssumed = 3 }
local DEREF_KIND  = { BackDerefBytes = 1, BackDerefAssumed = 2 }
local TRAP_KIND   = { BackNonTrapping = 1, BackChecked = 2 }
local MOTION_KIND = { BackCanMove = 1 }
local ACCESS_MODE = { BackAccessRead = 1, BackAccessWrite = 2, BackAccessReadWrite = 3 }

local INT_OVERFLOW = { BackIntWrap = 0, BackIntNoSignedWrap = 1, BackIntNoUnsignedWrap = 2, BackIntNoWrap = 3 }
local INT_EXACT   = { BackIntExact = 1, BackIntMayLose = 0 }

local LIT_KIND = { BackLitInt = 1, BackLitFloat = 2, BackLitBool = 3, BackLitNull = 4 }

local M = {}

local function id_text(v)
    return type(v) == "string" and v or v.text
end

local function scalar_kind(s)
    return SCALAR_KIND[s.kind] or 0
end

local function intern_id(intern, id_map, v)
    local key = id_text(v)
    local idx = id_map[key]
    if idx ~= nil then return idx end
    idx = #intern + 1
    id_map[key] = idx
    intern[idx] = key
    return idx
end

local function collect_ids(intern, id_map, cmds)
    local B = M._Back
    for i = 1, #cmds do
        local cmd = cmds[i]
        local k = cmd.kind
        if k == "CmdCreateSig" then
            intern_id(intern, id_map, cmd.sig)
        elseif k == "CmdDeclareData" or k == "CmdDataInitZero" or k == "CmdDataInit" or k == "CmdDataAddr" then
            intern_id(intern, id_map, cmd.data)
            if k == "CmdDataAddr" then intern_id(intern, id_map, cmd.dst) end
        elseif k == "CmdFuncAddr" then
            intern_id(intern, id_map, cmd.func)
            intern_id(intern, id_map, cmd.dst)
        elseif k == "CmdExternAddr" then
            intern_id(intern, id_map, cmd.func)
            intern_id(intern, id_map, cmd.dst)
        elseif k == "CmdDeclareFunc" then
            intern_id(intern, id_map, cmd.func)
            intern_id(intern, id_map, cmd.sig)
        elseif k == "CmdDeclareExtern" then
            intern_id(intern, id_map, cmd.func)
            intern_id(intern, id_map, cmd.sig)
        elseif k == "CmdBeginFunc" or k == "CmdFinishFunc" then
            intern_id(intern, id_map, cmd.func)
        elseif k == "CmdCreateBlock" or k == "CmdSwitchToBlock" or k == "CmdSealBlock" then
            intern_id(intern, id_map, cmd.block)
        elseif k == "CmdBindEntryParams" then
            intern_id(intern, id_map, cmd.block)
            for j = 1, #(cmd.values or {}) do intern_id(intern, id_map, cmd.values[j]) end
        elseif k == "CmdAppendBlockParam" then
            intern_id(intern, id_map, cmd.block)
            intern_id(intern, id_map, cmd.value)
        elseif k == "CmdCreateStackSlot" then
            intern_id(intern, id_map, cmd.slot)
        elseif k == "CmdAlias" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.src)
        elseif k == "CmdStackAddr" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.slot)
        elseif k == "CmdConst" then
            intern_id(intern, id_map, cmd.dst)
        elseif k == "CmdUnary" or k == "CmdIntrinsic" then
            intern_id(intern, id_map, cmd.dst)
            if k == "CmdUnary" then intern_id(intern, id_map, cmd.value) end
            for j = 1, #(cmd.args or {}) do intern_id(intern, id_map, cmd.args[j]) end
        elseif k == "CmdCompare" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.lhs)
            intern_id(intern, id_map, cmd.rhs)
        elseif k == "CmdCast" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.value)
        elseif k == "CmdPtrOffset" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.index)
            local base_cls = pvm.classof(cmd.base)
            if base_cls == B.BackAddrValue then intern_id(intern, id_map, cmd.base.value)
            elseif base_cls == B.BackAddrStack then intern_id(intern, id_map, cmd.base.slot)
            elseif base_cls == B.BackAddrData then intern_id(intern, id_map, cmd.base.data) end
        elseif k == "CmdLoadInfo" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.memory.access)
            local addr = cmd.addr
            local base_cls = pvm.classof(addr.base)
            if base_cls == B.BackAddrValue then intern_id(intern, id_map, addr.base.value)
            elseif base_cls == B.BackAddrStack then intern_id(intern, id_map, addr.base.slot)
            elseif base_cls == B.BackAddrData then intern_id(intern, id_map, addr.base.data) end
            intern_id(intern, id_map, addr.byte_offset)
        elseif k == "CmdStoreInfo" then
            intern_id(intern, id_map, cmd.value)
            intern_id(intern, id_map, cmd.memory.access)
            local addr = cmd.addr
            local base_cls = pvm.classof(addr.base)
            if base_cls == B.BackAddrValue then intern_id(intern, id_map, addr.base.value)
            elseif base_cls == B.BackAddrStack then intern_id(intern, id_map, addr.base.slot)
            elseif base_cls == B.BackAddrData then intern_id(intern, id_map, addr.base.data) end
            intern_id(intern, id_map, addr.byte_offset)
        elseif k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" or k == "CmdFloatBinary" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.lhs)
            intern_id(intern, id_map, cmd.rhs)
        elseif k == "CmdBitNot" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.value)
        elseif k == "CmdSelect" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.cond)
            intern_id(intern, id_map, cmd.then_value)
            intern_id(intern, id_map, cmd.else_value)
        elseif k == "CmdFma" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.a)
            intern_id(intern, id_map, cmd.b)
            intern_id(intern, id_map, cmd.c)
        elseif k == "CmdMemcpy" or k == "CmdMemset" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.src or cmd.byte)
            intern_id(intern, id_map, cmd.len)
        elseif k == "CmdVecSplat" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.value)
        elseif k == "CmdVecBinary" or k == "CmdVecCompare" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.lhs)
            intern_id(intern, id_map, cmd.rhs)
        elseif k == "CmdVecSelect" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.mask)
            intern_id(intern, id_map, cmd.then_value)
            intern_id(intern, id_map, cmd.else_value)
        elseif k == "CmdVecMask" then
            intern_id(intern, id_map, cmd.dst)
            for j = 1, #(cmd.args or {}) do intern_id(intern, id_map, cmd.args[j]) end
        elseif k == "CmdVecInsertLane" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.value)
            intern_id(intern, id_map, cmd.lane_value)
        elseif k == "CmdVecExtractLane" then
            intern_id(intern, id_map, cmd.dst)
            intern_id(intern, id_map, cmd.value)
        elseif k == "CmdCall" then
            intern_id(intern, id_map, cmd.sig)
            local target_cls = pvm.classof(cmd.target)
            if target_cls == B.BackCallDirect then intern_id(intern, id_map, cmd.target.func)
            elseif target_cls == B.BackCallExtern then intern_id(intern, id_map, cmd.target.func)
            elseif target_cls == B.BackCallIndirect then intern_id(intern, id_map, cmd.target.callee) end
            if cmd.result ~= B.BackCallStmt and pvm.classof(cmd.result) == B.BackCallValue then
                intern_id(intern, id_map, cmd.result.dst)
            end
            for j = 1, #(cmd.args or {}) do intern_id(intern, id_map, cmd.args[j]) end
        elseif k == "CmdJump" then
            intern_id(intern, id_map, cmd.dest)
            for j = 1, #(cmd.args or {}) do intern_id(intern, id_map, cmd.args[j]) end
        elseif k == "CmdBrIf" then
            intern_id(intern, id_map, cmd.cond)
            intern_id(intern, id_map, cmd.then_block)
            intern_id(intern, id_map, cmd.else_block)
            for j = 1, #(cmd.then_args or {}) do intern_id(intern, id_map, cmd.then_args[j]) end
            for j = 1, #(cmd.else_args or {}) do intern_id(intern, id_map, cmd.else_args[j]) end
        elseif k == "CmdSwitchInt" then
            intern_id(intern, id_map, cmd.value)
            intern_id(intern, id_map, cmd.default_dest)
            for j = 1, #(cmd.cases or {}) do intern_id(intern, id_map, cmd.cases[j].dest) end
        elseif k == "CmdReturnValue" then
            intern_id(intern, id_map, cmd.value)
        end
    end
end

local function pack_intern_strings(buf, intern)
    local str_start = #buf
    for i = 1, #intern do
        local s = intern[i]
        buf[str_start] = #s  -- length
        str_start = str_start + 1
        for j = 1, #s do
            buf[str_start] = string.byte(s, j)
            str_start = str_start + 1
        end
    end
end

local function pack_addr_base(buf, base, id_map)
    local cls = pvm.classof(base)
    if cls == M._Back.BackAddrValue then
        buf[#buf + 1] = 1  -- tag: value
        buf[#buf + 1] = id_map[id_text(base.value)] or 0
    elseif cls == M._Back.BackAddrStack then
        buf[#buf + 1] = 2  -- tag: stack
        buf[#buf + 1] = id_map[id_text(base.slot)] or 0
    elseif cls == M._Back.BackAddrData then
        buf[#buf + 1] = 3  -- tag: data
        buf[#buf + 1] = id_map[id_text(base.data)] or 0
    end
end

local function pack_memory(buf, memory, id_map)
    buf[#buf + 1] = id_map[id_text(memory.access)] or 0
    buf[#buf + 1] = ALIGN_KIND[memory.alignment.kind] or 0
    buf[#buf + 1] = memory.alignment.bytes or 0
    buf[#buf + 1] = DEREF_KIND[memory.dereference.kind] or 0
    buf[#buf + 1] = memory.dereference.bytes or 0
    buf[#buf + 1] = TRAP_KIND[memory.trap.kind] or 0
    buf[#buf + 1] = MOTION_KIND[memory.motion.kind] or 0
    buf[#buf + 1] = ACCESS_MODE[memory.mode.kind] or 1
end

local function pack_shape(buf, shape)
    if shape.kind == "BackShapeScalar" then
        buf[#buf + 1] = 0  -- scalar
        buf[#buf + 1] = scalar_kind(shape.scalar)
    elseif shape.kind == "BackShapeVec" then
        buf[#buf + 1] = 1  -- vector
        buf[#buf + 1] = scalar_kind(shape.vec.elem)
        buf[#buf + 1] = shape.vec.lanes
    end
end

local function pack_literal(buf, lit)
    local k = lit.kind
    if k == "BackLitInt" then
        buf[#buf + 1] = LIT_KIND.BackLitInt
        buf[#buf + 1] = tonumber(lit.raw) or 0
    elseif k == "BackLitFloat" then
        buf[#buf + 1] = LIT_KIND.BackLitFloat
        buf[#buf + 1] = 0  -- float value packed as raw, handled differently if needed
    elseif k == "BackLitBool" then
        buf[#buf + 1] = LIT_KIND.BackLitBool
        buf[#buf + 1] = (lit.value and 1 or 0)
    elseif k == "BackLitNull" then
        buf[#buf + 1] = LIT_KIND.BackLitNull
        buf[#buf + 1] = 0
    end
end

local function pack_cmd(buf, cmd, id_map)
    local k = cmd.kind
    local tag = CMD_TAG[k]
    if tag == nil then return end

    local pos = #buf + 1
    buf[pos] = 0  -- placeholder for length
    buf[pos + 1] = tag
    local start = #buf + 1
    buf[#buf + 1] = nil  -- placeholder for length (we fill after)

    if k == "CmdTargetModel" or k == "CmdAliasFact" then
        -- no-op, just tag
    elseif k == "CmdCreateSig" then
        buf[#buf + 1] = id_map[id_text(cmd.sig)] or 0
        buf[#buf + 1] = #(cmd.params or {})
        for j = 1, #(cmd.params or {}) do buf[#buf + 1] = scalar_kind(cmd.params[j]) end
        buf[#buf + 1] = #(cmd.results or {})
        for j = 1, #(cmd.results or {}) do buf[#buf + 1] = scalar_kind(cmd.results[j]) end
    elseif k == "CmdDeclareData" then
        buf[#buf + 1] = id_map[id_text(cmd.data)] or 0
        buf[#buf + 1] = cmd.size or 0
        buf[#buf + 1] = cmd.align or 0
    elseif k == "CmdDataInitZero" then
        buf[#buf + 1] = id_map[id_text(cmd.data)] or 0
        buf[#buf + 1] = cmd.offset or 0
        buf[#buf + 1] = cmd.size or 0
    elseif k == "CmdDataInit" then
        buf[#buf + 1] = id_map[id_text(cmd.data)] or 0
        buf[#buf + 1] = cmd.offset or 0
        buf[#buf + 1] = scalar_kind(cmd.ty)
        pack_literal(buf, cmd.value)
    elseif k == "CmdDataAddr" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.data)] or 0
    elseif k == "CmdFuncAddr" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.func)] or 0
    elseif k == "CmdExternAddr" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.func)] or 0
    elseif k == "CmdDeclareFunc" then
        buf[#buf + 1] = (cmd.visibility.kind == "VisibilityExport" and 1 or 0)
        buf[#buf + 1] = id_map[id_text(cmd.func)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.sig)] or 0
    elseif k == "CmdDeclareExtern" then
        buf[#buf + 1] = id_map[id_text(cmd.func)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.sig)] or 0
    elseif k == "CmdBeginFunc" or k == "CmdFinishFunc" then
        buf[#buf + 1] = id_map[id_text(cmd.func)] or 0
    elseif k == "CmdCreateBlock" or k == "CmdSwitchToBlock" or k == "CmdSealBlock" then
        buf[#buf + 1] = id_map[id_text(cmd.block)] or 0
    elseif k == "CmdBindEntryParams" then
        buf[#buf + 1] = id_map[id_text(cmd.block)] or 0
        buf[#buf + 1] = #(cmd.values or {})
        for j = 1, #(cmd.values or {}) do buf[#buf + 1] = id_map[id_text(cmd.values[j])] or 0 end
    elseif k == "CmdAppendBlockParam" then
        buf[#buf + 1] = id_map[id_text(cmd.block)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
        pack_shape(buf, cmd.ty)
    elseif k == "CmdCreateStackSlot" then
        buf[#buf + 1] = id_map[id_text(cmd.slot)] or 0
        buf[#buf + 1] = cmd.size or 0
        buf[#buf + 1] = cmd.align or 0
    elseif k == "CmdAlias" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.src)] or 0
    elseif k == "CmdStackAddr" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.slot)] or 0
    elseif k == "CmdConst" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty)
        pack_literal(buf, cmd.value)
    elseif k == "CmdUnary" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = (cmd.op.kind == "BackNeg" and 1 or (cmd.op.kind == "BackNot" and 2 or 0))
        pack_shape(buf, cmd.ty)
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
    elseif k == "CmdIntrinsic" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- op kind (simplified)
        pack_shape(buf, cmd.ty)
        buf[#buf + 1] = #(cmd.args or {})
        for j = 1, #(cmd.args or {}) do buf[#buf + 1] = id_map[id_text(cmd.args[j])] or 0 end
    elseif k == "CmdCompare" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = (cmd.op.kind == "BackIcmpEq" and 1 or (cmd.op.kind == "BackIcmpNe" and 2 or 0))
        pack_shape(buf, cmd.ty)
        buf[#buf + 1] = id_map[id_text(cmd.lhs)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.rhs)] or 0
    elseif k == "CmdCast" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- cast op kind
        buf[#buf + 1] = scalar_kind(cmd.ty)
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
    elseif k == "CmdPtrOffset" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        pack_addr_base(buf, cmd.base, id_map)
        buf[#buf + 1] = id_map[id_text(cmd.index)] or 0
        buf[#buf + 1] = cmd.elem_size or 0
        buf[#buf + 1] = cmd.const_offset or 0
    elseif k == "CmdLoadInfo" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        pack_shape(buf, cmd.ty)
        pack_addr_base(buf, cmd.addr.base, id_map)
        buf[#buf + 1] = id_map[id_text(cmd.addr.byte_offset)] or 0
        pack_memory(buf, cmd.memory, id_map)
    elseif k == "CmdStoreInfo" then
        pack_shape(buf, cmd.ty)
        pack_addr_base(buf, cmd.addr.base, id_map)
        buf[#buf + 1] = id_map[id_text(cmd.addr.byte_offset)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
        pack_memory(buf, cmd.memory, id_map)
    elseif k == "CmdIntBinary" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = (cmd.op.kind == "BackIntAdd" and 1 or (cmd.op.kind == "BackIntSub" and 2 or (cmd.op.kind == "BackIntMul" and 3 or 0)))
        buf[#buf + 1] = scalar_kind(cmd.scalar)
        buf[#buf + 1] = INT_OVERFLOW[cmd.semantics.overflow.kind] or 0
        buf[#buf + 1] = INT_EXACT[cmd.semantics.exact.kind] or 0
        buf[#buf + 1] = id_map[id_text(cmd.lhs)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.rhs)] or 0
    elseif k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- op kind
        buf[#buf + 1] = scalar_kind(cmd.scalar)
        buf[#buf + 1] = id_map[id_text(cmd.lhs)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.rhs)] or 0
    elseif k == "CmdBitNot" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.scalar)
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
    elseif k == "CmdFloatBinary" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- op kind
        buf[#buf + 1] = scalar_kind(cmd.scalar)
        buf[#buf + 1] = (cmd.semantics.kind == "BackFloatFastMath" and 1 or 0)
        buf[#buf + 1] = id_map[id_text(cmd.lhs)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.rhs)] or 0
    elseif k == "CmdMemcpy" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.src)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.len)] or 0
    elseif k == "CmdMemset" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.byte)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.len)] or 0
    elseif k == "CmdSelect" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        pack_shape(buf, cmd.ty)
        buf[#buf + 1] = id_map[id_text(cmd.cond)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.then_value)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.else_value)] or 0
    elseif k == "CmdFma" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty)
        buf[#buf + 1] = (cmd.semantics.kind == "BackFloatFastMath" and 1 or 0)
        buf[#buf + 1] = id_map[id_text(cmd.a)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.b)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.c)] or 0
    elseif k == "CmdVecSplat" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty.elem)
        buf[#buf + 1] = cmd.ty.lanes
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
    elseif k == "CmdVecBinary" or k == "CmdVecCompare" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- op kind
        buf[#buf + 1] = scalar_kind(cmd.ty.elem)
        buf[#buf + 1] = cmd.ty.lanes
        buf[#buf + 1] = id_map[id_text(cmd.lhs)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.rhs)] or 0
    elseif k == "CmdVecSelect" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty.elem)
        buf[#buf + 1] = cmd.ty.lanes
        buf[#buf + 1] = id_map[id_text(cmd.mask)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.then_value)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.else_value)] or 0
    elseif k == "CmdVecMask" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = 0  -- op kind
        buf[#buf + 1] = scalar_kind(cmd.ty.elem)
        buf[#buf + 1] = cmd.ty.lanes
        buf[#buf + 1] = #(cmd.args or {})
        for j = 1, #(cmd.args or {}) do buf[#buf + 1] = id_map[id_text(cmd.args[j])] or 0 end
    elseif k == "CmdVecInsertLane" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty.elem)
        buf[#buf + 1] = cmd.ty.lanes
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.lane_value)] or 0
        buf[#buf + 1] = cmd.lane or 0
    elseif k == "CmdVecExtractLane" then
        buf[#buf + 1] = id_map[id_text(cmd.dst)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty)
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
        buf[#buf + 1] = cmd.lane or 0
    elseif k == "CmdCall" then
        local target_cls = pvm.classof(cmd.target)
        local target_kind = target_cls == M._Back.BackCallDirect and 1 or (target_cls == M._Back.BackCallExtern and 2 or 3)
        local target_id = id_map[id_text(cmd.target.func or cmd.target.callee)] or 0
        local result_cls = pvm.classof(cmd.result)
        local result_kind = result_cls == M._Back.BackCallStmt and 0 or 1
        local result_id = (result_kind == 1) and (id_map[id_text(cmd.result.dst)] or 0) or 0
        buf[#buf + 1] = result_kind
        buf[#buf + 1] = result_id
        buf[#buf + 1] = target_kind
        buf[#buf + 1] = target_id
        buf[#buf + 1] = id_map[id_text(cmd.sig)] or 0
        buf[#buf + 1] = #(cmd.args or {})
        for j = 1, #(cmd.args or {}) do buf[#buf + 1] = id_map[id_text(cmd.args[j])] or 0 end
    elseif k == "CmdJump" then
        buf[#buf + 1] = id_map[id_text(cmd.dest)] or 0
        buf[#buf + 1] = #(cmd.args or {})
        for j = 1, #(cmd.args or {}) do buf[#buf + 1] = id_map[id_text(cmd.args[j])] or 0 end
    elseif k == "CmdBrIf" then
        buf[#buf + 1] = id_map[id_text(cmd.cond)] or 0
        buf[#buf + 1] = id_map[id_text(cmd.then_block)] or 0
        buf[#buf + 1] = #(cmd.then_args or {})
        for j = 1, #(cmd.then_args or {}) do buf[#buf + 1] = id_map[id_text(cmd.then_args[j])] or 0 end
        buf[#buf + 1] = id_map[id_text(cmd.else_block)] or 0
        buf[#buf + 1] = #(cmd.else_args or {})
        for j = 1, #(cmd.else_args or {}) do buf[#buf + 1] = id_map[id_text(cmd.else_args[j])] or 0 end
    elseif k == "CmdSwitchInt" then
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
        buf[#buf + 1] = scalar_kind(cmd.ty)
        buf[#buf + 1] = #(cmd.cases or {})
        for j = 1, #(cmd.cases or {}) do
            buf[#buf + 1] = id_map[id_text(cmd.cases[j].dest)] or 0
        end
        buf[#buf + 1] = id_map[id_text(cmd.default_dest)] or 0
    elseif k == "CmdReturnVoid" or k == "CmdTrap" or k == "CmdFinalizeModule" then
        -- no fields
    elseif k == "CmdReturnValue" then
        buf[#buf + 1] = id_map[id_text(cmd.value)] or 0
    end

    -- fill length
    local length = #buf - pos
    buf[pos] = length
end

function M.pack_offsets(data)
    -- Compute offsets in the packed data array
    local N = data[1] or 0          -- cmd count
    local I = data[2] or 0          -- intern count
    -- Skip intern: I lengths + all chars
    local pos = 3
    for i = 1, I do
        local slen = data[pos] or 0
        pos = pos + 1 + slen
    end
    local intern_end = pos
    -- Walk commands to find cmds_end
    local cmds_start = pos
    for i = 1, N do
        local len = data[pos] or 0
        if len <= 0 then
            pos = pos + 1
        else
            pos = pos + len
        end
    end
    local cmds_end = pos
    local issue_start = pos  -- after commands
    local bitset_words = math.ceil(I / 32)
    return {
        intern_end = intern_end,
        cmds_start = cmds_start,
        cmds_end = cmds_end,
        issue_start = issue_start,
        bitset_words = bitset_words,
    }
end

function M.pack(program)
    local B = M._Back or (program.cmds[1] and pvm.classof(program.cmds[1]) and pvm.classof(program.cmds[1]).__module and program.cmds[1].__module)
    if not M._Back then
        -- try to find Back from the first command
        for i = 1, #program.cmds do
            local cls = pvm.classof(program.cmds[i])
            if cls and cls.__module then
                M._Back = cls.__module
                break
            end
        end
    end

    local intern = {}  -- [idx] = string
    local id_map = {} -- string -> idx
    collect_ids(intern, id_map, program.cmds)

    local header = {}
    header[1] = #program.cmds       -- CMD_COUNT
    header[2] = #intern              -- INTERN_COUNT
    pack_intern_strings(header, intern)

    local cmds_buf = {}
    for i = 1, #program.cmds do
        pack_cmd(cmds_buf, program.cmds[i], id_map)
    end

    -- Combine header + cmds + reserve space for issue buffer
    local result = {}
    for i = 1, #header do result[#result + 1] = header[i] end
    for i = 1, #cmds_buf do result[#result + 1] = cmds_buf[i] end

    -- Reserve issue buffer space (just a count word for now)
    local issue_start = #result
    result[#result + 1] = 0  -- issue count placeholder

    return {
        data = result,
        intern = intern,
        id_map = id_map,
        issue_start = issue_start,
    }
end

function M.unpack_issues(packed, report_api)
    local B = report_api
    local data = packed.data
    local intern = packed.intern
    local issue_start = packed.issue_start
    local issue_count = data[issue_start] or 0
    local issues = {}

    local pos = issue_start + 1
    for i = 1, issue_count do
        local kind = data[pos] or 0
        local index = data[pos + 1] or 0
        pos = pos + 2

        -- Reconstruct issue ASDL value
        -- Since we can't easily construct specific issue variants from plain data,
        -- we return a structured table for comparison
        local payload = {}
        -- Payload depends on issue kind; for now just collect remaining fields
        -- The native side writes: [kind, index, optional_payload...]
        issues[#issues + 1] = { kind = kind, index = index, payload = payload }
    end

    return issues
end

M.SCALAR_KIND = SCALAR_KIND
M.CMD_TAG = CMD_TAG

return M
