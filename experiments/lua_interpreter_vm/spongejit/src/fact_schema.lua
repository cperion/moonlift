-- fact_schema.lua
-- Canonical fact vocabulary for Lua VM JIT stencil generation.
--
-- Design rule: LuaJIT-class rewrites live in L0 as primitive rewrite/fact
-- schemas. Layers L1+ instantiate those schemas over opcode windows.

local M = {}

M.ValueKind = {
    "unknown", "nil", "false", "true", "boolean", "integer", "float", "number",
    "string", "table", "lclosure", "cclosure", "closure", "userdata", "thread",
}

M.LivenessKind = {
    "unknown", "live", "dead", "last_use", "overwritten_before_observed",
}

M.EffectKind = {
    "pure", "guarded_pure", "reads_heap", "writes_heap", "may_call", "may_yield",
    "may_throw", "may_metamethod", "boundary",
}

M.TableAccessKind = {
    "unknown", "raw_array_i64", "raw_string_slot", "shape_known",
    "metatable_absent", "index_absent", "newindex_absent",
}

M.CallKind = {
    "unknown", "known_lua_target", "known_c_target", "monomorphic", "retcount_known",
}

M.DependencyKind = {
    "none", "table_shape_epoch", "metatable_epoch", "global_slot_epoch",
    "closure_target", "debug_hook_absent", "gc_barrier_protocol",
}

M.ProjectionKind = {
    "none", "side_exit", "interpreter", "roots", "debug", "error", "yield", "barrier",
    "materialize_virtual_object",
}

-- L0 semantic/rewrite schemas. These are not all concrete opcode stencils;
-- they are primitive semantic products available to all later layers.
M.L0_REWRITE_SCHEMAS = {
    {
        name = "REWRITE_DCE_PURE_RESULT_DEAD",
        kind = "REWRITE_ONLY",
        unlocks = "dead pure arithmetic/load elimination",
        requires = { "effect:pure", "liveness:result_dead" },
        projection = "none",
    },
    {
        name = "REWRITE_REDUNDANT_GUARD",
        kind = "REWRITE_ONLY",
        unlocks = "guard elimination when fact already dominates",
        requires = { "fact_dominates", "guard_same_subject" },
        projection = "none",
    },
    {
        name = "REWRITE_CONST_FOLD",
        kind = "REWRITE_ONLY",
        unlocks = "constant arithmetic/compare folding",
        requires = { "value_origin:constant", "effect:pure" },
        projection = "none",
    },
    {
        name = "REWRITE_LOAD_FORWARD",
        kind = "REWRITE_ONLY",
        unlocks = "slot/upvalue/table load forwarding",
        requires = { "def_use_visible", "no_intervening_write" },
        projection = "none",
    },
    {
        name = "REWRITE_STORE_LOAD_FORWARD",
        kind = "REWRITE_ONLY",
        unlocks = "store followed by same-location load",
        requires = { "alias_same_location", "no_barrier_observation" },
        projection = "none",
    },
    {
        name = "FACT_TABLE_RAW_STRING_SLOT",
        kind = "PRIMITIVE_FACT",
        unlocks = "raw GETFIELD/SELF/string-key GETTABLE",
        requires = { "value_kind:table", "key_kind:string", "table_shape_epoch", "metatable_absent" },
        dependency = "table_shape_epoch+metatable_epoch",
        projection = "side_exit",
    },
    {
        name = "FACT_TABLE_RAW_ARRAY_I64",
        kind = "PRIMITIVE_FACT",
        unlocks = "raw integer array GETTABLE/SETTABLE",
        requires = { "value_kind:table", "key_kind:integer", "array_hit", "metatable_absent" },
        dependency = "table_shape_epoch+metatable_epoch",
        projection = "side_exit",
    },
    {
        name = "FACT_METATABLE_ABSENT",
        kind = "PRIMITIVE_FACT",
        unlocks = "metamethod elimination",
        requires = { "metatable_epoch" },
        dependency = "metatable_epoch",
        projection = "side_exit",
    },
    {
        name = "FACT_KNOWN_CALL_TARGET",
        kind = "PRIMITIVE_FACT",
        unlocks = "known Lua/C call boundary stencils",
        requires = { "callee_stable", "arg_shape", "retcount_known" },
        dependency = "closure_target",
        projection = "call_boundary",
    },
    {
        name = "FACT_LOOP_I64_INDUCTION",
        kind = "PRIMITIVE_FACT",
        unlocks = "loop-carried i64 specialization",
        requires = { "loop_header", "i64_induction", "stable_step" },
        projection = "side_exit",
    },
    {
        name = "FACT_VIRTUAL_OBJECT",
        kind = "PRIMITIVE_FACT",
        unlocks = "allocation sinking / side-exit materialization",
        requires = { "allocation", "no_escape", "known_fields" },
        dependency = "escape_state",
        projection = "materialize_virtual_object",
    },
}

local function fact(kind, op, fields)
    local f = { kind = kind, op = op }
    for k, v in pairs(fields or {}) do f[k] = v end
    return f
end

function M.axes_for_op(op)
    op = tostring(op or "")
    if op == "GETFIELD" or op == "SELF" then
        return {
            fact("generic_boundary", op, { effect = "boundary", projection = "interpreter" }),
            fact("raw_string_slot", op, {
                requires = { "table", "string_key", "metatable_absent", "shape_dep" },
                dependency = "table_shape_epoch+metatable_epoch",
                projection = "side_exit",
                exits = { "guard_fail" },
            }),
        }
    elseif op == "GETTABLE" then
        return {
            fact("generic_boundary", op, { effect = "boundary", projection = "interpreter" }),
            fact("raw_array_i64", op, {
                requires = { "table", "integer_key", "array_hit", "metatable_absent", "shape_dep" },
                dependency = "table_shape_epoch+metatable_epoch",
                projection = "side_exit",
                exits = { "guard_fail" },
            }),
            fact("raw_string_slot", op, {
                requires = { "table", "string_key", "metatable_absent", "shape_dep" },
                dependency = "table_shape_epoch+metatable_epoch",
                projection = "side_exit",
                exits = { "guard_fail" },
            }),
        }
    elseif op == "ADDI" or op == "ADD" or op == "SUB" or op == "MUL" then
        return {
            fact("generic_boundary", op, { effect = "boundary", projection = "interpreter" }),
            fact("i64", op, { requires = { "lhs_i64", "rhs_i64" }, effect = "guarded_pure", projection = "side_exit", exits = { "guard_fail" } }),
            fact("i64_result_dead", op, { requires = { "lhs_i64", "rhs_i64", "result_dead" }, effect = "pure_rewrite", projection = "none", exits = {} }),
        }
    elseif op == "EQ" or op == "EQK" then
        return {
            fact("generic_boundary", op, { effect = "boundary", projection = "interpreter" }),
            fact("primitive_eq", op, { requires = { "primitive_values", "no_metamethod" }, projection = "side_exit", exits = { "guard_fail" } }),
            fact("i64_eq", op, { requires = { "lhs_i64", "rhs_i64" }, projection = "side_exit", exits = { "guard_fail" } }),
        }
    elseif op == "LT" or op == "LE" then
        return {
            fact("generic_boundary", op, { effect = "boundary", projection = "interpreter" }),
            fact("i64_compare", op, { requires = { "lhs_i64", "rhs_i64" }, projection = "side_exit", exits = { "guard_fail" } }),
        }
    elseif op == "CALL" or op == "TAILCALL" then
        return {
            fact("generic_call_boundary", op, { effect = "may_call", projection = "call_boundary" }),
            fact("known_lua_target", op, { requires = { "callee_lclosure", "arg_shape", "retcount_known" }, dependency = "closure_target", projection = "call_boundary", exits = { "call_boundary", "guard_fail" } }),
            fact("known_c_target", op, { requires = { "callee_cclosure", "arg_shape", "retcount_known" }, dependency = "closure_target", projection = "call_boundary", exits = { "call_boundary", "guard_fail" } }),
        }
    elseif op == "SETFIELD" or op == "SETTABLE" then
        return {
            fact("generic_write_boundary", op, { effect = "writes_heap", projection = "interpreter" }),
            fact("raw_write_barrier_clean", op, { requires = { "table", "slot_known", "metatable_absent", "barrier_clean", "shape_dep" }, dependency = "table_shape_epoch+metatable_epoch+gc_barrier_protocol", projection = "barrier", exits = { "guard_fail", "barrier" } }),
        }
    elseif op == "GETUPVAL" then
        return {
            fact("generic", op),
            fact("upvalue_known", op, { requires = { "upvalue_stable" }, dependency = "closure_target", projection = "side_exit", exits = { "guard_fail" } }),
        }
    end
    return { fact("generic", op) }
end

function M.fact_key(facts)
    local parts = {}
    for _, f in ipairs(facts or {}) do parts[#parts + 1] = tostring(f.op) .. ":" .. tostring(f.kind) end
    return table.concat(parts, ";")
end

function M.has_projection_and_dependency(fact)
    local kind = fact.kind or "generic"
    if kind == "generic" or kind:find("boundary", 1, true) then return true end
    return fact.projection ~= nil and fact.projection ~= "" and (fact.dependency ~= nil or fact.effect == "pure_rewrite")
end

function M.validate_fact_set(facts)
    local report = { valid = true, errors = {} }
    for i, f in ipairs(facts or {}) do
        if not M.has_projection_and_dependency(f) then
            report.valid = false
            report.errors[#report.errors + 1] = string.format("fact %d %s:%s lacks dependency/projection", i, tostring(f.op), tostring(f.kind))
        end
    end
    return report
end

return M
