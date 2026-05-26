-- lowering_plan.lua
-- Converts Candidate × FactSet into explicit lowering operations.
-- This is the semantic firewall between facts and codegen: if a fact has no
-- lowering for a backend, the candidate is unsupported for that backend.

local M = {}

local function ops(candidate)
    return candidate.ops or {}
end

local function fact_kind_for(candidate, op, ordinal)
    local seen = 0
    for _, f in ipairs(candidate.facts or {}) do
        if f.op == op then
            seen = seen + 1
            if seen == ordinal then return f.kind, f end
        end
    end
    return "generic", nil
end

local function op_ordinal(oplist, idx)
    local n = 0
    for i = 1, idx do if oplist[i] == oplist[idx] then n = n + 1 end end
    return n
end

local function add_error(plan, msg)
    plan.valid = false
    plan.errors[#plan.errors + 1] = msg
end

local BOUNDARY_OPS = {
    LOADKX=true, LFALSESKIP=true, GETUPVAL=true, SETUPVAL=true, GETTABUP=true, GETI=true,
    SETTABUP=true, SETTABLE=true, SETI=true, SETFIELD=true, NEWTABLE=true,
    ADDK=true, SUBK=true, MULK=true, MODK=true, POWK=true, DIVK=true, IDIVK=true,
    BANDK=true, BORK=true, BXORK=true, SHLI=true, SHRI=true,
    MOD=true, POW=true, DIV=true, IDIV=true, BAND=true, BOR=true, BXOR=true, SHL=true, SHR=true,
    MMBIN=true, MMBINI=true, MMBINK=true, UNM=true, BNOT=true, NOT=true, LEN=true, CONCAT=true,
    CLOSE=true, TBC=true, JMP=true, LE=true, EQI=true, LTI=true, LEI=true, GTI=true, GEI=true,
    TEST=true, TESTSET=true, CALL=true, TAILCALL=true, RETURN=true, FORLOOP=true, FORPREP=true,
    TFORPREP=true, TFORCALL=true, TFORLOOP=true, SETLIST=true, CLOSURE=true, VARARG=true,
    GETVARG=true, ERRNNIL=true, VARARGPREP=true, EXTRAARG=true,
}

local function boundary_lowering(op, kind)
    return "boundary_side_exit"
end

local function op_lowering(op, kind, backend)
    -- Always-concrete local/value/control-boundary primitives. Their generic
    -- fact is a real lowering, not an interpreter boundary.
    if op == "MOVE" then return "move" end
    if op == "LOADI" then return "load_i" end
    if op == "LOADF" then return "load_f" end
    if op == "LOADK" then return "load_k" end
    if op == "LOADFALSE" then return "load_false" end
    if op == "LOADTRUE" then return "load_true" end
    if op == "LOADNIL" then return "load_nil" end
    if op == "RETURN0" then return "return0" end
    if op == "RETURN1" then return "return1" end

    if op == "GETFIELD" then
        if kind == "raw_string_slot" then return "getfield_raw_string_slot" end
        if kind == "generic_boundary" then return "getfield_generic_guarded" end
        return nil, "GETFIELD requires raw_string_slot/generic_boundary lowering; got " .. tostring(kind)
    end
    if op == "GETTABLE" then
        if kind == "raw_array_i64" then return "gettable_raw_array_i64" end
        if kind == "raw_string_slot" then return "gettable_raw_string_slot" end
        if kind == "generic_boundary" then return "gettable_generic_guarded" end
        return nil, "GETTABLE requires raw_array_i64/raw_string_slot/generic_boundary lowering; got " .. tostring(kind)
    end
    if op == "GETTABUP" then
        if kind == "generic" then return "gettabup_generic_guarded" end
    end
    if op == "GETUPVAL" then
        if kind == "generic" or kind == "upvalue_known" then return "getupval" end
    end
    if op == "SELF" then
        if kind == "raw_string_slot" then return "self_raw_string_slot" end
        if kind == "generic_boundary" then return "self_generic_guarded" end
        return nil, "SELF requires raw_string_slot/generic_boundary lowering; got " .. tostring(kind)
    end

    if op == "ADDI" then
        if kind == "i64" or kind == "generic_boundary" then return "addi_i64_guarded" end
        if kind == "i64_result_dead" then return "dead_pure" end
        return nil, "ADDI requires i64/i64_result_dead/generic_boundary lowering; got " .. tostring(kind)
    end
    if op == "ADD" or op == "SUB" or op == "MUL" then
        if kind == "i64" or kind == "generic_boundary" then return op:lower() .. "_i64_guarded" end
        if kind == "i64_result_dead" then return "dead_pure" end
        return nil, op .. " requires i64/i64_result_dead/generic_boundary lowering; got " .. tostring(kind)
    end

    if op == "EQ" then
        if kind == "primitive_eq" then return "eq_primitive_branch" end
        if kind == "i64_eq" then return "eq_i64_branch" end
        if kind == "generic_boundary" then return "eq_generic_primitive_guarded" end
        return nil, "EQ requires primitive_eq/i64_eq/generic_boundary branch lowering; got " .. tostring(kind)
    end
    if op == "EQK" then
        if kind == "primitive_eq" then return "eqk_primitive_branch" end
        if kind == "i64_eq" then return "eqk_i64_branch" end
        if kind == "generic_boundary" then return "eqk_generic_primitive_guarded" end
        return nil, "EQK requires primitive_eq/i64_eq/generic_boundary branch lowering; got " .. tostring(kind)
    end
    if op == "LT" then
        if kind == "i64_compare" or kind == "generic_boundary" then return "lt_i64_branch" end
    end
    if op == "LE" then
        if kind == "i64_compare" or kind == "generic_boundary" then return "le_i64_branch" end
    end
    if op == "SETFIELD" or op == "SETTABLE" then
        if kind == "raw_write_barrier_clean" then return op == "SETFIELD" and "setfield_raw_write" or "settable_raw_write" end
        if kind == "generic_write_boundary" then return op == "SETFIELD" and "setfield_generic_raw_guarded" or "settable_generic_raw_guarded" end
    end
    if op == "CALL" or op == "TAILCALL" then
        if kind == "known_lua_target" then return op:lower() .. "_known_lua_boundary" end
        if kind == "known_c_target" then return op:lower() .. "_known_c_boundary" end
        if kind == "generic_call_boundary" then return op:lower() .. "_generic_closure_boundary" end
    end
    if op == "TEST" then
        if kind == "generic" then return "test_truthy_branch" end
    end
    if op == "JMP" then
        if kind == "generic" then return "jmp_sj" end
    end
    if op == "FORPREP" then
        if kind == "generic" then return "forprep_i64_guarded" end
    end
    if op == "FORLOOP" then
        if kind == "generic" then return "forloop_i64_guarded" end
    end
    if op == "DIV" then
        if kind == "generic" then return "div_number_guarded" end
    end
    if op == "RETURN" then
        if kind == "generic" then return "return_variable" end
    end
    if op == "NEWTABLE" then
        if kind == "generic" then return "newtable_allocator_boundary" end
    end

    if BOUNDARY_OPS[op] then return boundary_lowering(op, kind) end
    return boundary_lowering(op, kind)
end

local function rewrite_supported(kind)
    return kind == "move_move_empty"
        or kind == "move_move_forward"
        or kind == "load_move_final_dst"
        or kind == "op_move_final_dst"
        or kind == "op_return1"
end

function M.build(candidate, config)
    config = config or {}
    local backend = config.backend or "gcc"
    local plan = {
        valid = true,
        backend = backend,
        candidate_id = candidate.id,
        shape_kind = candidate.shape_kind,
        lowering = candidate.lowering or candidate.rewrite_kind or "generic_opcode_sequence",
        continuation = candidate.continuation,
        op_lowerings = {},
        errors = {},
    }

    if candidate.rewrite_kind then
        if rewrite_supported(candidate.rewrite_kind) then
            plan.rewrite_kind = candidate.rewrite_kind
            return plan
        end
        add_error(plan, "unsupported rewrite lowering " .. tostring(candidate.rewrite_kind))
        return plan
    end

    local oplist = ops(candidate)
    for i, op in ipairs(oplist) do
        local kind, fact = fact_kind_for(candidate, op, op_ordinal(oplist, i))
        local lowering, err = op_lowering(op, kind, backend)
        if not lowering then
            add_error(plan, err)
        else
            plan.op_lowerings[#plan.op_lowerings + 1] = {
                index = i,
                op = op,
                fact_kind = kind,
                fact = fact,
                lowering = lowering,
            }
        end
    end

    return plan
end

function M.codegen_supported(candidate, config)
    local plan = M.build(candidate, config)
    if plan.valid then return true, plan end
    return false, table.concat(plan.errors, "; "), plan
end

return M
