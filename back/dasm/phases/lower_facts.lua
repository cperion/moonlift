-- lower_facts.lua - Lower DFactSet families to DAsm shapes
--
-- Plain Lua decision logic (no LISLE needed here).
-- LISLE is reserved for complex instruction selection (rules_x64.lisle).

local bit = require("bit")
local pvm = require("moonlift.pvm")
local Mx = require("back.dasm.model")

local function vreg_of(D, v)
    return D.DVirtualRegId(Mx.idkey(v) or "<nil>")
end

local function op_vreg(D, v)
    return D.DOpVReg(vreg_of(D, v))
end

local function defs_of(cmd)
    local k = cmd.kind
    if k == "CmdConst" or k == "CmdAlias" or k == "CmdUnary" or k == "CmdIntrinsic"
        or k == "CmdCompare" or k == "CmdCast" or k == "CmdPtrOffset" or k == "CmdLoadInfo"
        or k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdBitNot" or k == "CmdShift"
        or k == "CmdRotate" or k == "CmdFloatBinary" or k == "CmdSelect" or k == "CmdFma"
        or k == "CmdVecSplat" or k == "CmdVecBinary" or k == "CmdVecCompare" or k == "CmdVecSelect"
        or k == "CmdVecMask" or k == "CmdVecInsertLane" or k == "CmdVecExtractLane"
        or k == "CmdStackAddr" or k == "CmdDataAddr" or k == "CmdFuncAddr" or k == "CmdExternAddr" then
        return { cmd.dst }
    elseif k == "CmdCall" then
        if cmd.result and cmd.result.kind == "BackCallValue" then return { cmd.result.dst } end
    elseif k == "CmdBindEntryParams" then
        return cmd.values or {}
    end
    return {}
end

local function uses_of(cmd)
    local k = cmd.kind
    local uses = {}
    local function add(v) if v then uses[#uses + 1] = v end end

    if k == "CmdAlias" then add(cmd.src)
    elseif k == "CmdUnary" then add(cmd.value)
    elseif k == "CmdIntrinsic" then for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
    elseif k == "CmdCompare" then add(cmd.lhs); add(cmd.rhs)
    elseif k == "CmdCast" then add(cmd.value)
    elseif k == "CmdPtrOffset" then add(cmd.index)
    elseif k == "CmdLoadInfo" then add(cmd.addr and cmd.addr.byte_offset)
    elseif k == "CmdStoreInfo" then add(cmd.addr and cmd.addr.byte_offset); add(cmd.value)
    elseif k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" or k == "CmdFloatBinary" then
        add(cmd.lhs); add(cmd.rhs)
    elseif k == "CmdBitNot" then add(cmd.value)
    elseif k == "CmdSelect" then add(cmd.cond); add(cmd.then_value); add(cmd.else_value)
    elseif k == "CmdFma" then add(cmd.a); add(cmd.b); add(cmd.c)
    elseif k == "CmdMemcpy" then add(cmd.dst); add(cmd.src); add(cmd.len)
    elseif k == "CmdMemset" then add(cmd.dst); add(cmd.byte); add(cmd.len)
    elseif k == "CmdCall" then
        for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
        if cmd.target and cmd.target.kind == "BackCallIndirect" then add(cmd.target.callee) end
    elseif k == "CmdJump" then for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
    elseif k == "CmdBrIf" then
        add(cmd.cond)
        for i = 1, #(cmd.then_args or {}) do add(cmd.then_args[i]) end
        for i = 1, #(cmd.else_args or {}) do add(cmd.else_args[i]) end
    elseif k == "CmdSwitchInt" then add(cmd.value)
    elseif k == "CmdReturnValue" then add(cmd.value)
    end

    return uses
end

local function inst_for(D, shape, cmd)
    local defs, uses = {}, {}
    local d = defs_of(cmd)
    for i = 1, #d do defs[#defs + 1] = vreg_of(D, d[i]) end
    local u = uses_of(cmd)
    for i = 1, #u do uses[#uses + 1] = vreg_of(D, u[i]) end
    return D.DAsmInst(shape, defs, uses, {})
end

local function build_const_map(facts)
    local cmap = {}
    for i = 1, #(facts.atoms or {}) do
        local a = facts.atoms[i]
        if a.kind == "DFactValueConst" then cmap[Mx.idkey(a.value)] = a.const_kind end
    end
    return cmap
end

local function label_of(D, block)
    return D.DLabelId("B_" .. Mx.to_label(Mx.idkey(block)))
end

local function addr_operand(D, addr, const_map)
    if not addr then return D.DOpMem(D.DAddress(nil, nil, 1, 0)) end
    local base = nil
    if addr.base and addr.base.kind == "BackAddrValue" then
        base = D.DPhysRegId(-1)
    end
    local disp = 0
    local bo = addr.byte_offset and const_map[Mx.idkey(addr.byte_offset)]
    if bo and bo.kind == "DConstInt" then disp = tonumber(bo.raw) or 0 end
    return D.DOpMem(D.DAddress(base, nil, 1, disp))
end

-- ─────────────────────────────────────────────────────────────────────
-- Lowering decisions - plain Lua pattern matching
-- ─────────────────────────────────────────────────────────────────────

local function decision(D, cmd_index, rule, cost, shape)
    return D.DLowerDecision(cmd_index, rule, cost, shape)
end

local function is_imm32(c)
    if not c or c.kind ~= "DConstInt" then return false end
    local n = tonumber(c.raw)
    return n and n >= -2147483648 and n <= 2147483647
end

local function is_pow2(c)
    if not c or c.kind ~= "DConstInt" then return false end
    local n = tonumber(c.raw)
    if not n or n <= 0 or math.floor(n) ~= n or n > 0x7fffffff then return false end
    return bit.band(n, n - 1) == 0
end

local function is_zero(c)
    if not c then return false end
    if c.kind == "DConstNull" then return true end
    if c.kind == "DConstInt" then return tonumber(c.raw) == 0 end
    if c.kind == "DConstFloat" then return tonumber(c.raw) == 0 end
    return false
end

local function lower_DKeyCopy(D, key, cmd, cmd_index)
    local class = key.class
    local src_const = key.src_const
    local same_value = key.same_value

    -- Priority 100: noop if same value
    if same_value then
        return decision(D, cmd_index, "copy.noop", 0, D.DAsmComment("copy noop"))
    end

    -- Priority 90: zero immediate
    if src_const and src_const.kind ~= "DConstUnknown" and is_zero(src_const) then
        return decision(D, cmd_index, "copy.zero", 1,
            D.DAsmMove(op_vreg(D, cmd.dst), D.DOpImmI64("0"), class))
    end

    -- Priority 80: register move
    return decision(D, cmd_index, "copy.mov", 2,
        D.DAsmMove(op_vreg(D, cmd.dst), op_vreg(D, cmd.src), class))
end

local function lower_DKeyIntBin(D, key, cmd, cmd_index)
    local op = key.op
    local scalar = key.scalar
    local rhs_const = key.rhs_const
    local rhs_pow2 = key.rhs_pow2

    -- Priority 100: imm32 for add/sub
    if is_imm32(rhs_const) and (op == "BackIntAdd" or op == "BackIntSub") then
        return decision(D, cmd_index, "intbin.imm32", 1,
            D.DAsmBinary(op .. ".imm", op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs),
                D.DOpImmI64(rhs_const.raw), scalar))
    end

    -- Priority 95: multiply by power of 2 -> shift
    if rhs_const and rhs_const.kind == "DConstInt" and op == "BackIntMul" and rhs_pow2 then
        local n = tonumber(rhs_const.raw)
        if n and n > 0 then
            local sh = math.floor(math.log(n) / math.log(2))
            return decision(D, cmd_index, "intbin.mul_pow2", 1,
                D.DAsmBinary("BackShiftLeft.imm", op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs),
                    D.DOpImmI64(tostring(sh)), scalar))
        end
    end

    -- Priority 80: register form
    return decision(D, cmd_index, "intbin.reg", 3,
        D.DAsmBinary(op, op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs), op_vreg(D, cmd.rhs), scalar))
end

local function lower_DKeyBitBin(D, key, cmd, cmd_index)
    local op = key.op
    local scalar = key.scalar
    local rhs_const = key.rhs_const

    -- Priority 90: immediate form
    if rhs_const and rhs_const.kind == "DConstInt" then
        return decision(D, cmd_index, "bitbin.imm", 1,
            D.DAsmBinary(op .. ".imm", op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs),
                D.DOpImmI64(rhs_const.raw), scalar))
    end

    -- Priority 80: register form
    return decision(D, cmd_index, "bitbin.reg", 2,
        D.DAsmBinary(op, op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs), op_vreg(D, cmd.rhs), scalar))
end

local function lower_DKeyShiftRotate(D, key, cmd, cmd_index)
    local op = key.op
    local scalar = key.scalar
    local rhs_const = key.rhs_const
    local rhs_small_imm = key.rhs_small_imm

    -- Priority 90: immediate form (small shift)
    if rhs_small_imm and rhs_const and rhs_const.kind == "DConstInt" then
        return decision(D, cmd_index, "shiftrotate.imm", 1,
            D.DAsmBinary(op .. ".imm", op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs),
                D.DOpImmI64(rhs_const.raw), scalar))
    end

    -- Priority 80: register form
    return decision(D, cmd_index, "shiftrotate.reg", 3,
        D.DAsmBinary(op, op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs), op_vreg(D, cmd.rhs), scalar))
end

local function lower_DKeyCompareBranch(D, key, cmd, cmd_index)
    local scalar = key.scalar
    local fused_branch = key.fused_branch

    -- Priority 95: fused with branch (handled by isel)
    if fused_branch then
        return decision(D, cmd_index, "cmp.fused-branch", 0,
            D.DAsmComment("compare fused with following branch"))
    end

    -- Priority 80: setcc form
    return decision(D, cmd_index, "cmp.setcc", 1,
        D.DAsmCompareSet(D.DccNE, op_vreg(D, cmd.dst), op_vreg(D, cmd.lhs), op_vreg(D, cmd.rhs), scalar))
end

local function lower_DKeyLoadStore(D, key, cmd, cmd_index, const_map)
    if cmd.kind == "CmdLoadInfo" then
        return decision(D, cmd_index, "mem.load", 1,
            D.DAsmLoad(op_vreg(D, cmd.dst), addr_operand(D, cmd.addr, const_map), cmd.ty))
    else
        return decision(D, cmd_index, "mem.store", 1,
            D.DAsmStore(addr_operand(D, cmd.addr, const_map), op_vreg(D, cmd.value), cmd.ty))
    end
end

local function lower_DKeyAddress(D, key, cmd, cmd_index)
    if cmd.kind == "CmdPtrOffset" then
        return decision(D, cmd_index, "addr.lea", 1,
            D.DAsmLea(op_vreg(D, cmd.dst),
                D.DOpMem(D.DAddress(D.DPhysRegId(-1), nil, cmd.elem_size or 1, cmd.const_offset or 0))))
    elseif cmd.kind == "CmdStackAddr" then
        return decision(D, cmd_index, "addr.stack", 1,
            D.DAsmLea(op_vreg(D, cmd.dst),
                D.DOpMem(D.DAddress(D.DPhysRegId(5), nil, 1, 0))))
    elseif cmd.kind == "CmdDataAddr" then
        return decision(D, cmd_index, "addr.label", 1,
            D.DAsmLea(op_vreg(D, cmd.dst),
                D.DOpLabel(D.DLabelId("D_" .. Mx.to_label(Mx.idkey(cmd.data))))))
    elseif cmd.kind == "CmdFuncAddr" then
        return decision(D, cmd_index, "addr.label", 1,
            D.DAsmLea(op_vreg(D, cmd.dst),
                D.DOpLabel(D.DLabelId("F_" .. Mx.to_label(Mx.idkey(cmd.func))))))
    elseif cmd.kind == "CmdExternAddr" then
        return decision(D, cmd_index, "addr.label", 1,
            D.DAsmLea(op_vreg(D, cmd.dst),
                D.DOpLabel(D.DLabelId("E_" .. Mx.to_label(Mx.idkey(cmd.func))))))
    end
    return decision(D, cmd_index, "addr.unknown", 99, D.DAsmComment("unknown address"))
end

local function lower_DKeyCall(D, key, cmd, cmd_index)
    local args = {}
    for i = 1, #(cmd.args or {}) do
        args[#args + 1] = op_vreg(D, cmd.args[i])
    end

    local res = nil
    if cmd.result and cmd.result.kind == "BackCallValue" then
        res = op_vreg(D, cmd.result.dst)
    end

    -- Priority 90: indirect call
    if cmd.target and cmd.target.kind == "BackCallIndirect" then
        return decision(D, cmd_index, "call.generic", 1,
            D.DAsmCall(op_vreg(D, cmd.target.callee), args, res))
    end

    -- Priority 89: direct call to function
    if cmd.target and cmd.target.kind == "BackCallDirect" then
        local op = D.DOpLabel(D.DLabelId("F_" .. Mx.to_label(Mx.idkey(cmd.target.func))))
        return decision(D, cmd_index, "call.generic", 1, D.DAsmCall(op, args, res))
    end

    -- Priority 88: call to extern
    local op = D.DOpLabel(D.DLabelId("E_" .. Mx.to_label(Mx.idkey(cmd.target.func))))
    return decision(D, cmd_index, "call.generic", 1, D.DAsmCall(op, args, res))
end

local function lower_DKeyControl(D, key, cmd, cmd_index)
    if cmd.kind == "CmdJump" then
        return decision(D, cmd_index, "ctl.jump", 1,
            D.DAsmJump(label_of(D, cmd.dest)))
    elseif cmd.kind == "CmdBrIf" then
        return decision(D, cmd_index, "ctl.brif", 1,
            D.DAsmBrIf(op_vreg(D, cmd.cond), label_of(D, cmd.then_block), label_of(D, cmd.else_block)))
    end
    return decision(D, cmd_index, "ctl.switch", 2,
        D.DAsmComment("switch lowered by fallback chain"))
end

local function lower_DKeyReturn(D, key, cmd, cmd_index)
    if cmd.kind == "CmdReturnValue" then
        return decision(D, cmd_index, "ret.value", 1,
            D.DAsmRetValue(op_vreg(D, cmd.value)))
    end
    return decision(D, cmd_index, "ret.void", 1, D.DAsmRetVoid)
end

-- ─────────────────────────────────────────────────────────────────────
-- Main lowering dispatch
-- ─────────────────────────────────────────────────────────────────────

local function lower_family(D, fi, cmd, cmd_index, const_map)
    local key = fi.key
    if not key then
        return decision(D, cmd_index, "other.nop", 99, D.DAsmComment("no key"))
    end

    local kk = key.kind
    if kk == "DKeyCopy" then
        return lower_DKeyCopy(D, key, cmd, cmd_index)
    elseif kk == "DKeyIntBin" then
        return lower_DKeyIntBin(D, key, cmd, cmd_index)
    elseif kk == "DKeyBitBin" then
        return lower_DKeyBitBin(D, key, cmd, cmd_index)
    elseif kk == "DKeyShiftRotate" then
        return lower_DKeyShiftRotate(D, key, cmd, cmd_index)
    elseif kk == "DKeyCompareBranch" then
        return lower_DKeyCompareBranch(D, key, cmd, cmd_index)
    elseif kk == "DKeyLoadStore" then
        return lower_DKeyLoadStore(D, key, cmd, cmd_index, const_map)
    elseif kk == "DKeyAddress" then
        return lower_DKeyAddress(D, key, cmd, cmd_index)
    elseif kk == "DKeyCall" then
        return lower_DKeyCall(D, key, cmd, cmd_index)
    elseif kk == "DKeyControl" then
        return lower_DKeyControl(D, key, cmd, cmd_index)
    elseif kk == "DKeyReturn" then
        return lower_DKeyReturn(D, key, cmd, cmd_index)
    end

    return decision(D, cmd_index, "other.comment", 99,
        D.DAsmComment("no specialized lowering for " .. tostring(cmd.kind)))
end

-- ─────────────────────────────────────────────────────────────────────
-- Build DAsmFunc from decisions
-- ─────────────────────────────────────────────────────────────────────

local function mk_empty_asm_func(D, facts)
    return D.DAsmFunc(Mx.back_func_id(facts.func or "<anon>"), {})
end

local function build_asm_from_decisions(D, facts, decisions)
    local shape_by_index = {}
    for i = 1, #decisions do
        shape_by_index[decisions[i].cmd_index] = decisions[i].shape
    end

    local blocks_by_key, block_order = {}, {}
    local function ensure_block(bid)
        local bk = Mx.idkey(bid)
        local b = blocks_by_key[bk]
        if b then return b end
        b = { id = bid, insts = {} }
        blocks_by_key[bk] = b
        block_order[#block_order + 1] = bk
        return b
    end

    local cur = nil
    local fallback = nil

    for i = 1, #(facts.cmds or {}) do
        local cmd = facts.cmds[i]
        if cmd.kind == "CmdCreateBlock" then
            ensure_block(cmd.block)
        elseif cmd.kind == "CmdSwitchToBlock" then
            cur = ensure_block(cmd.block)
            if not fallback then fallback = cur end
        end

        local shape = shape_by_index[i]
        if shape then
            if not cur then
                if not fallback then fallback = ensure_block(Mx.back_block_id("entry")) end
                cur = fallback
            end
            cur.insts[#cur.insts + 1] = inst_for(D, shape, cmd)
        end
    end

    local blocks = {}
    for i = 1, #block_order do
        local b = blocks_by_key[block_order[i]]
        blocks[#blocks + 1] = D.DAsmBlock(b.id, b.insts)
    end

    return D.DAsmFunc(Mx.back_func_id(facts.func or "<anon>"), blocks)
end

-- ─────────────────────────────────────────────────────────────────────
-- Phase entry point
-- ─────────────────────────────────────────────────────────────────────

local PHASE_LOWER = nil
local function lowering_phase()
    if PHASE_LOWER then return PHASE_LOWER end
    local D = Mx.dasm()

    PHASE_LOWER = pvm.phase("moonlift_dasm_lower_facts", {
        [D.DFactSet] = function(facts)
            local cmd_by_index = {}
            for i = 1, #(facts.cmds or {}) do
                cmd_by_index[i] = facts.cmds[i]
            end
            local const_map = build_const_map(facts)

            local decisions = {}
            for i = 1, #(facts.families or {}) do
                local fi = facts.families[i]
                local cmd = cmd_by_index[fi.cmd_index]
                if cmd then
                    decisions[#decisions + 1] = lower_family(D, fi, cmd, fi.cmd_index, const_map)
                end
            end

            local picked = {}
            for i = 1, #decisions do
                if decisions[i] then picked[#picked + 1] = decisions[i] end
            end

            local asm = (#picked > 0) and build_asm_from_decisions(D, facts, picked) or mk_empty_asm_func(D, facts)
            return pvm.once(D.DLoweredFunc(facts.func, facts.cmds, facts, picked, asm))
        end,
    })

    return PHASE_LOWER
end

return {
    phase = function() return lowering_phase() end,
    run = function(fact_set)
        local D = Mx.dasm()
        if pvm.classof(fact_set) ~= D.DFactSet then
            error("lower_facts.run expects MoonDasm.DFactSet", 2)
        end
        return pvm.one(lowering_phase()(fact_set))
    end,
}
