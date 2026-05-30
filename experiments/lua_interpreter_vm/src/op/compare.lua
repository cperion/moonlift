-- Moonlift VM — Compare opcode handlers (EQ, LT, LE, EQK, EQI, LTI, LEI, GTI, GEI, TEST, TESTSET)

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_eq = R([[
region op_eq(]] .. H .. [[;
             ]] .. B.CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_equal(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_equal: bool)
    if is_equal == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_lt = R([[
region op_lt(]] .. H .. [[;
             ]] .. B.CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_less_than(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_lt: bool)
    if is_lt == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_le = R([[
region op_le(]] .. H .. [[;
             ]] .. B.CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_less_equal(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_le: bool)
    if is_le == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value, fallback_lt: bool)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

-- EQK: R[A] == K[B]; k inverts skip
local op_eqk = R([[
region op_eqk(]] .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: Value = L.stack[base + as(index, a)]
    let rhs: Value = cl.proto.constants[bx]
    emit value_raw_equal(lhs, rhs;
        equal = yes,
        not_equal = no)
end
block yes()
    if k == 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block no()
    if k ~= 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- Comparison-with-immediate: k inverts skip, sc is Lua 5.5 signed C immediate
local function _cmp_imm_handler(op_name, region_name, result_field, g_flip)
    local lhs, rhs
    if g_flip then
        lhs = "int_val"
        rhs = "L.stack[base + as(index, a)]"
    else
        lhs = "L.stack[base + as(index, a)]"
        rhs = "int_val"
    end
    return R([[
region ]] .. op_name .. "(" .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    let int_val: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, sc)) }
    emit ]] .. region_name .. [[(L, ]] .. lhs .. [[, ]] .. rhs .. [[;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(]] .. result_field .. [[: bool)
    if ]] .. result_field .. [[ ~= (k ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])
end

local op_eqi = _cmp_imm_handler("op_eqi", "value_equal", "is_equal", false)
local op_lti = _cmp_imm_handler("op_lti", "value_less_than", "is_lt", false)
local op_lei = _cmp_imm_handler("op_lei", "value_less_equal", "is_le", false)
local op_gti = _cmp_imm_handler("op_gti", "value_less_than", "is_lt", true)
local op_gei = _cmp_imm_handler("op_gei", "value_less_equal", "is_le", true)

-- TEST / TESTSET
local op_test = R([[
region op_test(]] .. H .. [[;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, a)]
    var is_true: bool = false
    if val.tag ~= @{TAG_NIL} and val.tag ~= @{TAG_FALSE} then
        is_true = true
    end
    if is_true ~= (c == 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_testset = R([[
region op_testset(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, b)]
    var is_true: bool = false
    if val.tag ~= @{TAG_NIL} and val.tag ~= @{TAG_FALSE} then
        is_true = true
    end
    if is_true ~= (c == 0) then
        L.stack[base + as(index, a)] = val
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_eq = op_eq, op_lt = op_lt, op_le = op_le,
    op_eqk = op_eqk, op_eqi = op_eqi, op_lti = op_lti,
    op_lei = op_lei, op_gti = op_gti, op_gei = op_gei,
    op_test = op_test, op_testset = op_testset,
}
