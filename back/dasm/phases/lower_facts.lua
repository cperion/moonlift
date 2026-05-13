local pvm = require("moonlift.pvm")
local Lisle = require("moonlift.lisle.runtime")
local Mx = require("back.dasm.model")
local RULE_TEXT = require("back.dasm.rules.lower_facts_lisle")

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
        base = D.DPhysRegId(-1) -- symbolic pre-alloc marker
    end
    local disp = 0
    local bo = addr.byte_offset and const_map[Mx.idkey(addr.byte_offset)]
    if bo and bo.kind == "DConstInt" then disp = tonumber(bo.raw) or 0 end
    return D.DOpMem(D.DAddress(base, nil, 1, disp))
end

local RULES = nil
local function get_rules()
    if RULES then return RULES end
    local mod = Lisle.load(RULE_TEXT, "dasm_lower_facts_lisle")
    RULES = mod
    return RULES
end

local function make_rule_ctx(D)
    return {
        D = D,
        idkey = Mx.idkey,
        to_label = Mx.to_label,
        op_vreg = function(v) return op_vreg(D, v) end,
        addr_operand = function(addr, const_map) return addr_operand(D, addr, const_map) end,
        label_of = function(block) return label_of(D, block) end,
        decision = function(cmd_index, rule, cost, shape)
            return D.DLowerDecision(cmd_index, rule, cost, shape)
        end,
    }
end

local function mk_empty_asm_func(D, facts)
    return D.DAsmFunc(Mx.back_func_id(facts.func or "<anon>"), {})
end

local function build_asm_from_decisions(D, facts, decisions)
    local shape_by_index = {}
    for i = 1, #decisions do shape_by_index[decisions[i].cmd_index] = decisions[i].shape end

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

local PHASE_LOWER = nil
local function lowering_phase()
    if PHASE_LOWER then return PHASE_LOWER end
    local D = Mx.dasm()

    PHASE_LOWER = pvm.phase("moonlift_dasm_lower_facts", {
        [D.DFactSet] = function(facts)
            local cmd_by_index = {}
            for i = 1, #(facts.cmds or {}) do cmd_by_index[i] = facts.cmds[i] end
            local const_map = build_const_map(facts)

            local decisions = {}
            local rule_ctx = make_rule_ctx(D)
            local decide = get_rules().lower_rule
            for i = 1, #(facts.families or {}) do
                local fi = facts.families[i]
                local cmd = cmd_by_index[fi.cmd_index]
                if cmd then
                    decisions[#decisions + 1] = decide(rule_ctx, fi.key, fi, cmd, const_map)
                end
            end

            table.sort(decisions, function(a, b)
                if a.cmd_index ~= b.cmd_index then return a.cmd_index < b.cmd_index end
                if a.cost ~= b.cost then return a.cost < b.cost end
                return a.rule < b.rule
            end)

            local best = {}
            for i = 1, #decisions do
                local d = decisions[i]
                if not best[d.cmd_index] then best[d.cmd_index] = d end
            end

            local picked = {}
            for i = 1, #(facts.cmds or {}) do
                local d = best[i]
                if d then picked[#picked + 1] = d end
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
