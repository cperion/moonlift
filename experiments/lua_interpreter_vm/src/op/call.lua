-- Moonlift VM — Call/Return opcode handlers

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_call = R([[
region op_call(]] .. H .. [[;
               ]] .. B.CALL_CONTS .. [[)
entry start()
    let func_slot: index = base + as(index, a)
    var nargs: i32 = 0
    if b == 0 then
        nargs = as(i32, top - func_slot - 1)
    else
        nargs = as(i32, b - 1)
    end
    var wanted: i32 = 0
    if c == 0 then
        wanted = -1
    else
        wanted = as(i32, c - 1)
    end
    frame.pc = pc
    L.top = top
    let resume: ResumeState = {
        kind = as(u16, @{RESUME_NORMAL}),
        a = a,
        b = b,
        c = c,
        pc = pc,
        base = base,
        result_base = func_slot,
        call_top = top,
        wanted = wanted,
        value = { tag = @{TAG_NIL}, aux = 0, bits = 0 },
        errfunc_slot = 0
    }
    emit prepare_call(L, func_slot, nargs, wanted, resume, func_slot, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = call_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume.a = a
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
end
block call_returned(nres: i32)
    let func_slot: index = base + as(index, a)
    let dst: index = base + as(index, a)
    var wanted: i32 = 0
    if c == 0 then
        wanted = -1
    else
        wanted = as(i32, c - 1)
    end
    emit adjust_results(L, func_slot + 1, nres, wanted, dst;
        done = res_adjusted,
        oom = out_of_mem)
end
block res_adjusted(nplaced: i32)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block call_err(code: i32)
    jump error(code = code)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_tailcall = R([[
region op_tailcall(]] .. H .. [[;
                   ]] .. B.CALL_CONTS .. [[)
entry start()
    let func_slot: index = base + as(index, a)
    var nargs: i32 = 0
    if b == 0 then
        nargs = as(i32, top - func_slot - 1)
    else
        nargs = as(i32, b - 1)
    end
    frame.pc = pc
    L.top = top
    let resume: ResumeState = {
        kind = as(u16, @{RESUME_TAILCALL}),
        a = a,
        b = b,
        c = c,
        pc = pc,
        base = base,
        result_base = frame.result_base,
        call_top = top,
        wanted = frame.wanted,
        value = { tag = @{TAG_NIL}, aux = 0, bits = 0 },
        errfunc_slot = 0
    }
    emit prepare_call(L, func_slot, nargs, frame.wanted, resume, frame.result_base, top, frame.yieldable;
        enter_lua = do_lua,
        enter_native = do_native,
        returned = call_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
end
block call_returned(nres: i32)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block call_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_return = R([[
region op_return(]] .. H .. [[;
                 ]] .. B.RET_CONTS .. [[)
entry start()
    let first: index = base + as(index, a)
    if b == 1 then
        jump do_return(first = first, nres = 0)
    end
    if b == 0 then
        jump do_return(first = first, nres = as(i32, top - first))
    end
    jump do_return(first = first, nres = as(i32, b - 1))
end
block do_return(first: index, nres: i32)
    frame.resume.base = first
    frame.resume.a = as(u16, nres)
    emit close_upvalues(L, frame.base;
        done = after_close_saved,
        oom = oom)
end
block after_close_saved()
    if k ~= 0 then
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = error,
            oom = oom)
    end
    jump after_tbc_saved()
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume.base, nres = as(i32, frame.resume.a))
end
block after_tbc(first: index, nres: i32)
    emit return_from_lua(L, frame, first, nres;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = parent.pc, base = parent.base, top = parent.top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

local op_return0 = R([[
region op_return0(]] .. H .. [[;
                  ]] .. B.RET_CONTS .. [[)
entry start()
    frame.resume.base = base
    emit close_upvalues(L, frame.base;
        done = after_close_saved,
        oom = oom)
end
block after_close_saved()
    if k ~= 0 then
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = error,
            oom = oom)
    end
    jump after_tbc_saved()
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume.base)
end
block after_tbc(first: index)
    emit return_from_lua(L, frame, first, 0;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = parent.pc, base = parent.base, top = parent.top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

local op_return1 = R([[
region op_return1(]] .. H .. [[;
                  ]] .. B.RET_CONTS .. [[)
entry start()
    let first: index = base + as(index, a)
    frame.resume.base = first
    emit close_upvalues(L, frame.base;
        done = after_close_saved,
        oom = oom)
end
block after_close_saved()
    if k ~= 0 then
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = error,
            oom = oom)
    end
    jump after_tbc_saved()
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume.base)
end
block after_tbc(first: index)
    emit return_from_lua(L, frame, first, 1;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = parent.pc, base = parent.base, top = parent.top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

return {
    op_call = op_call, op_tailcall = op_tailcall,
    op_return = op_return, op_return0 = op_return0, op_return1 = op_return1,
}
