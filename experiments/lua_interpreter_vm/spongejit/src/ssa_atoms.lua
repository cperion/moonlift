-- ssa_atoms.lua -- atom semantic reopening from serialized/codegen op lists.

local Facts = require("src.facts")
local IR = require("src.ssa_ir")

local M = {}

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function copy_map(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

function M.reopen_node_specs(specs, facts, config)
    local fs = getmetatable(facts) == Facts.FactSet and facts or Facts.new(facts or {})
    local g = IR.new(fs, config)
    local vmap = {}

    local function mapped_input(old, ty, residency)
        if not old then return nil end
        if residency == false then residency = nil end
        if not vmap[old] then vmap[old] = g:new_value(ty or "Unknown", nil, nil, residency) end
        return vmap[old]
    end

    local function mapped_outputs(spec)
        local outs = {}
        for i, old in ipairs(spec.outputs or {}) do
            local ty = (spec.output_types and spec.output_types[i]) or "Unknown"
            local residency = spec.output_residencies and spec.output_residencies[i]
            if residency == false then residency = nil end
            local nv = g:new_value(ty, nil, nil, residency)
            vmap[old] = nv
            outs[#outs + 1] = nv
        end
        if outs[#outs] then g.current = outs[#outs] end
        return outs
    end

    for pc, spec in ipairs(specs or {}) do
        local ins = {}
        for i, old in ipairs(spec.inputs or {}) do
            local ty = spec.input_types and spec.input_types[i]
            local residency = spec.input_residencies and spec.input_residencies[i]
            ins[#ins + 1] = mapped_input(old, ty, residency)
        end
        local outs = mapped_outputs(spec)
        local exit = spec.exit and copy_map(spec.exit) or nil
        if not exit then
            if spec.effect == "guard" then exit = g:exit_projection("guard:" .. tostring(spec.guard_fact and spec.guard_fact.predicate or spec.op), spec.source or pc)
            elseif spec.op == "Residual" or spec.op == "Call" or spec.op == "KnownCall" or spec.op == "TailCall" then exit = g:exit_projection(tostring(spec.op) .. "_exit", spec.source or pc) end
        end
        g:add(spec.op or spec.codegen_op, {
            inputs = ins,
            outputs = outs,
            args = spec.args or {},
            effect = spec.effect or "none",
            codegen_op = spec.codegen_op,
            guard = spec.guard_fact and { fact = spec.guard_fact, key = Facts.guard_key(spec.guard_fact) } or nil,
            deps = copy_array(spec.deps),
            exit = exit,
            mem_in = copy_map(spec.mem_in),
            mem_out = copy_map(spec.mem_out),
            source = spec.source or pc,
        })
    end
    return g
end

return M
