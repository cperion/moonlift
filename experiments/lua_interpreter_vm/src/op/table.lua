-- Moonlift VM — Table access opcode handlers

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_gettabup = R([[
region op_gettabup(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    let tbl_val: Value = *uv.v
    let key: Value = cl.proto.constants[c]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl_val, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_gettable = R([[
region op_gettable(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_geti = R([[
region op_geti(]] .. H .. [[;
               ]] .. B.TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, c)) }
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_getfield = R([[
region op_getfield(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = cl.proto.constants[c]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_settabup = R([[
region op_settabup(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[a]
    let tbl_val: Value = *uv.v
    let key: Value = cl.proto.constants[b]
    emit resolve_rk(L, base, k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let cl_rk_stab: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv_rk_stab: ptr(UpVal) = cl_rk_stab.upvals[a]
    let tbl_val: Value = *uv_rk_stab.v
    let key: Value = cl_rk_stab.proto.constants[b]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl_val, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_settable = R([[
region op_settable(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    let val: Value = L.stack[base + as(index, a)]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, val;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_setti = R([[
region op_setti(]] .. H .. [[;
                ]] .. B.TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    emit resolve_rk(L, base, k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let tbl: Value = L.stack[base + as(index, a)]
    let key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, b)) }
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_setfield = R([[
region op_setfield(]] .. H .. [[;
                   ]] .. B.TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    emit resolve_rk(L, base, k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let cl_rk_sf: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let tbl: Value = L.stack[base + as(index, a)]
    let key: Value = cl_rk_sf.proto.constants[b]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_newtable = R([[
region op_newtable(]] .. H .. [[;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   oom: cont())
entry start()
    var arr: index = as(index, vb)
    if vb >= 8 then
        let mant: u16 = (vb & 7) + 8
        let exp: u16 = (vb >> 3) - 1
        arr = as(index, mant) << as(index, exp)
    end
    var hp: u32 = as(u32, vc)
    if hp == 0 then hp = 1 end
    if hp > 16 then hp = 16 end
    emit table_new(L, arr, hp;
        ok = made_table,
        oom = out_of_mem)
end
block made_table(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1 + as(index, k), base = base, top = top)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_self = R([[
region op_self(]] .. H .. [[;
               ]] .. B.TABLE_CONTS .. [[)
entry start()
    L.stack[base + as(index, a + 1)] = L.stack[base + as(index, b)]
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. B.TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_setlist = R([[
region op_setlist(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  oom: cont())
entry start()
    jump prepare()
end
block prepare()
    let tbl: Value = L.stack[base + as(index, a)]
    if tbl.tag ~= @{TAG_TABLE} then jump out_of_mem() end
    var block_index: u32 = as(u32, vc)
    if k ~= 0 then
        let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
        let extra: ptr(Instr) = cl.proto.code + (pc + 1)
        block_index = (extra.word >> 7) & 33554431
    end
    var n: index = as(index, b)
    if b == 0 then
        n = top - (base + as(index, a) + 1)
    end
    let start_index: index = (as(index, block_index) - 1) * 50
    let t: ptr(Table) = as(ptr(Table), tbl.bits)
    if start_index + n > t.array_cap then
        let key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, start_index + n) }
        emit table_grow_for_key(L, t, key;
            done = after_grow,
            error = set_error,
            oom = out_of_mem)
    end
    jump write_loop(i = as(index, 0), n = n, start_index = start_index, t = t)
end
block after_grow()
    jump prepare()
end
block write_loop(i: index, n: index, start_index: index, t: ptr(Table))
    if i >= n then
        if start_index + n > t.array_len then t.array_len = start_index + n end
        jump next(frame = frame, pc = pc + 1 + as(index, k), base = base, top = top)
    end
    t.array[start_index + i] = L.stack[base + as(index, a) + 1 + i]
    jump write_loop(i = i + 1, n = n, start_index = start_index, t = t)
end
block set_error(code: i32)
    jump out_of_mem()
end
block out_of_mem()
    jump oom()
end
end
]])

return {
    op_gettabup = op_gettabup, op_gettable = op_gettable,
    op_geti = op_geti, op_getfield = op_getfield,
    op_settabup = op_settabup, op_settable = op_settable,
    op_setti = op_setti, op_setfield = op_setfield,
    op_newtable = op_newtable, op_self = op_self, op_setlist = op_setlist,
}
