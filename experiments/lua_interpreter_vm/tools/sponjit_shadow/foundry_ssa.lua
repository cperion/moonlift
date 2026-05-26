-- foundry_ssa.lua
-- Offline, VM-shaped SSA engine for SponJIT shadow/foundry experiments.
--
-- This is deliberately not a runtime compiler. It expands opcode/atom tuples into
-- a small semantic SSA graph, applies fact-driven specialization, runs conservative
-- local simplifications, and returns a semantic normal form suitable for foundry
-- proposal/scoring.

local Util = require("tools.jit_harness.util")

local M = {}

local PURE = {
    const_nil = true, const_bool = true, const_i64 = true, const_f64 = true,
    load_slot = true, load_const = true, tag_of = true, bits_of = true,
    box_i64 = true, box_f64 = true, unbox_i64 = true, unbox_f64 = true,
    add_i64 = true, sub_i64 = true, mul_i64 = true, add_f64 = true,
    cmp_i64 = true, cmp_f64 = true, truthy_test = true,
    move_value = true,
    table_field_load = true, table_array_load = true,
}

local EFFECT = {
    store_slot = "frame_write",
    table_field_store = "heap_write",
    table_array_store = "heap_write",
    barrier_check = "gc_barrier",
    call_boundary = "call",
    call_boundary_known = "call",
    tailcall_boundary = "call",
    residual_boundary = "residual",
    return0 = "return",
    return1 = "return",
    returnN = "return",
    branch = "branch",
    jump = "branch",
}

local HARD_BARRIER = {
    call_boundary = true,
    call_boundary_known = true,
    tailcall_boundary = true,
    residual_boundary = true,
}

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function set_from(xs)
    local out = {}
    for _, x in ipairs(xs or {}) do out[x] = true end
    return out
end

local function has(set, x) return set and set[x] or false end

local function join(xs, sep) return table.concat(xs or {}, sep or "|") end

local function starts(s, prefix) return tostring(s or ""):sub(1, #prefix) == prefix end

local Graph = {}
Graph.__index = Graph

function Graph.new(facts, config)
    return setmetatable({
        nodes = {},
        next_id = 1,
        next_value = 1,
        facts = set_from(facts or {}),
        fact_list = copy_array(facts or {}),
        config = config or {},
        current = nil,
        stats = { guards = 0, removed = 0, barriers = 0 },
    }, Graph)
end

function Graph:value(prefix)
    local v = string.format("%s%d", prefix or "v", self.next_value)
    self.next_value = self.next_value + 1
    return v
end

function Graph:add(op, inputs, args)
    args = args or {}
    local n = {
        id = self.next_id,
        op = op,
        inputs = copy_array(inputs or {}),
        args = args,
        result = args.result,
        result_type = args.result_type,
        source_span = args.source_span,
        effect_class = args.effect_class or EFFECT[op] or (starts(op, "guard_") and "guard" or "pure"),
        deps = copy_array(args.deps or {}),
        projection_obligation = args.projection_obligation,
        residency_class = args.residency_class,
        flags = args.flags or {},
        removed = false,
    }
    if args.result == true then n.result = self:value(args.result_prefix or "v") end
    self.next_id = self.next_id + 1
    self.nodes[#self.nodes + 1] = n
    if starts(op, "guard_") then self.stats.guards = self.stats.guards + 1 end
    if HARD_BARRIER[op] then self.stats.barriers = self.stats.barriers + 1 end
    return n
end

function Graph:guard(op, subject, fact, deps)
    local n = self:add(op, { subject }, {
        fact = fact,
        deps = deps,
        projection_obligation = "guard_exit",
        result = nil,
    })
    return n
end

function Graph:slot_value()
    if self.current then return self.current end
    local n = self:add("load_slot", {}, { result = true, result_prefix = "slot", result_type = "value" })
    self.current = n.result
    return self.current
end

function Graph:store_current(v)
    self.current = v
    self:add("store_slot", { v }, {})
end

local function deps_for_fact(f)
    if f == "shape_known" then return { "shape_epoch" } end
    if f == "metatable_absent" then return { "metatable_epoch" } end
    if f == "known_call_target" then return { "call_target_epoch" } end
    if f == "barrier_clean" then return { "gc_barrier_protocol" } end
    return nil
end

local function specialize_number(g, v, side)
    if has(g.facts, side .. "_i64") or (side == "lhs" and has(g.facts, "last_i64")) then
        g:guard("guard_i64", v, side .. "_i64", deps_for_fact(side .. "_i64"))
        local u = g:add("unbox_i64", { v }, { result = true, result_prefix = "i", result_type = "i64" })
        return u.result, "i64"
    end
    return v, "value"
end

local function generic_or_i64_arith(g, op, immediate)
    local lhs = g:slot_value()
    local lv, lt = specialize_number(g, lhs, "lhs")
    local rv, rt
    if immediate then
        local c = g:add("const_i64", {}, { result = true, result_prefix = "c", result_type = "i64", value = immediate })
        rv, rt = c.result, "i64"
    else
        local rhs = g:add("load_slot", {}, { result = true, result_prefix = "rhs", result_type = "value" })
        rv, rt = specialize_number(g, rhs.result, "rhs")
    end
    if lt == "i64" and rt == "i64" then
        local map = { ADD = "add_i64", ADDI = "add_i64", SUB = "sub_i64", MUL = "mul_i64" }
        local a = g:add(map[op] or "add_i64", { lv, rv }, { result = true, result_prefix = "i", result_type = "i64", residency_class = "fixed_gpr0" })
        local b = g:add("box_i64", { a.result }, { result = true, result_prefix = "v", result_type = "value" })
        g:store_current(b.result)
    else
        local n = g:add("residual_boundary", { lhs }, { opcode = op, result = true, result_prefix = "v", result_type = "value" })
        g:store_current(n.result)
    end
end

local function expand_getfield(g, op)
    local tab = g:slot_value()
    if has(g.facts, "table") then g:guard("guard_table", tab, "table") end
    if has(g.facts, "shape_known") then g:guard("guard_shape", tab, "shape_known", deps_for_fact("shape_known")) end
    if has(g.facts, "metatable_absent") then g:guard("guard_metatable_absent", tab, "metatable_absent", deps_for_fact("metatable_absent")) end
    if has(g.facts, "shape_known") and has(g.facts, "key_const") and has(g.facts, "metatable_absent") then
        local n = g:add("table_field_load", { tab }, { result = true, result_prefix = "fld", result_type = "value", key = "const_key" })
        g:store_current(n.result)
    else
        local n = g:add("residual_boundary", { tab }, { opcode = op, result = true, result_prefix = "v", result_type = "value" })
        g:store_current(n.result)
    end
end

local function expand_setfield(g, op)
    local val = g:slot_value()
    local tab = g:add("load_slot", {}, { result = true, result_prefix = "tab", result_type = "value" })
    if has(g.facts, "table") then g:guard("guard_table", tab.result, "table") end
    if has(g.facts, "shape_known") then g:guard("guard_shape", tab.result, "shape_known", deps_for_fact("shape_known")) end
    if has(g.facts, "metatable_absent") then g:guard("guard_metatable_absent", tab.result, "metatable_absent", deps_for_fact("metatable_absent")) end
    if not has(g.facts, "barrier_clean") then g:add("barrier_check", { tab.result, val }, { projection_obligation = "barrier_slow_path" }) end
    if has(g.facts, "shape_known") and has(g.facts, "key_const") and has(g.facts, "metatable_absent") then
        g:add("table_field_store", { tab.result, val }, { key = "const_key" })
    else
        g:add("residual_boundary", { tab.result, val }, { opcode = op })
    end
end

local function expand_gettable(g, op)
    local tab = g:slot_value()
    if has(g.facts, "table") then g:guard("guard_table", tab, "table") end
    if has(g.facts, "array_hit") then g:guard("guard_array_hit", tab, "array_hit") end
    if has(g.facts, "metatable_absent") then g:guard("guard_metatable_absent", tab, "metatable_absent", deps_for_fact("metatable_absent")) end
    if has(g.facts, "array_hit") and has(g.facts, "key_i64") and has(g.facts, "metatable_absent") then
        local n = g:add("table_array_load", { tab }, { result = true, result_prefix = "elt", result_type = "value" })
        g:store_current(n.result)
    else
        local n = g:add("residual_boundary", { tab }, { opcode = op, result = true, result_prefix = "v", result_type = "value" })
        g:store_current(n.result)
    end
end

local function expand_settable(g, op)
    local val = g:slot_value()
    local tab = g:add("load_slot", {}, { result = true, result_prefix = "tab", result_type = "value" })
    if has(g.facts, "table") then g:guard("guard_table", tab.result, "table") end
    if has(g.facts, "array_hit") then g:guard("guard_array_hit", tab.result, "array_hit") end
    if has(g.facts, "metatable_absent") then g:guard("guard_metatable_absent", tab.result, "metatable_absent", deps_for_fact("metatable_absent")) end
    if not has(g.facts, "barrier_clean") then g:add("barrier_check", { tab.result, val }, { projection_obligation = "barrier_slow_path" }) end
    if has(g.facts, "array_hit") and has(g.facts, "key_i64") and has(g.facts, "metatable_absent") then
        g:add("table_array_store", { tab.result, val }, {})
    else
        g:add("residual_boundary", { tab.result, val }, { opcode = op })
    end
end

function M.expand(ops, facts, config)
    local g = Graph.new(facts, config)
    for pc, op in ipairs(ops or {}) do
        if op == "MOVE" then
            local v = g:slot_value()
            local n = g:add("move_value", { v }, { result = true, result_prefix = "mv", result_type = "value", source_span = pc })
            g:store_current(n.result)
        elseif op == "LOADK" then
            local n = g:add("load_const", {}, { result = true, result_prefix = "k", result_type = "value", source_span = pc })
            g:store_current(n.result)
        elseif op == "LOADI" then
            local n = g:add("const_i64", {}, { result = true, result_prefix = "i", result_type = "i64", source_span = pc })
            local b = g:add("box_i64", { n.result }, { result = true, result_prefix = "v", result_type = "value" })
            g:store_current(b.result)
        elseif op == "LOADTRUE" or op == "LOADFALSE" then
            local n = g:add("const_bool", {}, { result = true, result_prefix = "b", result_type = "value", value = op == "LOADTRUE", source_span = pc })
            g:store_current(n.result)
        elseif op == "LOADNIL" then
            local n = g:add("const_nil", {}, { result = true, result_prefix = "nil", result_type = "value", source_span = pc })
            g:store_current(n.result)
        elseif op == "ADD" or op == "SUB" or op == "MUL" then
            generic_or_i64_arith(g, op, nil)
        elseif op == "ADDI" then
            generic_or_i64_arith(g, op, 1)
        elseif op == "EQ" or op == "EQI" or op == "LT" or op == "LE" then
            local lhs = g:slot_value()
            local lv = specialize_number(g, lhs, "lhs")
            local cmp = g:add("cmp_i64", { lv }, { result = true, result_prefix = "cmp", result_type = "bool", source_span = pc })
            g:store_current(cmp.result)
        elseif op == "GETFIELD" or op == "GETTABUP" or op == "SELF" then
            expand_getfield(g, op)
            if op == "SELF" then
                g:add("project_virtual_value", { g.current }, { projection_obligation = "self_receiver" })
            end
        elseif op == "SETFIELD" or op == "SETTABUP" then
            expand_setfield(g, op)
        elseif op == "GETTABLE" then
            expand_gettable(g, op)
        elseif op == "SETTABLE" then
            expand_settable(g, op)
        elseif op == "CALL" then
            local f = g:slot_value()
            if has(g.facts, "known_call_target") then
                g:guard("guard_call_target", f, "known_call_target", deps_for_fact("known_call_target"))
                local n = g:add("call_boundary_known", { f }, { result = true, result_prefix = "ret", result_type = "value", projection_obligation = "call_exit" })
                g:store_current(n.result)
            else
                local n = g:add("call_boundary", { f }, { result = true, result_prefix = "ret", result_type = "value", projection_obligation = "call_exit" })
                g:store_current(n.result)
            end
        elseif op == "TAILCALL" then
            g:add("tailcall_boundary", { g:slot_value() }, { projection_obligation = "tailcall_exit" })
        elseif op == "RETURN0" then
            g:add("return0", {}, { projection_obligation = "return" })
        elseif op == "RETURN" or op == "RETURN1" then
            g:add("return1", { g:slot_value() }, { projection_obligation = "return" })
        elseif op == "JMP" then
            g:add("jump", { g:slot_value() }, {})
        else
            local n = g:add("residual_boundary", { g:slot_value() }, { opcode = op, result = true, result_prefix = "res", result_type = "value" })
            g:store_current(n.result)
        end
    end
    return g
end

local function replace_inputs(nodes, alias)
    for _, n in ipairs(nodes) do
        for i, v in ipairs(n.inputs or {}) do
            while alias[v] do v = alias[v] end
            n.inputs[i] = v
        end
    end
end

local function result_producer(nodes)
    local by = {}
    for _, n in ipairs(nodes) do if n.result then by[n.result] = n end end
    return by
end

local function pass_copy_forward(g)
    local alias = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed and n.op == "move_value" and n.inputs[1] then
            alias[n.result] = n.inputs[1]
            n.removed = true
            n.remove_reason = "copy_forward"
            g.stats.removed = g.stats.removed + 1
        end
    end
    replace_inputs(g.nodes, alias)
end

local function pass_box_unbox(g)
    local prod = result_producer(g.nodes)
    local alias = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed and n.op == "unbox_i64" then
            local p = prod[n.inputs[1]]
            if p and not p.removed and p.op == "box_i64" then
                alias[n.result] = p.inputs[1]
                n.removed = true
                n.remove_reason = "box_unbox"
                g.stats.removed = g.stats.removed + 1
            end
        end
    end
    replace_inputs(g.nodes, alias)
end

local function pass_guard_dedupe(g)
    local seen = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed and starts(n.op, "guard_") then
            local fact = (n.args and n.args.fact) or n.op  -- fallback to op name for compiled nodes
            local k = n.op .. ":" .. tostring(n.inputs[1] or "") .. ":" .. tostring(fact)
            if seen[k] then
                n.removed = true
                n.remove_reason = "redundant_guard"
                g.stats.removed = g.stats.removed + 1
            else
                seen[k] = true
            end
        end
    end
end

local function pass_dce(g)
    local used = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed then
            for _, v in ipairs(n.inputs or {}) do used[v] = true end
        end
    end
    for _, n in ipairs(g.nodes) do
        if not n.removed and n.result and PURE[n.op] and not used[n.result] then
            n.removed = true
            n.remove_reason = "dead_value"
            g.stats.removed = g.stats.removed + 1
        end
    end
end

function M.optimize(g)
    pass_copy_forward(g)
    pass_box_unbox(g)
    pass_guard_dedupe(g)
    pass_dce(g)
    return g
end

local function active_ops(g)
    local out = {}
    for _, n in ipairs(g.nodes or {}) do if not n.removed then out[#out + 1] = n.op end end
    return out
end

local function facts_have(facts, xs)
    local s = set_from(facts or {})
    for _, x in ipairs(xs or {}) do if not s[x] then return false end end
    return true
end

local function source_normal_form(ops, facts, g)
    local out = {}
    local i = 1
    while i <= #(ops or {}) do
        local a, b, c = ops[i], ops[i + 1], ops[i + 2]
        if (a == "LOADK" or a == "LOADI" or a == "LOADTRUE" or a == "LOADFALSE" or a == "LOADNIL") and b == "MOVE" then
            out[#out + 1] = a .. "_DIRECT"
            i = i + 2
        elseif (a == "ADD" or a == "ADDI" or a == "SUB" or a == "MUL") and b == "RETURN1" and facts_have(facts, { "returns_prev" }) then
            out[#out + 1] = a .. "_RETURN1"
            i = i + 2
        elseif a == "SELF" and b == "MOVE" and c == "CALL" and facts_have(facts, { "known_call_target" }) then
            out[#out + 1] = "SELF_CALL"
            i = i + 3
        elseif a == "GETFIELD" and b == "ADDI" and c == "SETFIELD" and facts_have(facts, { "table", "shape_known", "metatable_absent", "key_const", "lhs_i64" }) then
            out[#out + 1] = "FIELD_ADDI_UPDATE"
            i = i + 3
        elseif a == "GETTABLE" and b == "ADD" and c == "SETTABLE" and facts_have(facts, { "table", "array_hit", "metatable_absent", "key_i64", "lhs_i64", "rhs_i64" }) then
            out[#out + 1] = "ARRAY_ADD_UPDATE"
            i = i + 3
        else
            out[#out + 1] = a
            i = i + 1
        end
    end
    return out
end

local function collect_deps(g)
    local seen, out = {}, {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            for _, d in ipairs(n.deps or {}) do
                if not seen[d] then seen[d] = true; out[#out + 1] = d end
            end
        end
    end
    table.sort(out)
    return out
end

local function collect_checked_facts(g)
    local seen, out = {}, {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and starts(n.op, "guard_") and n.args and n.args.fact then
            local f = n.args.fact
            if not seen[f] then seen[f] = true; out[#out + 1] = f end
        end
    end
    table.sort(out)
    return out
end

local function projection_summary(g)
    local exits, virtuals = 0, 0
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            if n.projection_obligation then exits = exits + 1 end
            if n.op == "project_virtual_value" then virtuals = virtuals + 1 end
        end
    end
    return { exit_obligations = exits, virtual_values = virtuals, ok = true }
end

local function budget_ok(g, config)
    config = config or {}
    local gpr_live = 0
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.residency_class == "fixed_gpr0" then gpr_live = math.max(gpr_live, 1) end
    end
    return gpr_live <= (tonumber(config.max_live_gpr or 2) or 2)
end

function M.compile(ops, facts, config)
    facts = facts or {}
    local g = M.expand(ops, facts, config)
    M.optimize(g)
    return M.summarize(g, ops, facts, config)
end

function M.compile_nodes(node_ops, facts, config)
    facts = facts or {}
    local g = Graph.new(facts, config)
    for _, nop in ipairs(node_ops or {}) do
        if nop == "residual_boundary" then
            g:add("residual_boundary", { g:slot_value() }, {})
        elseif starts(nop, "guard_") then
            -- Reconstruct guard with proper fact for cross-atom dedup
            local fact_map = {
                guard_i64 = "lhs_i64", guard_table = "table", guard_shape = "shape_known",
                guard_metatable_absent = "metatable_absent", guard_call_target = "known_call_target",
                guard_array_hit = "array_hit", guard_bounds = "bounds",
            }
            local fact = fact_map[nop]
            local subject = g.current  -- guards check the current value
            g:add(nop, { subject }, { fact = fact or nop, projection_obligation = "guard_exit" })
        elseif nop == "store_slot" then
            g:add("store_slot", { g.current }, {})
        elseif nop == "load_slot" then
            local n = g:add("load_slot", {}, { result = true, result_prefix = "slot", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "load_const" then
            local n = g:add("load_const", {}, { result = true, result_prefix = "k", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "const_i64" then
            local n = g:add("const_i64", {}, { result = true, result_prefix = "c", result_type = "i64" })
            g:store_current(n.result)
        elseif nop == "const_nil" then
            local n = g:add("const_nil", {}, { result = true, result_prefix = "nil", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "const_bool" then
            local n = g:add("const_bool", {}, { result = true, result_prefix = "b", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "move_value" then
            local v = g:slot_value()
            local n = g:add("move_value", { v }, { result = true, result_prefix = "mv", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "box_i64" then
            local v = g:slot_value()
            local n = g:add("box_i64", { v }, { result = true, result_prefix = "v", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "unbox_i64" then
            local v = g:slot_value()
            local n = g:add("unbox_i64", { v }, { result = true, result_prefix = "i", result_type = "i64" })
            g:store_current(n.result)
        elseif nop == "add_i64" or nop == "sub_i64" or nop == "mul_i64" then
            local rhs = g:add("load_slot", {}, { result = true, result_prefix = "rhs", result_type = "i64" })
            local lhs = g:add("load_slot", {}, { result = true, result_prefix = "lhs", result_type = "i64" })
            local n = g:add(nop, { lhs.result, rhs.result }, { result = true, result_prefix = "ar", result_type = "i64", residency_class = "fixed_gpr0" })
            g:store_current(n.result)
        elseif nop == "cmp_i64" then
            local rhs = g:add("load_slot", {}, { result = true, result_prefix = "rhs", result_type = "i64" })
            local lhs = g:add("load_slot", {}, { result = true, result_prefix = "lhs", result_type = "i64" })
            local n = g:add("cmp_i64", { lhs.result, rhs.result }, { result = true, result_prefix = "cmp", result_type = "bool" })
            g:store_current(n.result)
        elseif nop == "table_field_load" then
            local tab = g:slot_value()
            local n = g:add("table_field_load", { tab }, { result = true, result_prefix = "fld", result_type = "value", key = "const_key" })
            g:store_current(n.result)
        elseif nop == "table_field_store" then
            local val = g:slot_value()
            local tab = g:add("load_slot", {}, { result = true, result_prefix = "tab", result_type = "value" })
            g:add("table_field_store", { tab.result, val }, { key = "const_key" })
        elseif nop == "table_array_load" then
            local tab = g:slot_value()
            local n = g:add("table_array_load", { tab }, { result = true, result_prefix = "elt", result_type = "value" })
            g:store_current(n.result)
        elseif nop == "table_array_store" then
            local val = g:slot_value()
            local tab = g:add("load_slot", {}, { result = true, result_prefix = "tab", result_type = "value" })
            g:add("table_array_store", { tab.result, val }, {})
        elseif nop == "call_boundary" or nop == "call_boundary_known" then
            local f = g:slot_value()
            local n = g:add(nop, { f }, { result = true, result_prefix = "ret", result_type = "value", projection_obligation = "call_exit" })
            g:store_current(n.result)
        elseif nop == "tailcall_boundary" then
            g:add("tailcall_boundary", { g:slot_value() }, { projection_obligation = "tailcall_exit" })
        elseif nop == "return0" then
            g:add("return0", {}, { projection_obligation = "return" })
        elseif nop == "return1" then
            g:add("return1", { g:slot_value() }, { projection_obligation = "return" })
        elseif nop == "barrier_check" then
            local val = g:slot_value()
            local tab = g:add("load_slot", {}, { result = true, result_prefix = "tab", result_type = "value" })
            g:add("barrier_check", { tab.result, val }, { projection_obligation = "barrier_slow_path" })
        end
    end
    M.optimize(g)
    return M.summarize(g, node_ops, facts, config)
end

function M.summarize(g, source_ops, facts, config)
    local nf = source_normal_form(source_ops or {}, facts or {}, g)
    local active = active_ops(g)
    local proj = projection_summary(g)
    local ok = proj.ok and budget_ok(g, config)
    local text = join(nf, "|") .. " :: " .. join(collect_checked_facts(g), ",")
    return {
        ok = ok,
        graph = g,
        normal_form = nf,
        normal_form_hash = Util.stable_hash(text),
        active_ops = active,
        checked_facts = collect_checked_facts(g),
        deps = collect_deps(g),
        projection = proj,
        stats = g.stats,
    }
end

function M.semantic_normal_form(ops, facts, config)
    return M.compile(ops, facts, config).normal_form
end

function M.normal_form_hash(ops, facts, config)
    local r = M.compile(ops, facts, config)
    return r.normal_form_hash, r.normal_form, r
end

return M
