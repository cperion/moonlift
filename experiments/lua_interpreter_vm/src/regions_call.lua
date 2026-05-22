-- Lua Interpreter VM — Call and return engine (Lua 5.5)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do I[k] = moon.int(v) end

-- prepare_call: central call dispatcher
local prepare_call = host.region {
    TAG_LCLOSURE = I.TAG_LCLOSURE,
    TAG_CCLOSURE = I.TAG_CCLOSURE,
    ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW,
    ERR_CALL = I.ERR_CALL,
    PF_VAHID = I.PF_VAHID,
} [[
region prepare_call(L: ptr(LuaThread), func_slot: index, nargs: i32, wanted: i32, resume_mode: u16;
                    enter_lua: cont(child: ptr(Frame)),
                    enter_native: cont(cl: ptr(CClosure)),
                    returned: cont(nres: i32),
                    yielded: cont(nres: i32),
                    error: cont(code: i32),
                    oom: cont())
entry start()
    let func_val: Value = L.stack[func_slot]
    if func_val.tag == @{TAG_LCLOSURE} then
        let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
        let proto: ptr(Proto) = cl.proto
        let base: index = func_slot + 1
        if as(bool, proto.flag & @{PF_VAHID}) then
            emit adjust_varargs(L, cl, func_slot, nargs;
                ok = do_push_lua,
                oom = out_of_mem)
        else
            let needed: index = base + as(index, proto.maxstack)
            emit stack_check(L, needed;
                ok = stack_ready,
                grown = stack_ready,
                overflow = stack_err,
                oom = out_of_mem)
        end
    end
    if func_val.tag == @{TAG_CCLOSURE} then
        let cl: ptr(CClosure) = as(ptr(CClosure), func_val.bits)
        jump enter_native(cl = cl)
    end
    jump error(code = @{ERR_CALL})
end
block do_push_lua(base: index)
    jump push_frame(base = base)
end
block stack_ready()
    jump push_frame(base = func_slot + 1)
end
block push_frame(base: index)
    let func_val: Value = L.stack[func_slot]
    let top: index = base + as(index, nargs)
    emit frame_push(L, func_val, base, top, wanted, resume_mode;
        ok = got_frame,
        overflow = stack_err,
        oom = out_of_mem)
end
block got_frame(frame: ptr(Frame))
    frame.pc = 0
    jump enter_lua(child = frame)
end
block stack_err()
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

-- call_native: invoke a C closure through the native ABI
local call_native = host.region { ERR_CALL = I.ERR_CALL } [[
region call_native(L: ptr(LuaThread), cl: ptr(CClosure), nargs: i32, wanted: i32;
                   returned: cont(nres: i32),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
entry start()
    jump error(code = @{ERR_CALL})
end
end
]]

-- return_from_lua: pop frame and dispatch return.
-- Keep return payload in entry-scope control; do not rely on block access to
-- region parameters, which is not a valid Moonlift data path for scalars.
local return_from_lua = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
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
    L.frame_count = L.frame_count - 1
    if L.frame_count == 0 then
        jump finished(nres = nres)
    end
    let parent: ptr(Frame) = L.frames + (L.frame_count - 1)
    emit handle_return_mode(L, parent, first_result, nres;
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
block no_parent()
    jump finished(nres = nres)
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

-- handle_return_mode: big switch on parent.resume_mode
local handle_return_mode = host.region {
    RESUME_NORMAL = I.RESUME_NORMAL,
    RESUME_TAILCALL = I.RESUME_TAILCALL,
    RESUME_GETTABLE_MM = I.RESUME_GETTABLE_MM,
    RESUME_SETTABLE_MM = I.RESUME_SETTABLE_MM,
    RESUME_BINOP_MM = I.RESUME_BINOP_MM,
    RESUME_UNOP_MM = I.RESUME_UNOP_MM,
    RESUME_EQ_MM = I.RESUME_EQ_MM,
    RESUME_LT_MM = I.RESUME_LT_MM,
    RESUME_LE_MM = I.RESUME_LE_MM,
    RESUME_CONCAT_MM = I.RESUME_CONCAT_MM,
    RESUME_TFORLOOP_CALL = I.RESUME_TFORLOOP_CALL,
    RESUME_PCALL = I.RESUME_PCALL,
    RESUME_TBC_CLOSE = I.RESUME_TBC_CLOSE,
    ERR_RUNTIME = I.ERR_RUNTIME,
} [[
region handle_return_mode(L: ptr(LuaThread), parent: ptr(Frame), first_result: index, nres: i32;
                          normal: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_gettable_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_settable_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_binop_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_unop_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_compare_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_concat_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_tforloop: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          resume_tbc_close: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          pcall_success: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          pcall_failure: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          finished: cont(nres: i32),
                          yielded: cont(nres: i32),
                          error: cont(code: i32),
                          oom: cont())
entry start()
    switch parent.resume_mode do
    case 0 then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = hm_oom)
    case 1 then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = hm_oom)
    case 2 then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = hm_oom)
    case 4 then
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 5 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 6 then
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 7 then
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 10 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 11 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 12 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 9 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 14 then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case 16 then
        jump resume_tbc_close(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    default then
        jump error(code = @{ERR_RUNTIME})
    end
end
block adj_normal(nplaced: i32)
    jump normal(parent = parent, pc = parent.pc + 1, base = parent.base, top = parent.top)
end
block hm_oom()
    jump oom()
end
end
]]

return {
    prepare_call = prepare_call,
    try_call_metamethod = try_call_metamethod,
    call_native = call_native,
    return_from_lua = return_from_lua,
    handle_return_mode = handle_return_mode,
}
