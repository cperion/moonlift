-- Moonlift VM — Opcode module shared boilerplate

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local protocols = require("experiments.lua_interpreter_vm.src.op.protocols")

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

local H = protocols.handler_params()

-- Shared continuation signatures come from named protocol descriptors. The two
-- table metamethod adapter blocks are kept as structural blocks for now; their
-- signatures are no longer copied ad hoc.
local next_only = "\n               " .. protocols.signature("next_only")
local NATIVE_CONT = protocols.conts.enter_native
local TABLE_CONTS = protocols.signature("table")
local TABLE_GET_MM_BLOCKS = [[
block do_mm(mm: Value, self: Value, key: Value)
    let scratch: index = top
    L.stack[scratch] = mm
    L.stack[scratch + 1] = self
    L.stack[scratch + 2] = key
    let resume: ResumeState = {
        kind = as(u16, @{RESUME_GETTABLE_MM}),
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
    emit prepare_call(L, scratch, 2, 1, resume, scratch, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume.a = a
    child.resume.pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
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
    let resume: ResumeState = {
        kind = as(u16, @{RESUME_SETTABLE_MM}),
        a = a,
        b = b,
        c = c,
        pc = pc,
        base = base,
        result_base = scratch,
        call_top = top,
        wanted = 0,
        value = { tag = @{TAG_NIL}, aux = 0, bits = 0 },
        errfunc_slot = 0
    }
    emit prepare_call(L, scratch, 3, 0, resume, scratch, top, as(u8, 1);
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume.a = a
    child.resume.pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
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
local CMP_CONTS = protocols.signature("compare")
local CALL_CONTS = protocols.signature("call")
local RET_CONTS = protocols.signature("ret")
local MMBIN_CONTS = protocols.signature("mmbin")
local TFORCALL_CONTS = protocols.signature("tforcall")
local STUB_CALL_CONTS = TABLE_CONTS

local ARITH_CONT = protocols.signature("arith")

return {
    VALS = VALS, R = R, H = H, protocols = protocols,
    NATIVE_CONT = NATIVE_CONT,
    next_only = next_only,
    TABLE_CONTS = TABLE_CONTS,
    TABLE_GET_MM_BLOCKS = TABLE_GET_MM_BLOCKS,
    TABLE_SET_MM_BLOCKS = TABLE_SET_MM_BLOCKS,
    CMP_CONTS = CMP_CONTS,
    CALL_CONTS = CALL_CONTS,
    RET_CONTS = RET_CONTS,
    MMBIN_CONTS = MMBIN_CONTS,
    TFORCALL_CONTS = TFORCALL_CONTS,
    STUB_CALL_CONTS = STUB_CALL_CONTS,
    ARITH_CONT = ARITH_CONT,
}
