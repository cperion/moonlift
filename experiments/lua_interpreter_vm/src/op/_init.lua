-- Moonlift VM — Opcode module shared boilerplate

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local VALS = {}
for k, v in pairs(const.Tag)    do VALS["TAG_" .. k]    = moon.int(v) end
for k, v in pairs(const.Err)    do VALS["ERR_" .. k]    = moon.int(v) end
for k, v in pairs(const.Resume) do VALS["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.TM)     do VALS["TM_" .. k]     = moon.int(v) end
for k, v in pairs(const.Op)     do VALS["OP_" .. k]     = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do VALS[k] = moon.int(v) end

local function R(src)
    src = src:match("^%s*(.+)") or src
    return host.region(VALS)(src)
end

local H = "L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32"

-- Shared continuation strings
local next_only = "\n               next: cont(frame: ptr(Frame), pc: index, base: index, top: index)"
local NATIVE_CONT = "enter_native: cont(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16)"
local TABLE_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]
local TABLE_GET_MM_BLOCKS = [[
block do_mm(mm: Value, self: Value, key: Value)
    let scratch: index = top
    L.stack[scratch] = mm
    L.stack[scratch + 1] = self
    L.stack[scratch + 2] = key
    emit prepare_call(L, scratch, 2, 1, as(u16, @{RESUME_GETTABLE_MM}), pc, scratch, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume_a = a
    child.resume_pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16)
    jump enter_native(cl = cl, func_slot = func_slot, nargs = nargs, wanted = wanted, result_base = result_base, resume_mode = resume_mode)
end
block mm_returned(nres: i32)
    let scratch: index = top
    let v: Value = L.stack[scratch]
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block type_err()
    jump error(code = @{ERR_INDEX})
end
block loop_err()
    jump error(code = @{ERR_LOOP})
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
]]
local TABLE_SET_MM_BLOCKS = [[
block do_mm(mm: Value, self: Value, key: Value, value: Value)
    let scratch: index = top
    L.stack[scratch] = mm
    L.stack[scratch + 1] = self
    L.stack[scratch + 2] = key
    L.stack[scratch + 3] = value
    emit prepare_call(L, scratch, 3, 0, as(u16, @{RESUME_SETTABLE_MM}), pc, scratch, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume_a = a
    child.resume_pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16)
    jump enter_native(cl = cl, func_slot = func_slot, nargs = nargs, wanted = wanted, result_base = result_base, resume_mode = resume_mode)
end
block mm_returned(nres: i32)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block type_err()
    jump error(code = @{ERR_INDEX})
end
block loop_err()
    jump error(code = @{ERR_LOOP})
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
]]
local CMP_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]
local CALL_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]
local RET_CONTS = [[
resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                 finished: cont(nres: i32),
                 error: cont(code: i32),
                 oom: cont()]]
local MMBIN_CONTS = "enter_lua: cont(child: ptr(Frame)),\n               enter_native: cont(cl: ptr(CClosure), func_slot: index, nargs: i32, wanted: i32, result_base: index, resume_mode: u16),\n               yielded: cont(nres: i32),\n               error: cont(code: i32),\n               oom: cont()"
local STUB_CALL_CONTS = TABLE_CONTS

local ARITH_CONT = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index),\n               error: cont(code: i32)"

return {
    VALS = VALS, R = R, H = H,
    NATIVE_CONT = NATIVE_CONT,
    next_only = next_only,
    TABLE_CONTS = TABLE_CONTS,
    TABLE_GET_MM_BLOCKS = TABLE_GET_MM_BLOCKS,
    TABLE_SET_MM_BLOCKS = TABLE_SET_MM_BLOCKS,
    CMP_CONTS = CMP_CONTS,
    CALL_CONTS = CALL_CONTS,
    RET_CONTS = RET_CONTS,
    MMBIN_CONTS = MMBIN_CONTS,
    STUB_CALL_CONTS = STUB_CALL_CONTS,
    ARITH_CONT = ARITH_CONT,
}
