-- Moonlift VM — Misc opcode handlers (LEN, CONCAT, CLOSE, TBC, JMP, ERRNNIL)

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_len = R([[
region op_len(]] .. H .. [[;
              ]] .. B.STUB_CALL_CONTS .. [[)
entry start()
    let src: Value = L.stack[base + as(index, b)]
    if src.tag == @{TAG_STR} then
        let s: ptr(String) = as(ptr(String), src.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, s.len) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    if src.tag == @{TAG_TABLE} then
        let t: ptr(Table) = as(ptr(Table), src.bits)
        if t.metatable ~= nil then
            emit get_table_metamethod(L.global, t, as(u8, @{TM_LEN});
                found = call_len_mm,
                missing = raw_table_len)
        end
        jump raw_table_len()
    end
    emit get_metamethod(L.global, src, as(u8, @{TM_LEN});
        found = call_len_mm,
        missing = len_type_error)
end
block raw_table_len()
    let t: ptr(Table) = as(ptr(Table), L.stack[base + as(index, b)].bits)
    jump len_scan(t = t, i = t.array_len)
end
block len_scan(t: ptr(Table), i: index)
    if i == 0 then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = 0 }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    if t.array[i - 1].tag ~= @{TAG_NIL} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, i) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump len_scan(t = t, i = i - 1)
end
block call_len_mm(mm: Value)
    let scratch: index = top
    L.stack[scratch] = mm
    L.stack[scratch + 1] = L.stack[base + as(index, b)]
    let resume: ResumeState = {
        kind = as(u16, @{RESUME_LEN_MM}),
        a = a,
        b = b,
        c = c,
        pc = pc,
        base = base,
        result_base = scratch,
        call_top = top,
        wanted = 1,
        value = { tag = @{TAG_NIL}, aux = 0, bits = 0 },
        errfunc_slot = 0
    }
    emit prepare_call(L, scratch, 1, 1, resume, scratch, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = do_yielded,
        error = len_error,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
end
block mm_returned(nres: i32)
    L.stack[base + as(index, a)] = L.stack[top]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block len_type_error()
    jump error(code = @{ERR_TYPE})
end
block len_error(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_concat = R([[
region op_concat(]] .. H .. [[;
                 ]] .. B.STUB_CALL_CONTS .. [[)
entry start()
    let first: index = base + as(index, b)
    let last: index = base + as(index, c)
    emit string_concat_range(L, first, last;
        done = got_string,
        call_mm = concat_mm,
        error = concat_error,
        oom = out_of_mem)
end
block got_string(s: ptr(String))
    L.stack[base + as(index, a)].tag = @{TAG_STR}
    L.stack[base + as(index, a)].aux = 0
    L.stack[base + as(index, a)].bits = as(u64, s)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block concat_mm(mm: Value)
    jump error(code = @{ERR_CONCAT})
end
block concat_error(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_close = R([[
region op_close(]] .. H .. [[;
                next(frame: ptr(Frame), pc: index, base: index, top: index) |
                oom)
entry start()
    let close_idx: index = base + as(index, a)
    emit close_upvalues(L, close_idx;
        done = closed,
        oom = out_of_mem)
end
block closed()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_tbc = R([[
region op_tbc(]] .. H .. [[;
              next(frame: ptr(Frame), pc: index, base: index, top: index) |
              error(code: i32) |
              oom)
entry start()
    L.tbc_head = base + as(index, a)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_jmp = R([[
region op_jmp(]] .. H .. [[;
              do_jump(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sj)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]])

local op_errnnil = R([[
region op_errnnil(]] .. H .. [[;
                  next(frame: ptr(Frame), pc: index, base: index, top: index) |
                  error(code: i32) |
                  oom)
entry start()
    let val: Value = L.stack[base + as(index, a)]
    if val.tag == @{TAG_NIL} then
        jump error(code = @{ERR_RUNTIME})
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_len = op_len, op_concat = op_concat,
    op_close = op_close, op_tbc = op_tbc,
    op_jmp = op_jmp, op_errnnil = op_errnnil,
}
