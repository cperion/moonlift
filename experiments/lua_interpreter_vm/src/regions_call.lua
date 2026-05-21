-- Lua Interpreter VM — Call and return engine

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end

-- prepare_call: central call dispatcher
-- Evaluates the function at func_slot, dispatches LClosure/CClosure/metamethod
local prepare_call = host.region {
    TAG_LCLOSURE = I.TAG_LCLOSURE,
    TAG_CCLOSURE = I.TAG_CCLOSURE,
    ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW,
    ERR_CALL = I.ERR_CALL,
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
        let needed: index = base + as(index, proto.maxstack)
        emit stack_check(L, needed;
            ok = do_push_lua,
            grown = do_push_lua,
            overflow = stack_err,
            oom = out_of_mem)
    end
    if func_val.tag == @{TAG_CCLOSURE} then
        let cl: ptr(CClosure) = as(ptr(CClosure), func_val.bits)
        jump enter_native(cl = cl)
    end
    -- Not a function: try __call metamethod
    jump error(code = @{ERR_CALL})
end
block do_push_lua()
    let func_val: Value = L.stack[func_slot]
    let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
    let proto: ptr(Proto) = cl.proto
    let base: index = func_slot + 1
    -- Adjust for vararg if needed
    if as(bool, proto.is_vararg) then
        emit adjust_varargs(L, cl, func_slot, nargs;
            ok = push_frame,
            oom = out_of_mem)
    else
        jump push_frame(base = base)
    end
end
block push_frame(base: index)
    let func_val: Value = L.stack[func_slot]
    let top: index = base + as(index, nargs)
    emit frame_push(L, func_val, base, top, wanted, resume_mode;
        ok = got_frame,
        overflow = stack_err,
        oom = out_of_mem)
end
block got_frame(child: ptr(Frame))
    child.pc = 0
    jump enter_lua(child = child)
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

-- return_from_lua: close upvalues, pop frame, dispatch return
local return_from_lua = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region return_from_lua(L: ptr(LuaThread), frame: ptr(Frame), first_result: index, nres: i32;
                       resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                       finished: cont(nres: i32),
                       yielded: cont(nres: i32),
                       error: cont(code: i32),
                       oom: cont())
entry start()
    emit close_upvalues(L, frame.base;
        done = pop_it,
        oom = out_of_mem)
end
block pop_it()
    emit frame_pop(L;
        parent = do_return,
        empty = all_done)
end
block do_return(parent: ptr(Frame))
    emit handle_return_mode(L, parent, first_result, nres;
        normal = cont_normal,
        resume_gettable_mm = cont_gettable,
        resume_settable_mm = cont_settable,
        resume_binop_mm = cont_binop,
        resume_unop_mm = cont_unop,
        resume_compare_mm = cont_compare,
        resume_concat_mm = cont_concat,
        resume_tforloop = cont_tforloop,
        pcall_success = cont_pcall_ok,
        pcall_failure = cont_pcall_err,
        finished = all_done,
        yielded = did_yield,
        error = run_err,
        oom = out_of_mem)
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
block cont_pcall_ok(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block cont_pcall_err(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block all_done(nres: i32)
    jump finished(nres = nres)
end
block did_yield(nres: i32)
    jump yielded(nres = nres)
end
block run_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]]

-- handle_return_mode: big switch on parent.resume_mode
-- Each resume mode corresponds to a dynamic Lua continuation target
local handle_return_mode = host.region {
    RESUME_NORMAL = I.RESUME_NORMAL,
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
    RESUME_TAILCALL = I.RESUME_TAILCALL,
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
                          pcall_success: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          pcall_failure: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                          finished: cont(nres: i32),
                          yielded: cont(nres: i32),
                          error: cont(code: i32),
                          oom: cont())
entry start()
    switch parent.resume_mode do
    case @{RESUME_NORMAL} then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = out_of_mem)
    case @{RESUME_TAILCALL} then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = out_of_mem)
    case @{RESUME_GETTABLE_MM} then
        -- Result goes into resume_a register
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_SETTABLE_MM} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_BINOP_MM} then
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_UNOP_MM} then
        L.stack[parent.base + as(index, parent.resume_a)] = L.stack[first_result]
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_EQ_MM} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_LT_MM} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_LE_MM} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_CONCAT_MM} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_TFORLOOP_CALL} then
        jump normal(parent = parent, pc = parent.resume_pc, base = parent.base, top = parent.top)
    case @{RESUME_PCALL} then
        emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
            done = adj_normal,
            oom = out_of_mem)
    default then
        jump error(code = @{ERR_RUNTIME})
    end
end
block adj_normal(nplaced: i32)
    jump normal(parent = parent, pc = parent.pc + 1, base = parent.base, top = parent.top)
end
block out_of_mem()
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
