-- Lua Interpreter VM — Main loop and entry point

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Status) do I["THREAD_" .. k] = moon.int(v) end

-- dispatch_instruction from opcodes module
local opcodes_mod = require("experiments.lua_interpreter_vm.src.opcodes")
local dispatch_instruction = opcodes_mod.dispatch_instruction

-- commit_vm_state: write hot state back to frame/LuaThread before potentially
-- re-entering VM, yielding, allocating, or raising errors
local commit_vm_state = host.region [[
region commit_vm_state(L: ptr(LuaThread), frame: ptr(Frame), pc: index, top: index; done: cont())
entry start()
    frame.pc = pc
    frame.top = top
    L.top = top
    jump done()
end
end
]]

-- vm_resume: entry point from API or coroutine resume
local vm_resume = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME,
    THREAD_OK = I.THREAD_OK,
    THREAD_DEAD = I.THREAD_DEAD,
    THREAD_YIELDED = I.THREAD_YIELDED,
    THREAD_RUNTIME_ERROR = I.THREAD_RUNTIME_ERROR,
    THREAD_OOM = I.THREAD_OOM,
} [[
region vm_resume(L: ptr(LuaThread), nargs: i32;
                 ok: cont(nres: i32),
                 yielded: cont(nres: i32),
                 runtime_error: cont(code: i32),
                 oom: cont())
entry start()
    if L.frame_count == 0 then
        jump runtime_error(code = @{ERR_RUNTIME})
    end
    L.status = @{THREAD_OK}
    emit vm_loop(L;
        finished = do_finish,
        yielded = do_yield,
        error = do_error,
        oom = out_of_mem)
end
block do_finish(nres: i32)
    L.status = @{THREAD_DEAD}
    jump ok(nres = nres)
end
block do_yield(nres: i32)
    L.status = @{THREAD_YIELDED}
    jump yielded(nres = nres)
end
block do_error(code: i32)
    L.status = @{THREAD_RUNTIME_ERROR}
    jump runtime_error(code = code)
end
block out_of_mem()
    L.status = @{THREAD_OOM}
    jump oom()
end
end
]]

-- vm_loop: the main interpreter loop
-- Hot state kept in block parameters: frame, pc, base, top
local vm_loop = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME,
    ERR_BAD_OPCODE = I.ERR_BAD_OPCODE,
} [[
region vm_loop(L: ptr(LuaThread);
               finished: cont(nres: i32),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
entry start()
    if L.frame_count == 0 then
        jump finished(nres = 0)
    end
    let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
    let pc: index = frame.pc
    let base: index = frame.base
    let top: index = frame.top
    jump loop(frame = frame, pc = pc, base = base, top = top)
end
block loop(frame: ptr(Frame), pc: index, base: index, top: index)
    emit commit_vm_state(L, frame, pc, top;
        done = dispatch)
end
block dispatch()
    emit dispatch_instruction(L, frame, pc, base, top;
        next = cont_loop,
        do_jump = cont_jump,
        enter_lua = do_lua,
        enter_native = do_native,
        returned = do_returned,
        yielded = do_yielded,
        error = do_error,
        oom = out_of_mem)
end
block cont_loop(frame: ptr(Frame), pc: index, base: index, top: index)
    jump loop(frame = frame, pc = pc, base = base, top = top)
end
block cont_jump(frame: ptr(Frame), pc: index, base: index, top: index)
    jump loop(frame = frame, pc = pc, base = base, top = top)
end
block do_lua(child: ptr(Frame))
    jump loop(frame = child, pc = child.pc, base = child.base, top = child.top)
end
block do_native(cl: ptr(CClosure))
    let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
    let nargs: i32 = as(i32, frame.top - frame.base)
    emit call_native(L, cl, nargs, frame.wanted;
        returned = native_ret,
        yielded = do_yielded,
        error = do_error,
        oom = out_of_mem)
end
block native_ret(nres: i32)
    -- call_native only reaches this path for native ABIs that have already placed results on the Lua stack.
    -- Caller frame return reshaping must be explicit; reject instead of resuming with corrupt state.
    jump error(code = @{ERR_RUNTIME})
end
block all_done()
    jump finished(nres = 0)
end
block do_returned(nres: i32)
    jump finished(nres = nres)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block do_error(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    vm_resume = vm_resume,
    vm_loop = vm_loop,
    commit_vm_state = commit_vm_state,
    dispatch_instruction = dispatch_instruction,
}
