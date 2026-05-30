-- Lua Interpreter VM — explicit suspended-control protocols.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end

local decode_resume_kind = host.region(I) [[
region decode_resume_kind(state: ResumeState;
                          normal: cont(),
                          tailcall: cont(),
                          pcall: cont(),
                          xpcall: cont(),
                          gettable_mm: cont(),
                          settable_mm: cont(),
                          binop_mm: cont(),
                          unop_mm: cont(),
                          len_mm: cont(),
                          concat_mm: cont(),
                          eq_mm: cont(),
                          lt_mm: cont(),
                          le_mm: cont(),
                          call_mm: cont(),
                          tforloop_call: cont(),
                          native_cont: cont(),
                          tbc_close: cont(),
                          finalizer_call: cont(),
                          coroutine_resume: cont(),
                          coroutine_yield: cont(),
                          unknown: cont(kind: u16))
entry start()
    switch state.kind do
    case 0 then jump normal()
    case 1 then jump tailcall()
    case 2 then jump pcall()
    case 3 then jump xpcall()
    case 4 then jump gettable_mm()
    case 5 then jump settable_mm()
    case 6 then jump binop_mm()
    case 7 then jump unop_mm()
    case 8 then jump len_mm()
    case 9 then jump concat_mm()
    case 10 then jump eq_mm()
    case 11 then jump lt_mm()
    case 12 then jump le_mm()
    case 13 then jump call_mm()
    case 14 then jump tforloop_call()
    case 15 then jump native_cont()
    case 16 then jump tbc_close()
    case 17 then jump finalizer_call()
    case 18 then jump coroutine_resume()
    case 19 then jump coroutine_yield()
    default then jump unknown(kind = state.kind)
    end
end
end
]]

local resume_after_return = host.region {
    TAG_NIL = I.TAG_NIL,
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
region resume_after_return(L: ptr(LuaThread), parent: ptr(Frame), first_result: index, nres: i32,
                           state: ResumeState;
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
    switch state.kind do
    case 0 then
        let next_pc: index = state.pc + 1
        jump adjust_start(parent = parent, dst = state.result_base,
                          first = first_result, nactual = nres,
                          wanted = state.wanted, target_pc = next_pc,
                          is_pcall = as(u8, 0))
    case 1 then
        let next_pc: index = state.pc + 1
        jump adjust_start(parent = parent, dst = state.result_base,
                          first = first_result, nactual = nres,
                          wanted = state.wanted, target_pc = next_pc,
                          is_pcall = as(u8, 0))
    case 2 then
        let next_pc: index = state.pc + 1
        jump adjust_start(parent = parent, dst = state.result_base,
                          first = first_result, nactual = nres,
                          wanted = state.wanted, target_pc = next_pc,
                          is_pcall = as(u8, 1))
    case 4 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        L.stack[parent.base + as(index, state.a)] = L.stack[first_result]
        jump resume_gettable_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 5 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_settable_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 6 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        L.stack[parent.base + as(index, state.a)] = L.stack[first_result]
        jump resume_binop_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 7 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        L.stack[parent.base + as(index, state.a)] = L.stack[first_result]
        jump resume_unop_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 8 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        L.stack[parent.base + as(index, state.a)] = L.stack[first_result]
        jump resume_unop_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 10 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_compare_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 11 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_compare_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 12 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_compare_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 9 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_concat_mm(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 14 then
        let next_pc: index = state.pc + 1
        parent.pc = next_pc
        jump resume_tforloop(parent = parent, pc = next_pc, base = parent.base, top = parent.top)
    case 16 then
        parent.pc = state.pc
        jump resume_tbc_close(parent = parent, pc = state.pc, base = parent.base, top = parent.top)
    default then
        jump error(code = @{ERR_RUNTIME})
    end
end
block adjust_start(parent: ptr(Frame), dst: index, first: index, nactual: i32,
                   wanted: i32, target_pc: index, is_pcall: u8)
    if wanted < 0 then
        jump adjust_done(parent = parent, target_pc = target_pc, is_pcall = is_pcall)
    end
    var n: i32 = nactual
    if n > wanted then n = wanted end
    if n <= 0 then
        jump fill_loop(parent = parent, dst = dst, i = 0, wanted = wanted,
                       target_pc = target_pc, is_pcall = is_pcall)
    end
    jump copy_loop(parent = parent, dst = dst, first = first, i = 0, n = n,
                   wanted = wanted, target_pc = target_pc, is_pcall = is_pcall)
end
block copy_loop(parent: ptr(Frame), dst: index, first: index, i: i32, n: i32,
                wanted: i32, target_pc: index, is_pcall: u8)
    if i >= n then
        jump fill_loop(parent = parent, dst = dst, i = i, wanted = wanted,
                       target_pc = target_pc, is_pcall = is_pcall)
    end
    L.stack[dst + as(index, i)] = L.stack[first + as(index, i)]
    jump copy_loop(i = i + 1, parent = parent, dst = dst, first = first, n = n,
                   wanted = wanted, target_pc = target_pc, is_pcall = is_pcall)
end
block fill_loop(parent: ptr(Frame), dst: index, i: i32, wanted: i32,
                target_pc: index, is_pcall: u8)
    if i >= wanted then
        jump adjust_done(parent = parent, target_pc = target_pc, is_pcall = is_pcall)
    end
    L.stack[dst + as(index, i)].tag = @{TAG_NIL}
    jump fill_loop(i = i + 1, parent = parent, dst = dst, wanted = wanted,
                   target_pc = target_pc, is_pcall = is_pcall)
end
block adjust_done(parent: ptr(Frame), target_pc: index, is_pcall: u8)
    parent.pc = target_pc
    if is_pcall ~= 0 then
        jump pcall_success(parent = parent, pc = target_pc, base = parent.base, top = parent.top)
    end
    jump normal(parent = parent, pc = target_pc, base = parent.base, top = parent.top)
end
block hm_oom()
    jump oom()
end
end
]]

local clear_resume = host.region { TAG_NIL = I.TAG_NIL, RESUME_NORMAL = I.RESUME_NORMAL } [[
region clear_resume(frame: ptr(Frame); done: cont())
entry start()
    frame.resume.kind = @{RESUME_NORMAL}
    frame.resume.a = 0
    frame.resume.b = 0
    frame.resume.c = 0
    frame.resume.pc = 0
    frame.resume.base = 0
    frame.resume.result_base = frame.result_base
    frame.resume.call_top = frame.call_top
    frame.resume.wanted = frame.wanted
    frame.resume.value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    frame.resume.errfunc_slot = 0
    jump done()
end
end
]]

return {
    decode_resume_kind = decode_resume_kind,
    resume_after_return = resume_after_return,
    handle_return_mode = resume_after_return,
    clear_resume = clear_resume,
}
