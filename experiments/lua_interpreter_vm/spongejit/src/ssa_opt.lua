-- ssa_opt.lua -- typed SSA optimization over explicit values and memory.

local IR = require("src.ssa_ir")

local M = {}

local function starts(s, prefix) return tostring(s or ""):sub(1, #prefix) == prefix end

local function outputs_of(n) return n.outputs or {} end
local function inputs_of(n) return n.inputs or {} end

local function replace_inputs(g, alias)
    local function root(v)
        local seen = {}
        while alias[v] and not seen[v] do seen[v] = true; v = alias[v] end
        return v
    end
    for _, n in ipairs(g.nodes or {}) do
        for i, v in ipairs(n.inputs or {}) do n.inputs[i] = root(v) end
    end
end

local function result_producer(g)
    local prod = {}
    for _, n in ipairs(g.nodes or {}) do
        for _, v in ipairs(outputs_of(n)) do prod[v] = n end
    end
    return prod
end

local function use_counts(g)
    local used = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            for _, v in ipairs(inputs_of(n)) do used[v] = (used[v] or 0) + 1 end
        end
    end
    return used
end

local function remove(g, n, why)
    if not n.removed then
        n.removed = true
        n.remove_reason = why
        g.stats.removed = (g.stats.removed or 0) + 1
    end
end

local function pass_copy_forward(g)
    local alias = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.op == "Move" and n.inputs[1] and n.outputs[1] then
            alias[n.outputs[1]] = n.inputs[1]
            remove(g, n, "copy_forward")
        end
    end
    replace_inputs(g, alias)
end

local function pass_box_unbox(g)
    local prod = result_producer(g)
    local alias = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.op == "UnboxI64" and n.inputs[1] and n.outputs[1] then
            local p = prod[n.inputs[1]]
            if p and not p.removed and p.op == "BoxI64" and p.inputs[1] then
                alias[n.outputs[1]] = p.inputs[1]
                remove(g, n, "box_unbox")
            end
        elseif not n.removed and n.op == "BoxI64" and n.inputs[1] and n.outputs[1] then
            local p = prod[n.inputs[1]]
            if p and not p.removed and p.op == "UnboxI64" and p.inputs[1] then
                alias[n.outputs[1]] = p.inputs[1]
                remove(g, n, "unbox_box")
            end
        end
    end
    replace_inputs(g, alias)
end

local function pass_guard_dominance(g)
    local seen = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.effect == "guard" and n.guard then
            local k = n.guard.key or (n.op .. ":" .. tostring(n.inputs[1]))
            if seen[k] then remove(g, n, "dominated_guard") else seen[k] = true end
        end
        if not n.removed and IR.HARD_BARRIER[n.op] then
            -- Calls/residuals can invalidate facts not covered by dependency epochs.
            -- Keep shape/metatable/call target guards dominated across code only if deps remain valid;
            -- for now, be conservative and clear domination at hard VM boundaries.
            seen = {}
        end
    end
end

local function pass_frame_forward(g)
    -- Real frame forwarding: slot identity, not adjacency. A FrameStore(slot, v)
    -- makes later FrameLoad(slot) alias v until another store/barrier invalidates it.
    local last_store = {}
    local alias = {}
    for _, n in ipairs(g.nodes or {}) do
        if n.removed then goto continue end
        if n.op == "FrameStore" then
            local slot = tostring((n.args and n.args.slot) or "cur")
            last_store[slot] = n.inputs[1]
        elseif n.op == "FrameLoad" then
            local slot = tostring((n.args and n.args.slot) or "cur")
            local v = last_store[slot]
            if v and n.outputs[1] then
                while alias[v] do v = alias[v] end
                alias[n.outputs[1]] = v
                remove(g, n, "frame_load_forward")
            end
        elseif IR.HARD_BARRIER[n.op] then
            last_store = {}
        end
        ::continue::
    end
    replace_inputs(g, alias)
end

local function pass_dead_frame_store(g)
    -- A frame store is dead if the same slot is overwritten before any load or
    -- hard boundary. This is correct because exit projection at a hard boundary
    -- may need the frame, so boundaries stop the analysis.
    for i, n in ipairs(g.nodes or {}) do
        if not n.removed and n.op == "FrameStore" then
            local slot = tostring((n.args and n.args.slot) or "cur")
            local used = false
            for j = i + 1, #g.nodes do
                local m = g.nodes[j]
                if m.removed then goto continue_dead end
                if IR.HARD_BARRIER[m.op] or m.effect == "return_" or m.effect == "guard" then used = true; break end
                if m.op == "FrameLoad" and tostring((m.args and m.args.slot) or "cur") == slot then used = true; break end
                if m.op == "FrameStore" and tostring((m.args and m.args.slot) or "cur") == slot then break end
                ::continue_dead::
            end
            if not used then remove(g, n, "dead_frame_store") end
        end
    end
end

local function same_field(a, b)
    return a and b and a.args and b.args and tostring(a.args.key) == tostring(b.args.key)
end

local function pass_field_forward(g)
    -- If FieldStore(table,key,v) is followed by FieldLoad(same table,key) before
    -- another heap write/call/residual, forward v. Shape/key facts make this exact.
    local alias = {}
    local last = nil
    for _, n in ipairs(g.nodes or {}) do
        if n.removed then goto continue end
        if n.op == "FieldStore" then
            last = n
        elseif n.op == "FieldLoad" and last and same_field(last, n) and last.inputs[1] == n.inputs[1] then
            if n.outputs[1] and last.inputs[2] then
                alias[n.outputs[1]] = last.inputs[2]
                remove(g, n, "field_load_forward")
            end
        elseif n.effect == "heap_write" or IR.HARD_BARRIER[n.op] then
            last = nil
        end
        ::continue::
    end
    replace_inputs(g, alias)
end

local function pass_barrier_elim(g)
    if not g.factset or not g.factset:implies("barrier_clean") then return end
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.op == "BarrierCheck" then remove(g, n, "barrier_clean") end
    end
end

local function pass_constant_fold(g)
    local prod = result_producer(g)
    local alias = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and (n.op == "AddI64" or n.op == "SubI64" or n.op == "MulI64") then
            local a, b = prod[n.inputs[1]], prod[n.inputs[2]]
            if a and b and a.op == "ConstI64" and b.op == "ConstI64" and a.args and b.args then
                local av, bv = tonumber(a.args.value or 0) or 0, tonumber(b.args.value or 0) or 0
                local r = n.op == "AddI64" and (av + bv) or (n.op == "SubI64" and (av - bv) or (av * bv))
                n.op = "ConstI64"
                n.codegen_op = "const_i64"
                n.inputs = {}
                n.args = { value = r }
                n.effect = "none"
            end
        end
    end
    replace_inputs(g, alias)
end

local function pass_dce(g)
    local changed = true
    while changed do
        changed = false
        local used = use_counts(g)
        for _, n in ipairs(g.nodes or {}) do
            if not n.removed and IR.PURE_OP[n.op] then
                local all_dead = true
                for _, v in ipairs(outputs_of(n)) do if (used[v] or 0) > 0 then all_dead = false; break end end
                if all_dead and #(outputs_of(n)) > 0 then remove(g, n, "dead_value"); changed = true end
            end
        end
    end
end

function M.optimize(g, config)
    config = config or {}
    if g.invalid then return g end
    pass_copy_forward(g)
    pass_box_unbox(g)
    pass_frame_forward(g)
    pass_field_forward(g)
    pass_guard_dominance(g)
    pass_barrier_elim(g)
    pass_dead_frame_store(g)
    pass_constant_fold(g)
    pass_dce(g)
    return g
end

return M
