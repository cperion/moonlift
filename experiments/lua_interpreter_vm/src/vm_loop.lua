-- Lua Interpreter VM — Main loop and entry point
-- Hot state threaded through block params: frame, pc, base, top, code, constants.
-- code and constants are cached pointers (not reloaded from frame->closure->proto on every op).

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Status) do I["THREAD_" .. k] = moon.int(v) end

local opcodes_mod = require("experiments.lua_interpreter_vm.src.opcodes")
local dispatch_instruction = opcodes_mod.dispatch_instruction

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
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = frame, pc = pc, base = base, top = top, code = code, constants = constants)
end
block loop(frame: ptr(Frame), pc: index, base: index, top: index,
           code: ptr(Instr), constants: ptr(Value))
    emit dispatch_instruction(L, frame, pc, base, top, code, constants;
        next = cont_loop,
        do_jump = cont_jump,
        resume_parent = cont_resume_parent,
        enter_lua = do_lua,
        enter_native = do_native,
        returned = do_returned,
        yielded = do_yielded,
        error = do_error,
        oom = out_of_mem)
end
block cont_loop(frame: ptr(Frame), pc: index, base: index, top: index,
                code: ptr(Instr), constants: ptr(Value))
    jump loop(frame = frame, pc = pc, base = base, top = top, code = code, constants = constants)
end
block cont_jump(frame: ptr(Frame), pc: index, base: index, top: index,
                code: ptr(Instr), constants: ptr(Value))
    jump loop(frame = frame, pc = pc, base = base, top = top, code = code, constants = constants)
end
block cont_resume_parent(parent: ptr(Frame), pc: index, base: index, top: index,
                         code: ptr(Instr), constants: ptr(Value))
    let cl: ptr(LClosure) = as(ptr(LClosure), parent.closure.bits)
    let parent_code: ptr(Instr) = cl.proto.code
    let parent_constants: ptr(Value) = cl.proto.constants
    jump loop(frame = parent, pc = pc, base = base, top = top,
              code = parent_code, constants = parent_constants)
end
block do_lua(child: ptr(Frame))
    let cl: ptr(LClosure) = as(ptr(LClosure), child.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = child, pc = child.pc, base = child.base, top = child.top,
              code = code, constants = constants)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    emit call_native(L, cl, ctx;
        returned = native_ret,
        yielded = do_yielded,
        error = do_error,
        oom = out_of_mem)
end
block native_ret(frame: ptr(Frame), pc: index, base: index, top: index, nres: i32)
    if frame == nil then
        jump finished(nres = nres)
    end
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = frame, pc = pc, base = base, top = top,
              code = code, constants = constants)
end
block do_returned(nres: i32)
    jump finished(nres = nres)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block do_error(code: i32)
    emit raise_code_error(L, code;
        caught = error_caught,
        uncaught = error_uncaught,
        oom = out_of_mem)
end
block error_caught(frame: ptr(Frame))
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = frame, pc = frame.pc, base = frame.base, top = frame.top,
              code = code, constants = constants)
end
block error_uncaught(code: i32)
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
