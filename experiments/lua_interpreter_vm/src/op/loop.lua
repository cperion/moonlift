-- Moonlift VM — For-loop opcode handlers

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_forloop = R([[
region op_forloop(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32))
entry start()
    let idx_slot: index = base + as(index, a)
    let limit_slot: index = base + as(index, a + 1)
    let step_slot: index = base + as(index, a + 2)
    let idx_val: Value = L.stack[idx_slot]
    let limit_val: Value = L.stack[limit_slot]
    let step_val: Value = L.stack[step_slot]
    if idx_val.tag == @{TAG_INTEGER} and limit_val.tag == @{TAG_INTEGER} and step_val.tag == @{TAG_INTEGER} then
        let idx: i64 = as(i64, idx_val.bits) + as(i64, step_val.bits)
        L.stack[idx_slot] = { tag = @{TAG_INTEGER}, aux = 0, bits = bitcast(u64, idx) }
        let limit: i64 = as(i64, limit_val.bits)
        let step: i64 = as(i64, step_val.bits)
        if (step >= 0 and idx <= limit) or (step < 0 and idx >= limit) then
            L.stack[base + as(index, a + 3)] = L.stack[idx_slot]
            let new_pc: index = as(index, as(i32, pc) + sbx)
            jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
        end
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    if idx_val.tag == @{TAG_NUM} and limit_val.tag == @{TAG_NUM} and step_val.tag == @{TAG_NUM} then
        let idx: f64 = bitcast(f64, idx_val.bits) + bitcast(f64, step_val.bits)
        L.stack[idx_slot] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, idx) }
        let limit: f64 = bitcast(f64, limit_val.bits)
        let step: f64 = bitcast(f64, step_val.bits)
        if (step >= 0.0 and idx <= limit) or (step < 0.0 and idx >= limit) then
            L.stack[base + as(index, a + 3)] = L.stack[idx_slot]
            let new_pc: index = as(index, as(i32, pc) + sbx)
            jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
        end
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_forprep = R([[
region op_forprep(]] .. H .. [[;
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32))
entry start()
    let init_slot: index = base + as(index, a)
    let limit_slot: index = base + as(index, a + 1)
    let step_slot: index = base + as(index, a + 2)
    let init_val: Value = L.stack[init_slot]
    let limit_val: Value = L.stack[limit_slot]
    let step_val: Value = L.stack[step_slot]
    if init_val.tag == @{TAG_INTEGER} and limit_val.tag == @{TAG_INTEGER} and step_val.tag == @{TAG_INTEGER} then
        let prepared: i64 = as(i64, init_val.bits) - as(i64, step_val.bits)
        L.stack[init_slot] = { tag = @{TAG_INTEGER}, aux = 0, bits = bitcast(u64, prepared) }
        let new_pc: index = as(index, as(i32, pc) + sbx)
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    if init_val.tag == @{TAG_NUM} and limit_val.tag == @{TAG_NUM} and step_val.tag == @{TAG_NUM} then
        let prepared: f64 = bitcast(f64, init_val.bits) - bitcast(f64, step_val.bits)
        L.stack[init_slot] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, prepared) }
        let new_pc: index = as(index, as(i32, pc) + sbx)
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_tforprep = R([[
region op_tforprep(]] .. H .. [[;
                   do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]])

local op_tforcall = R([[
region op_tforcall(]] .. H .. [[;
                   ]] .. B.MMBIN_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_tforloop = R([[
region op_tforloop(]] .. H .. [[;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let var_val: Value = L.stack[base + as(index, a + 2)]
    if var_val.tag ~= @{TAG_NIL} then
        L.stack[base + as(index, a)] = var_val
        let new_pc: index = as(index, as(i32, pc) - as(i32, bx))
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_forloop = op_forloop, op_forprep = op_forprep,
    op_tforprep = op_tforprep, op_tforcall = op_tforcall, op_tforloop = op_tforloop,
}
