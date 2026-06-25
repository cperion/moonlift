local pvm = require("lalin.pvm")
local Mx = require("back.dasm.model")

local function mk_edge_args(D, dest, args, params_by_key)
    local out = {}
    local plist = params_by_key[Mx.idkey(dest)] or {}
    for i = 1, #(args or {}) do
        local src = Mx.back_val_id(args[i])
        local dst = plist[i] and plist[i].value or src
        out[#out + 1] = D.DEdgeArg(src, dst)
    end
    return out
end

local function build_cfg_from_phase_func(pf, sig_id)
    local D = Mx.dasm()

    local body = Mx.phase_func_cmds(pf)
    local func_id = Mx.phase_func_id(pf)

    local block_order, block_by_key = {}, {}
    local params_by_key = {}
    local stack_slots, seen_slots = {}, {}

    local function push_block(bid)
        local bk = Mx.idkey(bid)
        if not block_by_key[bk] then
            block_by_key[bk] = Mx.back_block_id(bid)
            block_order[#block_order + 1] = bk
        end
    end

    for i = 1, #body do
        local cmd = body[i]
        local k = cmd.kind
        if k == "CmdCreateBlock" then
            push_block(cmd.block)
        elseif k == "CmdAppendBlockParam" then
            local bk = Mx.idkey(cmd.block)
            local arr = params_by_key[bk]
            if not arr then arr = {}; params_by_key[bk] = arr end
            arr[#arr + 1] = D.DBlockParam(Mx.back_val_id(cmd.value), cmd.ty)
        elseif k == "CmdCreateStackSlot" then
            local sk = Mx.idkey(cmd.slot)
            if not seen_slots[sk] then
                seen_slots[sk] = true
                stack_slots[#stack_slots + 1] = Mx.back_slot_id(cmd.slot)
            end
        end
    end

    local entry_block = nil
    for i = 1, #body do
        local cmd = body[i]
        if cmd.kind == "CmdSwitchToBlock" then
            entry_block = Mx.back_block_id(cmd.block)
            break
        end
    end
    if not entry_block and #block_order > 0 then entry_block = block_by_key[block_order[1]] end

    local body_by_key, term_by_key = {}, {}
    local current = nil

    for i = 1, #body do
        local cmd = body[i]
        local k = cmd.kind

        if k == "CmdSwitchToBlock" then
            current = Mx.idkey(cmd.block)
            if current and not body_by_key[current] then body_by_key[current] = {} end

        elseif k == "CmdCreateBlock" or k == "CmdAppendBlockParam" or k == "CmdSealBlock" then
            -- consumed by CFG form

        elseif current then
            local bb = body_by_key[current]

            if k == "CmdJump" then
                term_by_key[current] = D.DTermJump(Mx.back_block_id(cmd.dest), mk_edge_args(D, cmd.dest, cmd.args, params_by_key))

            elseif k == "CmdBrIf" then
                term_by_key[current] = D.DTermBrIf(
                    Mx.back_val_id(cmd.cond),
                    Mx.back_block_id(cmd.then_block),
                    mk_edge_args(D, cmd.then_block, cmd.then_args, params_by_key),
                    Mx.back_block_id(cmd.else_block),
                    mk_edge_args(D, cmd.else_block, cmd.else_args, params_by_key)
                )

            elseif k == "CmdSwitchInt" then
                local cases = {}
                for ci = 1, #(cmd.cases or {}) do
                    local c = cmd.cases[ci]
                    cases[#cases + 1] = D.DSwitchCase(c.raw, Mx.back_block_id(c.dest))
                end
                term_by_key[current] = D.DTermSwitch(Mx.back_val_id(cmd.value), cmd.ty, cases, Mx.back_block_id(cmd.default_dest))

            elseif k == "CmdReturnVoid" then
                term_by_key[current] = D.DTermReturnVoid

            elseif k == "CmdReturnValue" then
                term_by_key[current] = D.DTermReturnValue(Mx.back_val_id(cmd.value))

            elseif k == "CmdTrap" then
                term_by_key[current] = D.DTermTrap

            else
                bb[#bb + 1] = cmd
            end
        end
    end

    local blocks = {}
    for i = 1, #block_order do
        local bk = block_order[i]
        local params = params_by_key[bk] or {}
        local cmds = body_by_key[bk] or {}
        local term = term_by_key[bk] or D.DTermTrap
        blocks[#blocks + 1] = D.DCfgBlock(block_by_key[bk], params, cmds, term)
    end

    return D.DFuncCFG(
        Mx.back_func_id(func_id or "<anon>"),
        Mx.back_sig_id(sig_id or "<unknown_sig>"),
        entry_block or Mx.back_block_id("entry"),
        blocks,
        stack_slots
    )
end

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local D = Mx.dasm()

    PHASE = pvm.phase("lalin_dasm_build_cfg", {
        [D.DPhaseFunc] = function(pf, sig_id)
            return pvm.once(build_cfg_from_phase_func(pf, sig_id))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(phase_func, sig_id)
        local D = Mx.dasm()
        if pvm.classof(phase_func) ~= D.DPhaseFunc then
            error("build_cfg.run expects LalinDasm.DPhaseFunc", 2)
        end
        return pvm.one(phase()(phase_func, Mx.back_sig_id(sig_id or "<unknown_sig>")))
    end,
}
