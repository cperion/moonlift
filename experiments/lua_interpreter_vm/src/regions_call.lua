-- Lua Interpreter VM — Call and return engine (Lua 5.5)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local resume_regions = require("experiments.lua_interpreter_vm.src.regions_resume")
local native_regions = require("experiments.lua_interpreter_vm.src.regions_native")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do I[k] = moon.int(v) end
for k, v in pairs(const.Abi) do I["ABI_" .. k] = moon.int(v) end

local stack_check_lua_call = host.region [[
region stack_check_lua_call(L: ptr(LuaThread), base: index, ncall: i32, topcall: index, maxstack: u16;
                            ready: cont(base: index, ncall: i32, topcall: index),
                            overflow: cont(), oom: cont())
entry start()
    emit stack_check(L, base + as(index, maxstack);
        ok = ok_ready,
        grown = ok_ready,
        overflow = overflow,
        oom = oom)
end
block ok_ready()
    jump ready(base = base, ncall = ncall, topcall = topcall)
end
end
]]

local adjust_varargs_call = host.region [[
region adjust_varargs_call(L: ptr(LuaThread), cl: ptr(LClosure), func_slot: index, ncall: i32, topcall: index;
                            ready: cont(base: index, ncall: i32, topcall: index), oom: cont())
entry start()
    emit adjust_varargs(L, cl, func_slot, ncall; ok = adjusted, oom = oom)
end
block adjusted(base: index)
    jump ready(base = base, ncall = ncall, topcall = topcall)
end
end
]]

local get_call_metamethod_for_call = host.region { TM_CALL = I.TM_CALL } [[
region get_call_metamethod_for_call(L: ptr(LuaThread), func_val: Value, ncall: i32, topcall: index;
                                    found: cont(mm: Value, ncall: i32, topcall: index), missing: cont())
entry start()
    emit get_metamethod(L.global, func_val, as(u8, @{TM_CALL}); found = got, missing = missing)
end
block got(mm: Value)
    jump found(mm = mm, ncall = ncall, topcall = topcall)
end
end
]]

local stack_check_call_metamethod = host.region [[
region stack_check_call_metamethod(L: ptr(LuaThread), func_slot: index, ncall: i32, mm: Value;
                                   ready: cont(ncall: i32, mm: Value), overflow: cont(), oom: cont())
entry start()
    let needed: index = func_slot + as(index, ncall) + 2
    emit stack_check(L, needed;
        ok = ok_ready,
        grown = ok_ready,
        overflow = overflow,
        oom = oom)
end
block ok_ready()
    jump ready(ncall = ncall, mm = mm)
end
end
]]

-- prepare_call: central call dispatcher. The caller supplies explicit return
-- metadata; the child frame owns that metadata until return_from_lua consumes it.
local prepare_call = host.region {
    TAG_LCLOSURE = I.TAG_LCLOSURE,
    TAG_CCLOSURE = I.TAG_CCLOSURE,
    ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW,
    ERR_CALL = I.ERR_CALL,
    TM_CALL = I.TM_CALL,
    PF_VAHID = I.PF_VAHID,
} [[
region prepare_call(L: ptr(LuaThread), func_slot: index, nargs: i32, wanted: i32,
                    resume: ResumeState,
                    result_base: index, call_top: index, yieldable: u8;
                    enter_lua: cont(child: ptr(Frame)),
                    enter_native: cont(cl: ptr(CClosure), ctx: NativeCallContext),
                    returned: cont(nres: i32),
                    yielded: cont(nres: i32),
                    error: cont(code: i32),
                    oom: cont())
entry start()
    jump classify(func_val = L.stack[func_slot], ncall = nargs, topcall = call_top)
end
block classify(func_val: Value, ncall: i32, topcall: index)
    if func_val.tag == @{TAG_LCLOSURE} then
        jump dispatch_lua(func_val = func_val, ncall = ncall, topcall = topcall)
    end
    if func_val.tag == @{TAG_CCLOSURE} then
        jump dispatch_native(func_val = func_val, ncall = ncall, topcall = topcall)
    end
    emit get_call_metamethod_for_call(L, func_val, ncall, topcall;
        found = have_call_mm,
        missing = no_call_mm)
end
block have_call_mm(mm: Value, ncall: i32, topcall: index)
    emit stack_check_call_metamethod(L, func_slot, ncall, mm;
        ready = shift_for_call_mm,
        overflow = stack_err,
        oom = out_of_mem)
end
block shift_for_call_mm(ncall: i32, mm: Value)
    jump shift_loop(i = ncall, ncall = ncall, mm = mm)
end
block shift_loop(i: i32, ncall: i32, mm: Value)
    if i < 0 then jump shifted_call_mm(ncall = ncall, mm = mm) end
    L.stack[func_slot + as(index, i) + 1] = L.stack[func_slot + as(index, i)]
    jump shift_loop(i = i - 1, ncall = ncall, mm = mm)
end
block shifted_call_mm(ncall: i32, mm: Value)
    L.stack[func_slot] = mm
    let new_nargs: i32 = ncall + 1
    let new_top: index = func_slot + as(index, new_nargs) + 1
    jump classify(func_val = mm, ncall = new_nargs, topcall = new_top)
end
block no_call_mm()
    L.last_error_code = @{ERR_CALL}
    jump error(code = @{ERR_CALL})
end
block dispatch_lua(func_val: Value, ncall: i32, topcall: index)
    let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
    let proto: ptr(Proto) = cl.proto
    let base: index = func_slot + 1
    if as(bool, proto.flag & @{PF_VAHID}) then
        emit adjust_varargs_call(L, cl, func_slot, ncall, topcall;
            ready = vararg_adjusted,
            oom = out_of_mem)
    end
    emit stack_check_lua_call(L, base, ncall, topcall, proto.maxstack;
        ready = push_frame,
        overflow = stack_err,
        oom = out_of_mem)
end
block dispatch_native(func_val: Value, ncall: i32, topcall: index)
    let cl: ptr(CClosure) = as(ptr(CClosure), func_val.bits)
    let ctx: NativeCallContext = {
        func_slot = func_slot,
        nargs = ncall,
        wanted = wanted,
        result_base = result_base,
        stack_top = topcall,
        yieldable = yieldable,
        reserved = 0,
        resume = resume
    }
    jump enter_native(cl = cl, ctx = ctx)
end
block vararg_adjusted(base: index, ncall: i32, topcall: index)
    let func_val: Value = L.stack[func_slot]
    let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
    emit stack_check_lua_call(L, base, ncall, topcall, cl.proto.maxstack;
        ready = push_frame,
        overflow = stack_err,
        oom = out_of_mem)
end
block push_frame(base: index, ncall: i32, topcall: index)
    let func_val: Value = L.stack[func_slot]
    let top: index = base + as(index, ncall)
    emit frame_push(L, func_val, base, top,
                    result_base, topcall, wanted, resume, yieldable;
        ok = got_frame,
        overflow = stack_err,
        oom = out_of_mem)
end
block got_frame(frame: ptr(Frame))
    frame.pc = 0
    jump enter_lua(child = frame)
end
block stack_err()
    L.last_error_code = @{ERR_STACK_OVERFLOW}
    jump error(code = @{ERR_STACK_OVERFLOW})
end
block out_of_mem()
    jump oom()
end
end
]]

-- try_call_metamethod: check if the value at func_slot has __call metamethod
local try_call_metamethod = host.region { ERR_CALL = I.ERR_CALL } [[
region try_call_metamethod(L: ptr(LuaThread), func_slot: index;
                           replaced: cont(),
                           not_callable: cont(),
                           error: cont(code: i32),
                           oom: cont())
entry start()
    jump not_callable()
end
end
]]

-- call_native: invoke a C closure through the explicit native ABI.
-- The VM loop passes one NativeCallContext value; raw resume modes do not cross
-- this boundary. Native invocation goes through regions_native.invoke_native.
local call_native = host.region { ERR_CALL = I.ERR_CALL, ABI_NATIVE_VERSION = I.ABI_NATIVE_VERSION, invoke_native = native_regions.invoke_native, resume_after_return = resume_regions.resume_after_return } [[
region call_native(L: ptr(LuaThread), cl: ptr(CClosure), ctx: NativeCallContext;
                   returned: cont(frame: ptr(Frame), pc: index, base: index, top: index, nres: i32),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
entry start()
    if cl == nil then
        L.last_error_code = @{ERR_CALL}
        jump error(code = @{ERR_CALL})
    end
    if cl.fn == nil then
        L.last_error_code = @{ERR_CALL}
        jump error(code = @{ERR_CALL})
    end
    if cl.fn.abi_version ~= @{ABI_NATIVE_VERSION} then
        L.last_error_code = @{ERR_CALL}
        jump error(code = @{ERR_CALL})
    end
    emit @{invoke_native}(L, cl, ctx;
        returned = did_return,
        yielded = did_yield,
        error = native_error,
        oom = out_of_mem,
        stack_grow = need_stack,
        reenter_lua = invalid_result,
        invalid = invalid_result)
end
block did_return(nres: i32)
    if L.frame_count == 0 then
        L.last_error_code = @{ERR_CALL}
        jump error(code = @{ERR_CALL})
    end
    let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
    emit @{resume_after_return}(L, frame, ctx.result_base, nres, ctx.resume;
        normal = native_resumed,
        resume_gettable_mm = native_resumed,
        resume_settable_mm = native_resumed,
        resume_binop_mm = native_resumed,
        resume_unop_mm = native_resumed,
        resume_compare_mm = native_resumed,
        resume_concat_mm = native_resumed,
        resume_tforloop = native_resumed,
        resume_tbc_close = native_resumed,
        pcall_success = native_resumed,
        pcall_failure = native_resumed,
        finished = native_finished,
        yielded = did_yield,
        error = native_resume_error,
        oom = out_of_mem)
end
block native_resumed(parent: ptr(Frame), pc: index, base: index, top: index)
    jump returned(frame = parent, pc = pc, base = base, top = top, nres = ctx.resume.wanted)
end
block native_finished(nres: i32)
    jump returned(frame = as(ptr(Frame), as(u64, 0)), pc = as(index, 0), base = as(index, 0), top = L.top, nres = nres)
end
block native_resume_error(code: i32)
    jump error(code = code)
end
block did_yield(nres: i32)
    jump yielded(nres = nres)
end
block native_error(err: Value)
    L.err_value = err
    L.last_error_code = as(i32, err.aux)
    jump error(code = as(i32, err.aux))
end
block need_stack(needed: index)
    emit stack_check(L, needed;
        ok = retry_after_stack,
        grown = retry_after_stack,
        overflow = invalid_result,
        oom = out_of_mem)
end
block retry_after_stack()
    emit @{invoke_native}(L, cl, ctx;
        returned = did_return,
        yielded = did_yield,
        error = native_error,
        oom = out_of_mem,
        stack_grow = invalid_stack,
        reenter_lua = invalid_result,
        invalid = invalid_result)
end
block invalid_stack(needed: index)
    jump invalid_result()
end
block invalid_result()
    L.last_error_code = @{ERR_CALL}
    jump error(code = @{ERR_CALL})
end
block out_of_mem()
    jump oom()
end
end
]]

-- return_from_lua: pop child frame and dispatch according to child-owned
-- return metadata. The parent is resumed with its own frame state.
local return_from_lua = host.region { ERR_RUNTIME = I.ERR_RUNTIME, resume_after_return = resume_regions.resume_after_return } [[
region return_from_lua(L: ptr(LuaThread), frame: ptr(Frame), first_result: index, nres: i32;
                       resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                       finished: cont(nres: i32),
                       yielded: cont(nres: i32),
                       error: cont(code: i32),
                       oom: cont())
entry start()
    if L.frame_count == 0 then
        jump finished(nres = nres)
    end
    let ret_state: ResumeState = frame.resume
    L.frame_count = L.frame_count - 1
    if L.frame_count == 0 then
        jump finished(nres = nres)
    end
    let parent: ptr(Frame) = L.frames + (L.frame_count - 1)
    emit @{resume_after_return}(L, parent, first_result, nres, ret_state;
        normal = cont_normal,
        resume_gettable_mm = cont_gettable,
        resume_settable_mm = cont_settable,
        resume_binop_mm = cont_binop,
        resume_unop_mm = cont_unop,
        resume_compare_mm = cont_compare,
        resume_concat_mm = cont_concat,
        resume_tforloop = cont_tforloop,
        resume_tbc_close = cont_tbc_close,
        pcall_success = cont_pcall_ok,
        pcall_failure = cont_pcall_err,
        finished = ret_finished,
        yielded = ret_yielded,
        error = ret_error,
        oom = ret_oom)
end
block cont_normal(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_gettable(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_settable(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_binop(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_unop(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_compare(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_concat(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_tforloop(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_tbc_close(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_pcall_ok(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_pcall_err(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block ret_finished(nres: i32)
    jump finished(nres = nres)
end
block ret_yielded(nres: i32)
    jump yielded(nres = nres)
end
block ret_error(code: i32)
    jump error(code = code)
end
block ret_oom()
    jump oom()
end
end
]]

-- resume_after_return: switch on captured child-frame ResumeState, not parent state.
local resume_after_return = resume_regions.resume_after_return
local handle_return_mode = resume_after_return

return {
    prepare_call = prepare_call,
    try_call_metamethod = try_call_metamethod,
    call_native = call_native,
    return_from_lua = return_from_lua,
    resume_after_return = resume_after_return,
    handle_return_mode = handle_return_mode,
}
