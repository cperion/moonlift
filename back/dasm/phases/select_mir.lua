local pvm = require("moonlift.pvm")
local Mx = require("back.dasm.model")

local function lower_cfg_to_backcmd(cfg)
    local B = Mx.back()

    local function edge_values(edge_args)
        local vals = {}
        for i = 1, #(edge_args or {}) do vals[#vals + 1] = edge_args[i].src end
        return vals
    end

    local function lower_term(term)
        local tk = term and term.kind

        if tk == "DTermJump" then
            return B.CmdJump(term.dest, edge_values(term.args))

        elseif tk == "DTermBrIf" then
            return B.CmdBrIf(term.cond, term.then_block, edge_values(term.then_args), term.else_block, edge_values(term.else_args))

        elseif tk == "DTermSwitch" then
            local cases = {}
            for i = 1, #(term.cases or {}) do
                local c = term.cases[i]
                cases[#cases + 1] = B.BackSwitchCase(c.raw, c.dest)
            end
            return B.CmdSwitchInt(term.value, term.ty, cases, term.default_dest)

        elseif tk == "DTermReturnValue" then
            return B.CmdReturnValue(term.value)

        elseif tk == "DTermReturnVoid" then
            return B.CmdReturnVoid

        elseif tk == "DTermTrap" then
            return B.CmdTrap
        end

        error("select_mir: unsupported terminator kind: " .. tostring(tk))
    end

    local out = {}

    for i = 1, #cfg.blocks do
        local block = cfg.blocks[i]
        out[#out + 1] = B.CmdCreateBlock(block.id)
        for j = 1, #(block.params or {}) do
            local p = block.params[j]
            out[#out + 1] = B.CmdAppendBlockParam(block.id, p.value, p.ty)
        end
    end

    for i = 1, #cfg.blocks do
        local block = cfg.blocks[i]
        out[#out + 1] = B.CmdSwitchToBlock(block.id)
        for j = 1, #(block.body or {}) do out[#out + 1] = block.body[j] end
        out[#out + 1] = lower_term(block.term)
        out[#out + 1] = B.CmdSealBlock(block.id)
    end

    return Mx.make_phase_func(out, cfg.func)
end

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local D = Mx.dasm()

    PHASE = pvm.phase("moonlift_dasm_select_mir", {
        [D.DFuncCFG] = function(cfg)
            return pvm.once(lower_cfg_to_backcmd(cfg))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(cfg)
        return pvm.one(phase()(cfg))
    end,
}
