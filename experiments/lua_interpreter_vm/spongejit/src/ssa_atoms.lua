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

function M.reopen_codegen_ops(codegen_ops, facts, config)
    local fs = getmetatable(facts) == Facts.FactSet and facts or Facts.new(facts or {})
    local g = IR.new(fs, config)
    local rcx = nil

    for pc, op in ipairs(codegen_ops or {}) do
        if op == "load_slot" then
            g:frame_load("cur", "TValue", pc)
        elseif op == "store_slot" then
            if g.current then g:store_current(g.current, "cur", pc) end
        elseif op == "load_const" then
            g:load_const("K", pc)
        elseif op == "const_i64" then
            rcx = g:const_i64(0, pc)
        elseif op == "const_nil" then
            g:const_nil(pc)
        elseif op == "const_bool" then
            g:const_bool(true, pc)
        elseif op == "move_value" then
            local v = g:slot_value("cur")
            local out = g:new_value("TValue")
            g:add("Move", { inputs = { v }, outputs = { out }, source = pc })
            g.current = out
        elseif op == "guard_i64" then
            local v = g:slot_value("cur")
            g:guard(v, fact("type", Facts.value("last"), "is_i64"), "GuardTypeI64", pc)
        elseif op == "guard_table" then
            local v = g:slot_value("cur")
            g:guard(v, fact("type", Facts.value("table"), "is_table"), "GuardTable", pc)
        elseif op == "guard_shape" then
            local v = g:slot_value("cur")
            g:guard(v, fact("shape", Facts.value("table"), "shape_known", true), "GuardShape", pc)
        elseif op == "guard_metatable_absent" then
            local v = g:slot_value("cur")
            g:guard(v, fact("metatable", Facts.value("table"), "metatable_absent", true), "GuardMetatableAbsent", pc)
        elseif op == "guard_call_target" then
            local v = g:slot_value("cur")
            g:guard(v, fact("call", Facts.value("callee"), "known_call_target", true), "GuardCallTarget", pc)
        elseif op == "guard_array_hit" then
            local v = g:slot_value("cur")
            g:guard(v, fact("array", Facts.value("table"), "array_hit", true), "GuardArrayHit", pc)
        elseif op == "guard_bounds" then
            local v = g:slot_value("cur")
            g:guard(v, fact("array", Facts.value("table"), "bounds_ok", true), "GuardBounds", pc)
        elseif op == "unbox_i64" then
            rcx = g:unbox_i64(g:slot_value("cur"), pc)
        elseif op == "box_i64" then
            g:box_i64(rcx or g:slot_value("cur"), pc)
        elseif op == "add_i64" or op == "sub_i64" or op == "mul_i64" then
            local rhs = g:frame_load("rhs", "TValue", pc)
            local rhs_i = g:unbox_i64(rhs, pc)
            local source_op = op == "sub_i64" and "SUB" or (op == "mul_i64" and "MUL" or "ADD")
            rcx = g:i64_arith(source_op, rcx or g:slot_value("cur"), rhs_i, pc)
        elseif op == "cmp_i64" then
            local rhs = g:frame_load("rhs", "TValue", pc)
            local rhs_i = g:unbox_i64(rhs, pc)
            local out = g:new_value("Bool")
            g:add("CmpI64", { inputs = { rcx or g:slot_value("cur"), rhs_i }, outputs = { out }, source = pc })
            g.current = out
        elseif op == "table_field_load" then
            local tab = g:slot_value("cur")
            g:field_load(tab, "const_key", pc)
        elseif op == "table_field_store" then
            local val = g:slot_value("cur")
            local tab = g:frame_load("tab", "TValue", pc)
            g:field_store(tab, "const_key", val, pc)
        elseif op == "table_array_load" then
            g:array_load(g:slot_value("cur"), pc)
        elseif op == "table_array_store" then
            local val = g:slot_value("cur")
            local tab = g:frame_load("tab", "TValue", pc)
            g:array_store(tab, val, pc)
        elseif op == "barrier_check" then
            local val = g:slot_value("cur")
            local tab = g:frame_load("tab", "TValue", pc)
            g:barrier(tab, val, pc)
        elseif op == "call_boundary" then
            local r = g:call("generic", g:slot_value("cur"), pc)
            g:store_current(r, "cur", pc)
        elseif op == "call_boundary_known" then
            local r = g:call("known", g:slot_value("cur"), pc)
            g:store_current(r, "cur", pc)
        elseif op == "tailcall_boundary" then
            g:add("TailCall", { inputs = { g:slot_value("cur") }, source = pc, effect = "call", exit = g:exit_projection("tailcall", pc) })
        elseif op == "return0" then
            g:return0(pc)
        elseif op == "return1" then
            g:return1(g:slot_value("cur"), pc)
        elseif op == "residual_boundary" then
            g:residual("ATOM_RESIDUAL", { g:slot_value("cur") }, pc)
        elseif op == "jump" then
            g:add("Jump", { inputs = { g:slot_value("cur") }, source = pc, effect = "branch", exit = g:exit_projection("jump", pc) })
        elseif op == "branch" then
            g:add("Branch", { inputs = { g:slot_value("cur") }, source = pc, effect = "branch", exit = g:exit_projection("branch", pc) })
        else
            g:residual(op, { g:slot_value("cur") }, pc)
        end
    end

    return g
end

return M
