-- ssa_lift.lua -- lift opcode windows to typed SSA with explicit memory.

local Facts = require("src.facts")
local IR = require("src.ssa_ir")

local M = {}

local function factset_of(facts)
    if getmetatable(facts) == Facts.FactSet then return facts end
    return Facts.new(facts or {})
end

local function op_name(x) return type(x) == "table" and tostring(x.op or x.name or x[1] or "?") or tostring(x) end
local function slot_name(n) return n ~= nil and ("R" .. tostring(n)) or "cur" end

local function implies(fs, predicate, subject, value)
    return fs:implies(predicate, subject, value)
end

local function implies_any(fs, predicate, subjects, value)
    for _, s in ipairs(subjects or {}) do
        if s and fs:implies(predicate, s, value) then return true, s end
    end
    return false, nil
end

local function value_fact(kind, subject, predicate, value)
    return Facts.fact(kind, subject, predicate, value, "assumed")
end

local function guard_if(g, subject_value, fact, op, pc)
    g:guard(subject_value, fact, op, pc)
end

local function ensure_i64(g, v, role, pc, slot)
    local subjects = { slot and Facts.slot(slot), Facts.value(role or "lhs"), Facts.value("last") }
    local ok, subject = implies_any(g.factset, "is_i64", subjects)
    if ok then
        guard_if(g, v, value_fact("type", subject or Facts.value(role or "lhs"), "is_i64"), "GuardTypeI64", pc)
        return g:unbox_i64(v, pc), true
    end
    return v, false
end

local function specialize_arith(g, op, immediate, pc, ev)
    local dst = slot_name(type(ev) == "table" and ev.a)
    local lhs_slot = slot_name(type(ev) == "table" and ev.b)
    local rhs_slot = slot_name(type(ev) == "table" and ev.c)
    local lhs_t = g:frame_load(lhs_slot, "TValue", pc)
    local lhs_i, lhs_ok = ensure_i64(g, lhs_t, "lhs", pc, lhs_slot)
    local rhs_i, rhs_ok
    if immediate then
        rhs_i = g:const_i64(immediate, pc)
        rhs_ok = true
    else
        local rhs_t = g:frame_load(rhs_slot, "TValue", pc)
        rhs_i, rhs_ok = ensure_i64(g, rhs_t, "rhs", pc, rhs_slot)
    end
    if lhs_ok and rhs_ok then
        local native = g:i64_arith(op, lhs_i, rhs_i, pc)
        local boxed = g:box_i64(native, pc)
        g:store_current(boxed, dst, pc)
    else
        local r = g:residual(op, { lhs_t }, pc)
        g:store_current(r, dst, pc)
    end
end

local function table_subject(slot) return slot and Facts.slot(slot) or Facts.value("table") end
local function key_subject(k) return k ~= nil and Facts.value("K" .. tostring(k)) or Facts.value("key") end

local function guard_table_facts(g, tab, table_slot, array_mode, pc)
    local ts = table_subject(table_slot)
    if implies(g.factset, "is_table", ts) or implies(g.factset, "is_table", Facts.value("table")) then
        guard_if(g, tab, value_fact("type", ts, "is_table"), "GuardTable", pc)
    end
    if implies(g.factset, "shape_known", ts) or implies(g.factset, "shape_known", Facts.value("table")) then
        guard_if(g, tab, value_fact("shape", ts, "shape_known", true), "GuardShape", pc)
    end
    if implies(g.factset, "metatable_absent", ts) or implies(g.factset, "metatable_absent", Facts.value("table")) then
        guard_if(g, tab, value_fact("metatable", ts, "metatable_absent", true), "GuardMetatableAbsent", pc)
    end
    if array_mode and (implies(g.factset, "array_hit", ts) or implies(g.factset, "array_hit", Facts.value("table"))) then
        guard_if(g, tab, value_fact("array", ts, "array_hit", true), "GuardArrayHit", pc)
    end
    if array_mode and (implies(g.factset, "bounds_ok", ts) or implies(g.factset, "bounds_ok", Facts.value("table"))) then
        guard_if(g, tab, value_fact("array", ts, "bounds_ok", true), "GuardBounds", pc)
    end
end

local function can_direct_field(g, table_slot, key)
    local ts = table_subject(table_slot)
    return (implies(g.factset, "is_table", ts) or implies(g.factset, "is_table", Facts.value("table")))
       and (implies(g.factset, "shape_known", ts) or implies(g.factset, "shape_known", Facts.value("table")))
       and (implies(g.factset, "metatable_absent", ts) or implies(g.factset, "metatable_absent", Facts.value("table")))
       and (implies(g.factset, "key_const", key_subject(key)) or implies(g.factset, "key_const", Facts.value("key")))
end

local function can_direct_array(g, table_slot, key_slot)
    local ts = table_subject(table_slot)
    local ks = key_slot and Facts.slot(key_slot) or Facts.value("key")
    return (implies(g.factset, "array_hit", ts) or implies(g.factset, "array_hit", Facts.value("table")))
       and (implies(g.factset, "metatable_absent", ts) or implies(g.factset, "metatable_absent", Facts.value("table")))
       and (implies(g.factset, "key_i64", ks) or implies(g.factset, "key_i64", Facts.value("key")))
end

local function lift_getfield(g, opcode, pc, ev)
    local dst = slot_name(type(ev) == "table" and ev.a)
    local table_slot = slot_name(type(ev) == "table" and ev.b)
    local key = type(ev) == "table" and ev.c or nil
    local tab = g:frame_load(table_slot, "TValue", pc)
    guard_table_facts(g, tab, table_slot, false, pc)
    if can_direct_field(g, table_slot, key) then
        local v = g:field_load(tab, "K" .. tostring(key or "const_key"), pc)
        g:store_current(v, dst, pc)
    else
        local r = g:residual(opcode, { tab }, pc)
        g:store_current(r, dst, pc)
    end
end

local function lift_setfield(g, opcode, pc, ev)
    local table_slot = slot_name(type(ev) == "table" and ev.a)
    local key = type(ev) == "table" and ev.b or nil
    local value_slot = slot_name(type(ev) == "table" and ev.c)
    local tab = g:frame_load(table_slot, "TValue", pc)
    local val = g:frame_load(value_slot, "TValue", pc)
    guard_table_facts(g, tab, table_slot, false, pc)
    if not implies(g.factset, "barrier_clean", Facts.global_subject()) then g:barrier(tab, val, pc) end
    if can_direct_field(g, table_slot, key) then g:field_store(tab, "K" .. tostring(key or "const_key"), val, pc) else g:residual(opcode, { tab, val }, pc) end
end

local function lift_gettable(g, opcode, pc, ev)
    local dst = slot_name(type(ev) == "table" and ev.a)
    local table_slot = slot_name(type(ev) == "table" and ev.b)
    local key_slot = slot_name(type(ev) == "table" and ev.c)
    local tab = g:frame_load(table_slot, "TValue", pc)
    guard_table_facts(g, tab, table_slot, true, pc)
    if can_direct_array(g, table_slot, key_slot) then
        local v = g:array_load(tab, pc)
        g:store_current(v, dst, pc)
    else
        local r = g:residual(opcode, { tab }, pc)
        g:store_current(r, dst, pc)
    end
end

local function lift_settable(g, opcode, pc, ev)
    local table_slot = slot_name(type(ev) == "table" and ev.a)
    local key_slot = slot_name(type(ev) == "table" and ev.b)
    local value_slot = slot_name(type(ev) == "table" and ev.c)
    local tab = g:frame_load(table_slot, "TValue", pc)
    local val = g:frame_load(value_slot, "TValue", pc)
    guard_table_facts(g, tab, table_slot, true, pc)
    if not implies(g.factset, "barrier_clean", Facts.global_subject()) then g:barrier(tab, val, pc) end
    if can_direct_array(g, table_slot, key_slot) then g:array_store(tab, val, pc) else g:residual(opcode, { tab, val }, pc) end
end

function M.lift(ops, facts, config)
    local fs = factset_of(facts)
    local g = IR.new(fs, config)
    if not fs:ok() then
        g.invalid = true
        g.invalid_reasons = fs:contradictions()
        return g
    end

    for pc, ev in ipairs(ops or {}) do
        local op = op_name(ev)
        local A, B = type(ev) == "table" and ev.a, type(ev) == "table" and ev.b
        if op == "MOVE" then
            local v = g:frame_load(slot_name(B), "TValue", pc)
            local out = g:new_value("TValue")
            g:add("Move", { inputs = { v }, outputs = { out }, source = pc })
            g:store_current(out, slot_name(A), pc)
        elseif op == "LOADK" then
            local v = g:load_const("K" .. tostring(type(ev) == "table" and ev.bx or ""), pc)
            g:store_current(v, slot_name(A), pc)
        elseif op == "LOADI" then
            local i = g:const_i64((type(ev) == "table" and (ev.sbx or ev.bx)) or 0, pc)
            local v = g:box_i64(i, pc)
            g:store_current(v, slot_name(A), pc)
        elseif op == "LOADTRUE" or op == "LOADFALSE" then
            local v = g:const_bool(op == "LOADTRUE", pc)
            g:store_current(v, slot_name(A), pc)
        elseif op == "LOADNIL" then
            local v = g:const_nil(pc)
            g:store_current(v, slot_name(A), pc)
        elseif op == "ADD" or op == "SUB" or op == "MUL" then
            specialize_arith(g, op, nil, pc, ev)
        elseif op == "ADDI" then
            specialize_arith(g, op, 1, pc, ev)
        elseif op == "EQ" or op == "EQI" or op == "LT" or op == "LE" or op == "LTI" or op == "LEI" or op == "GTI" or op == "GEI" then
            local lhs_slot = slot_name(type(ev) == "table" and ev.b)
            local rhs_slot = slot_name(type(ev) == "table" and ev.c)
            local lhs_t = g:frame_load(lhs_slot, "TValue", pc)
            local lhs_i, ok = ensure_i64(g, lhs_t, "lhs", pc, lhs_slot)
            if ok then
                local rhs = g:frame_load(rhs_slot, "TValue", pc)
                local rhs_i = g:unbox_i64(rhs, pc)
                local out = g:new_value("Bool")
                g:add("CmpI64", { inputs = { lhs_i, rhs_i }, outputs = { out }, source = pc })
                g:store_current(out, slot_name(A), pc)
            else
                local r = g:residual(op, { lhs_t }, pc)
                g:store_current(r, slot_name(A), pc)
            end
        elseif op == "GETFIELD" or op == "GETTABUP" then
            lift_getfield(g, op, pc, ev)
        elseif op == "SELF" then
            lift_getfield(g, op, pc, ev)
            local recv = g:frame_load(slot_name(type(ev) == "table" and ev.b), "TValue", pc)
            g:store_current(recv, slot_name((type(ev) == "table" and ev.a or 0) + 1), pc)
        elseif op == "SETFIELD" or op == "SETTABUP" then
            lift_setfield(g, op, pc, ev)
        elseif op == "GETTABLE" or op == "GETI" then
            lift_gettable(g, op, pc, ev)
        elseif op == "SETTABLE" then
            lift_settable(g, op, pc, ev)
        elseif op == "CALL" then
            local fn_slot = slot_name(A)
            local fn = g:frame_load(fn_slot, "TValue", pc)
            if implies(g.factset, "known_call_target", Facts.slot(fn_slot)) or implies(g.factset, "known_call_target", Facts.value("callee")) or implies(g.factset, "known_call_target", Facts.value("last")) then
                guard_if(g, fn, value_fact("call", Facts.slot(fn_slot), "known_call_target", true), "GuardCallTarget", pc)
                local r = g:call("known", fn, pc)
                g:store_current(r, fn_slot, pc)
            else
                local r = g:call("generic", fn, pc)
                g:store_current(r, fn_slot, pc)
            end
        elseif op == "TAILCALL" then
            local fn = g:frame_load(slot_name(A), "TValue", pc)
            g:add("TailCall", { inputs = { fn }, source = pc, effect = "call", exit = g:exit_projection("tailcall", pc) })
        elseif op == "RETURN0" then
            g:return0(pc)
        elseif op == "RETURN" or op == "RETURN1" then
            g:return1(g:frame_load(slot_name(A), "TValue", pc), pc)
        elseif op == "JMP" then
            g:add("Jump", { inputs = { g:slot_value("cur") }, source = pc, effect = "branch", exit = g:exit_projection("jump", pc) })
        else
            local r = g:residual(op, { g:slot_value("cur") }, pc)
            g:store_current(r, slot_name(A), pc)
        end
    end

    return g
end

return M
