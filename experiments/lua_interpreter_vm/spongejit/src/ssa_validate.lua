-- ssa_validate.lua -- invariant checks for real fact/SSA layer.

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate(g, config)
    config = config or {}
    local errors = {}
    if g.invalid then
        for _, r in ipairs(g.invalid_reasons or {}) do add(errors, r) end
        return false, errors
    end
    local ok_graph, graph_errors = g:validate()
    if not ok_graph then for _, e in ipairs(graph_errors) do add(errors, e) end end

    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            if n.effect == "guard" then
                if not n.guard or not n.guard.fact then add(errors, "guard node missing fact at " .. n.id) end
                if not n.exit then add(errors, "guard node missing exit projection at " .. n.id) end
            end
            if (n.op == "Residual" or n.op == "GenericExit" or n.op == "Call" or n.op == "KnownCall" or n.op == "TailCall") and not n.exit then
                add(errors, n.op .. " missing exit projection at " .. n.id)
            end
            if n.op == "FrameLoad" and not (n.args and n.args.slot) then add(errors, "FrameLoad missing slot at " .. n.id) end
            if n.op == "FrameStore" and not (n.args and n.args.slot) then add(errors, "FrameStore missing slot at " .. n.id) end
        end
    end

    return #errors == 0, errors
end

function M.lowerable(g, cover_set)
    local errors = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            local op = n.codegen_op or n.op
            if cover_set and not cover_set[op] then add(errors, "no stencil cover for " .. tostring(op) .. " at node " .. n.id) end
        end
    end
    return #errors == 0, errors
end

return M
