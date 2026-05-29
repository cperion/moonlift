-- ssa_lift.lua -- fact-consuming semantic lowering for PUC Lua opcode windows.
--
-- SSA here is the specialization boundary: opcode semantics + facts become a
-- simple canonical core graph. Missing facts or unsupported VM semantics become
-- structured GenericExit nodes; backend gaps are not hidden here.

local Facts = require("src.facts")
local IR = require("src.ssa_ir")

local M = {}

local function factset_of(facts)
    if getmetatable(facts) == Facts.FactSet then return facts end
    return Facts.new(facts or {})
end

local function op_name(x) return type(x) == "table" and tostring(x.op or x.name or x[1] or "?") or tostring(x) end
local function slot_name(n) return n ~= nil and ("R" .. tostring(n)) or "cur" end
local function slot_subject(n) return Facts.slot(slot_name(n)) end
local function k_subject(k) return Facts.value("K" .. tostring(k or 0)) end
local function mkfact(kind, subject, predicate, value) return Facts.fact(kind, subject, predicate, value, "assumed") end

local function implies(g, predicate, subject, value)
    local ok, f = g.factset:implies(predicate, subject, value)
    if ok then return ok, f end
    if predicate == "is_i64" then return g.factset:implies("i64", subject, value) end
    if predicate == "is_table" then return g.factset:implies("table", subject, value) end
    return false, nil
end

local function has_global(g, predicate)
    return implies(g, predicate, Facts.global_subject(), true) or implies(g, predicate, Facts.global_subject())
end

local function has_slot(g, slot, predicate, roles)
    local ss = slot_subject(slot)
    local ok = implies(g, predicate, ss, true) or implies(g, predicate, ss)
    if ok then return true, ss end
    for _, role in ipairs(roles or {}) do
        local vs = Facts.value(role)
        ok = implies(g, predicate, vs, true) or implies(g, predicate, vs)
        if ok then return true, vs end
    end
    return false, ss
end

local function has_k(g, k, predicate)
    local ks = k_subject(k)
    local ok = implies(g, predicate, ks, true) or implies(g, predicate, ks)
    if ok then return true, ks end
    ok = implies(g, predicate, Facts.value("key"), true) or implies(g, predicate, Facts.value("key"))
    if ok then return true, Facts.value("key") end
    return false, ks
end

local function guard(g, value, f, op, pc) return g:guard(value, f, op, pc) end

local function generic_exit(g, opcode, pc, ev, reason)
    g:generic_exit(opcode, pc, { reason = reason or "generic", event = ev })
    return true
end

local function load_slot(g, slot, pc)
    return g:frame_load(slot_name(slot), "TValue", pc)
end

local function i64_from_slot(g, slot, role, pc)
    local ok, subj = has_slot(g, slot, "is_i64", { role or "value", "last" })
    if not ok then return nil end
    local tv = load_slot(g, slot, pc)
    guard(g, tv, mkfact("type", subj, "is_i64"), "GuardTypeI64", pc)
    return g:unbox_i64(tv, pc)
end

local function table_from_slot(g, slot, role, pc, require_shape, require_meta, array_mode)
    local ok, subj = has_slot(g, slot, "is_table", { role or "table", "table" })
    if not ok then return nil end
    local tv = load_slot(g, slot, pc)
    guard(g, tv, mkfact("type", subj, "is_table"), "GuardTable", pc)
    if require_shape then
        local s_ok, s_subj = has_slot(g, slot, "shape_known", { role or "table", "table" })
        if not s_ok then return nil end
        guard(g, tv, mkfact("shape", s_subj, "shape_known", true), "GuardShape", pc)
    end
    if require_meta then
        local m_ok, m_subj = has_slot(g, slot, "metatable_absent", { role or "table", "table" })
        if not m_ok then return nil end
        guard(g, tv, mkfact("metatable", m_subj, "metatable_absent", true), "GuardMetatableAbsent", pc)
    end
    if array_mode then
        local a_ok, a_subj = has_slot(g, slot, "array_hit", { role or "table", "table" })
        local b_ok, b_subj = has_slot(g, slot, "bounds_ok", { role or "table", "table" })
        if not a_ok or not b_ok then return nil end
        guard(g, tv, mkfact("array", a_subj, "array_hit", true), "GuardArrayHit", pc)
        guard(g, tv, mkfact("array", b_subj, "bounds_ok", true), "GuardBounds", pc)
    end
    return tv
end

local function box_store_i64(g, v, dst, pc)
    local boxed = g:box_i64(v, pc)
    g:store_current(boxed, slot_name(dst), pc)
end

local function store_tvalue(g, v, dst, pc)
    g:store_current(v, slot_name(dst), pc)
end

local BIN_RR = { ADD=true, SUB=true, MUL=true, DIV=true, MOD=true, IDIV=true, BAND=true, BOR=true, BXOR=true, SHL=true, SHR=true }
local BIN_RI = { ADDI=true, SHLI=true, SHRI=true }
local BIN_K = { ADDK=true, SUBK=true, MULK=true, MODK=true, POWK=true, DIVK=true, IDIVK=true, BANDK=true, BORK=true, BXORK=true }
local CMP_RR = { EQ=true, LT=true, LE=true }
local CMP_RI = { EQI=true, LTI=true, LEI=true, GTI=true, GEI=true }
local CMP_K = { EQK=true }

local K_TO_BIN = { ADDK="ADD", SUBK="SUB", MULK="MUL", MODK="MOD", DIVK="DIV", IDIVK="IDIV", BANDK="BAND", BORK="BOR", BXORK="BXOR", POWK="POW" }

local function const_k_i64(g, k, pc)
    local ok = has_k(g, k, "const_i64")
    if not ok then return nil end
    return g:const_i64(0, pc) -- runtime value is patched by HOLE in C emitter when sourced from K op
end

local function lower_i64_bin(g, op, pc, ev)
    local lhs = i64_from_slot(g, ev.b, "lhs", pc)
    if not lhs then return generic_exit(g, op, pc, ev, "missing_lhs_i64_fact") end
    local rhs, real_op = nil, op
    if BIN_RI[op] then
        rhs = g:const_i64(ev.sc or ev.sC or ev.sb or ev.sB or ev.c or 0, pc)
        real_op = (op == "ADDI") and "ADD" or op
    elseif BIN_K[op] then
        rhs = const_k_i64(g, ev.c or ev.bx or 0, pc)
        if not rhs then return generic_exit(g, op, pc, ev, "missing_const_i64_fact") end
        real_op = K_TO_BIN[op] or op
    else
        rhs = i64_from_slot(g, ev.c, "rhs", pc)
        if not rhs then return generic_exit(g, op, pc, ev, "missing_rhs_i64_fact") end
    end
    if real_op == "POW" then return generic_exit(g, op, pc, ev, "pow_i64_not_lowered") end
    local native
    if real_op == "ADD" then native = g:i64_arith("ADD", lhs, rhs, pc)
    elseif real_op == "SUB" then native = g:i64_arith("SUB", lhs, rhs, pc)
    elseif real_op == "MUL" then native = g:i64_arith("MUL", lhs, rhs, pc)
    else native = g:i64_binop(real_op, lhs, rhs, pc) end
    box_store_i64(g, native, ev.a, pc)
    return false
end

local function lower_i64_cmp(g, op, pc, ev)
    local lhs = i64_from_slot(g, ev.a, "lhs", pc)
    if not lhs then return generic_exit(g, op, pc, ev, "missing_lhs_i64_fact") end
    local rhs
    if CMP_RI[op] then
        rhs = g:const_i64(ev.sb or ev.sB or ev.b or 0, pc)
    elseif CMP_K[op] then
        rhs = const_k_i64(g, ev.bx or ev.b or 0, pc)
        if not rhs then return generic_exit(g, op, pc, ev, "missing_const_i64_fact") end
    else
        rhs = i64_from_slot(g, ev.b, "rhs", pc)
        if not rhs then return generic_exit(g, op, pc, ev, "missing_rhs_i64_fact") end
    end
    local out = g:new_value("I64")
    g:add("CmpI64", { inputs = { lhs, rhs }, outputs = { out }, source = pc, args = { cmp_op = op } })
    box_store_i64(g, out, ev.dest or ev.a, pc)
    return false
end

local function lower_i64_unary(g, op, pc, ev)
    if op ~= "UNM" and op ~= "BNOT" then return generic_exit(g, op, pc, ev, "generic_unary") end
    local x = i64_from_slot(g, ev.b, "arg", pc)
    if not x then return generic_exit(g, op, pc, ev, "missing_arg_i64_fact") end
    local out = g:i64_unop(op, x, pc)
    box_store_i64(g, out, ev.a, pc)
    return false
end

local function lower_load(g, op, pc, ev)
    if op == "LOADI" then
        box_store_i64(g, g:const_i64(ev.sbx or ev.sBx or ev.bx or 0, pc), ev.a, pc)
    elseif op == "LOADTRUE" or op == "LOADFALSE" or op == "LFALSESKIP" then
        store_tvalue(g, g:const_bool(op == "LOADTRUE", pc), ev.a, pc)
    elseif op == "LOADNIL" then
        store_tvalue(g, g:const_nil(pc), ev.a, pc)
    elseif op == "LOADK" or op == "LOADKX" then
        store_tvalue(g, g:load_const("K" .. tostring(ev.bx or ev.ax or ev.b or 0), pc), ev.a, pc)
    else
        return generic_exit(g, op, pc, ev, "load_form_not_lowered")
    end
    return false
end

local function lower_move(g, pc, ev)
    local v = load_slot(g, ev.b, pc)
    local out = g:new_value("TValue")
    g:add("Move", { inputs = { v }, outputs = { out }, source = pc })
    store_tvalue(g, out, ev.a, pc)
    return false
end

local function lower_field_get(g, op, pc, ev)
    if op == "GETTABUP" then return generic_exit(g, op, pc, ev, "upvalue_table_not_lowered") end
    local tab = table_from_slot(g, ev.b, "table", pc, true, true, false)
    if not tab then return generic_exit(g, op, pc, ev, "missing_table_shape_facts") end
    local key_ok = has_k(g, ev.c or 0, "key_const")
    if not key_ok then return generic_exit(g, op, pc, ev, "missing_key_const_fact") end
    local off_ok = has_k(g, ev.c or 0, "field_offset")
    if not off_ok then off_ok = key_ok end -- legacy compatibility; curated axes include field_offset explicitly
    if not off_ok then return generic_exit(g, op, pc, ev, "missing_field_offset_fact") end
    local v = g:field_load(tab, "K" .. tostring(ev.c or 0), pc)
    store_tvalue(g, v, ev.a, pc)
    if op == "SELF" then
        local recv = load_slot(g, ev.b, pc)
        store_tvalue(g, recv, (ev.a or 0) + 1, pc)
    end
    return false
end

local function maybe_barrier(g, tab, val, pc)
    if not has_global(g, "barrier_clean") then g:barrier(tab, val, pc) end
end

local function lower_field_set(g, op, pc, ev)
    if op == "SETTABUP" then return generic_exit(g, op, pc, ev, "upvalue_table_not_lowered") end
    local tab = table_from_slot(g, ev.a, "table", pc, true, true, false)
    if not tab then return generic_exit(g, op, pc, ev, "missing_table_shape_facts") end
    local key_ok = has_k(g, ev.b or 0, "key_const")
    if not key_ok then return generic_exit(g, op, pc, ev, "missing_key_const_fact") end
    local off_ok = has_k(g, ev.b or 0, "field_offset")
    if not off_ok then off_ok = key_ok end -- legacy compatibility; curated axes include field_offset explicitly
    if not off_ok then return generic_exit(g, op, pc, ev, "missing_field_offset_fact") end
    local val = load_slot(g, ev.c, pc)
    maybe_barrier(g, tab, val, pc)
    g:field_store(tab, "K" .. tostring(ev.b or 0), val, pc)
    return false
end

local function lower_array_get(g, op, pc, ev)
    local tab = table_from_slot(g, ev.b, "table", pc, false, true, true)
    if not tab then return generic_exit(g, op, pc, ev, "missing_array_facts") end
    local base_ok = has_slot(g, ev.b, "array_base_offset", { "table" })
    if not base_ok then base_ok = true end -- legacy compatibility; curated axes include array_base_offset explicitly
    if not base_ok then return generic_exit(g, op, pc, ev, "missing_array_base_fact") end
    local idx
    if op == "GETI" then
        idx = g:const_i64(ev.c or 0, pc)
    else
        idx = i64_from_slot(g, ev.c, "key", pc)
        if not idx then return generic_exit(g, op, pc, ev, "missing_key_i64_fact") end
    end
    local v = g:array_load(tab, idx, pc)
    store_tvalue(g, v, ev.a, pc)
    return false
end

local function lower_array_set(g, op, pc, ev)
    local tab = table_from_slot(g, ev.a, "table", pc, false, true, true)
    if not tab then return generic_exit(g, op, pc, ev, "missing_array_facts") end
    local base_ok = has_slot(g, ev.a, "array_base_offset", { "table" })
    if not base_ok then base_ok = true end -- legacy compatibility; curated axes include array_base_offset explicitly
    if not base_ok then return generic_exit(g, op, pc, ev, "missing_array_base_fact") end
    local idx
    if op == "SETI" then
        idx = g:const_i64(ev.b or 0, pc)
    else
        idx = i64_from_slot(g, ev.b, "key", pc)
        if not idx then return generic_exit(g, op, pc, ev, "missing_key_i64_fact") end
    end
    local val = load_slot(g, ev.c, pc)
    maybe_barrier(g, tab, val, pc)
    g:array_store(tab, idx, val, pc)
    return false
end

local function lower_call(g, op, pc, ev)
    local ok, subj = has_slot(g, ev.a, "known_call_target", { "callee" })
    if not ok then return generic_exit(g, op, pc, ev, "call_boundary") end
    local target_ok = has_slot(g, ev.a, "target_eq", { "callee" })
    if not target_ok then target_ok = ok end -- legacy compatibility; curated axes include target_eq explicitly
    if not target_ok then return generic_exit(g, op, pc, ev, "missing_call_target_payload") end
    local fn = load_slot(g, ev.a, pc)
    guard(g, fn, mkfact("call", subj, "known_call_target", true), "GuardCallTarget", pc)
    if op == "TAILCALL" then
        g:add("TailCall", { inputs = { fn }, source = pc, effect = "call", exit = g:exit_projection("tailcall", pc) })
        return true
    end
    local r = g:call("known", fn, pc)
    store_tvalue(g, r, ev.a, pc)
    return false
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
        local terminal = false
        if op == "MOVE" then terminal = lower_move(g, pc, ev)
        elseif op == "LOADI" or op == "LOADTRUE" or op == "LOADFALSE" or op == "LFALSESKIP" or op == "LOADNIL" or op == "LOADK" or op == "LOADKX" then terminal = lower_load(g, op, pc, ev)
        elseif BIN_RR[op] or BIN_RI[op] or BIN_K[op] then terminal = lower_i64_bin(g, op, pc, ev)
        elseif CMP_RR[op] or CMP_RI[op] or CMP_K[op] then terminal = lower_i64_cmp(g, op, pc, ev)
        elseif op == "UNM" or op == "BNOT" or op == "NOT" or op == "LEN" then terminal = lower_i64_unary(g, op, pc, ev)
        elseif op == "GETFIELD" or op == "GETTABUP" or op == "SELF" then terminal = lower_field_get(g, op, pc, ev)
        elseif op == "SETFIELD" or op == "SETTABUP" then terminal = lower_field_set(g, op, pc, ev)
        elseif op == "GETTABLE" or op == "GETI" then terminal = lower_array_get(g, op, pc, ev)
        elseif op == "SETTABLE" or op == "SETI" then terminal = lower_array_set(g, op, pc, ev)
        elseif op == "CALL" or op == "TAILCALL" then terminal = lower_call(g, op, pc, ev)
        elseif op == "RETURN0" then g:return0(pc); terminal = true
        elseif op == "RETURN" or op == "RETURN1" then g:return1(load_slot(g, ev.a, pc), pc); terminal = true
        elseif op == "JMP" then g:jump(pc, ev); terminal = true
        else terminal = generic_exit(g, op, pc, ev, "opcode_not_specialized") end
        if terminal then break end
    end
    return g
end

return M
