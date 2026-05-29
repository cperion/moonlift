-- ssa_atoms.lua -- atom semantic reopening from serialized/codegen op lists.

local Facts = require("src.facts")
local IR = require("src.ssa_ir")

local M = {}

local function fact(kind, subject, predicate, value)
    return Facts.fact(kind, subject, predicate, value, "atom")
end

function M.reopen_node_specs(specs, facts, config)
    local fs = getmetatable(facts) == Facts.FactSet and facts or Facts.new(facts or {})
    local g = IR.new(fs, config)
    local vmap = {}

    local function mapped_input(old)
        if not old then return nil end
        if not vmap[old] then vmap[old] = g:new_value("Unknown") end
        return vmap[old]
    end

    local function mapped_outputs(spec)
        local outs = {}
        for i, old in ipairs(spec.outputs or {}) do
            local ty = (spec.output_types and spec.output_types[i]) or "Unknown"
            local nv = g:new_value(ty)
            vmap[old] = nv
            outs[#outs + 1] = nv
        end
        if outs[#outs] then g.current = outs[#outs] end
        return outs
    end

    for pc, spec in ipairs(specs or {}) do
        local ins = {}
        for _, old in ipairs(spec.inputs or {}) do ins[#ins + 1] = mapped_input(old) end
        local outs = mapped_outputs(spec)
        local exit = nil
        if spec.effect == "guard" then exit = g:exit_projection("guard:" .. tostring(spec.guard_fact and spec.guard_fact.predicate or spec.op), pc)
        elseif spec.op == "Residual" or spec.op == "Call" or spec.op == "KnownCall" or spec.op == "TailCall" then exit = g:exit_projection(tostring(spec.op) .. "_exit", pc) end
        g:add(spec.op or spec.codegen_op, {
            inputs = ins,
            outputs = outs,
            args = spec.args or {},
            effect = spec.effect or "none",
            codegen_op = spec.codegen_op,
            guard = spec.guard_fact and { fact = spec.guard_fact, key = Facts.guard_key(spec.guard_fact) } or nil,
            deps = spec.deps or {},
            exit = exit,
            source = pc,
        })
    end
    return g
end

return M
