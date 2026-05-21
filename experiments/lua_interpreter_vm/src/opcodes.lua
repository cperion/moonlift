-- Lua Interpreter VM — Dispatch instruction region
-- Single region: fetch instruction, switch on opcode, emit handler.

-- This is a hand-written region, not generated. If opcodes change,
-- update the switch arms and handler effects here.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

-- Build values table for all opcode constants
local I = {}
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

local dispatch_instruction = host.region {
    OP_MOVE = I.OP_MOVE, OP_LOADK = I.OP_LOADK, OP_LOADBOOL = I.OP_LOADBOOL,
    OP_LOADNIL = I.OP_LOADNIL, OP_GETUPVAL = I.OP_GETUPVAL,
    OP_GETGLOBAL = I.OP_GETGLOBAL, OP_GETTABLE = I.OP_GETTABLE,
    OP_SETGLOBAL = I.OP_SETGLOBAL, OP_SETUPVAL = I.OP_SETUPVAL,
    OP_SETTABLE = I.OP_SETTABLE, OP_NEWTABLE = I.OP_NEWTABLE,
    OP_SELF = I.OP_SELF, OP_ADD = I.OP_ADD, OP_SUB = I.OP_SUB,
    OP_MUL = I.OP_MUL, OP_DIV = I.OP_DIV, OP_MOD = I.OP_MOD,
    OP_POW = I.OP_POW, OP_UNM = I.OP_UNM, OP_NOT = I.OP_NOT,
    OP_LEN = I.OP_LEN, OP_CONCAT = I.OP_CONCAT, OP_JMP = I.OP_JMP,
    OP_EQ = I.OP_EQ, OP_LT = I.OP_LT, OP_LE = I.OP_LE,
    OP_TEST = I.OP_TEST, OP_TESTSET = I.OP_TESTSET,
    OP_CALL = I.OP_CALL, OP_TAILCALL = I.OP_TAILCALL,
    OP_RETURN = I.OP_RETURN, OP_FORLOOP = I.OP_FORLOOP,
    OP_FORPREP = I.OP_FORPREP, OP_TFORLOOP = I.OP_TFORLOOP,
    OP_SETLIST = I.OP_SETLIST, OP_CLOSE = I.OP_CLOSE,
    OP_CLOSURE = I.OP_CLOSURE, OP_VARARG = I.OP_VARARG,
    ERR_BAD_OPCODE = I.ERR_BAD_OPCODE,
} [[
region dispatch_instruction(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    finished: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
entry decode()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code_ptr: ptr(Instr) = cl.proto.code + pc
    let instr: Instr = *code_ptr
    let a: u16 = instr.a
    let b: u16 = instr.b
    let c: u16 = instr.c
    let bx: u32 = instr.bx
    let sbx: i32 = instr.sbx
    switch instr.op do
    case @{OP_MOVE} then
        emit op_move(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_LOADK} then
        emit op_loadk(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_LOADBOOL} then
        emit op_loadbool(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_LOADNIL} then
        emit op_loadnil(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_GETUPVAL} then
        emit op_getupval(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_GETGLOBAL} then
        emit op_getglobal(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_GETTABLE} then
        emit op_gettable(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_SETGLOBAL} then
        emit op_setglobal(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_SETUPVAL} then
        emit op_setupval(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_SETTABLE} then
        emit op_settable(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_NEWTABLE} then
        emit op_newtable(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, oom = do_oom)
    case @{OP_SELF} then
        emit op_self(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_ADD} then
        emit op_add(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_SUB} then
        emit op_sub(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_MUL} then
        emit op_mul(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_DIV} then
        emit op_div(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_MOD} then
        emit op_mod(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_POW} then
        emit op_pow(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_UNM} then
        emit op_unm(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error)
    case @{OP_NOT} then
        emit op_not(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next)
    case @{OP_LEN} then
        emit op_len(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_CONCAT} then
        emit op_concat(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_JMP} then
        emit op_jmp(L, frame, pc, base, top, a, b, c, bx, sbx; do_jump = forward_jump)
    case @{OP_EQ} then
        emit op_eq(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_LT} then
        emit op_lt(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_LE} then
        emit op_le(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_TEST} then
        emit op_test(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump)
    case @{OP_TESTSET} then
        emit op_testset(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump)
    case @{OP_CALL} then
        emit op_call(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_TAILCALL} then
        emit op_tailcall(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_RETURN} then
        emit op_return(L, frame, pc, base, top, a, b, c, bx, sbx; resume_parent = do_resume, finished = do_finished, error = do_error, oom = do_oom)
    case @{OP_FORLOOP} then
        emit op_forloop(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, error = do_error)
    case @{OP_FORPREP} then
        emit op_forprep(L, frame, pc, base, top, a, b, c, bx, sbx; do_jump = forward_jump, error = do_error)
    case @{OP_TFORLOOP} then
        emit op_tforloop(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = do_lua, enter_native = do_native, yielded = do_yielded, error = do_error, oom = do_oom)
    case @{OP_SETLIST} then
        emit op_setlist(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, oom = do_oom)
    case @{OP_CLOSE} then
        emit op_close(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, oom = do_oom)
    case @{OP_CLOSURE} then
        emit op_closure(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, error = do_error, oom = do_oom)
    case @{OP_VARARG} then
        emit op_vararg(L, frame, pc, base, top, a, b, c, bx, sbx; next = do_next, error = do_error, oom = do_oom)
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
-- Continuation forwarding blocks
block do_next(frame: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = frame, pc = pc, base = base, top = top)
end
block forward_jump(frame: ptr(Frame), pc: index, base: index, top: index)
    jump do_jump(frame = frame, pc = pc, base = base, top = top)
end
block do_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block do_returned(nres: i32)
    jump returned(nres = nres)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block do_error(code: i32)
    jump error(code = code)
end
block do_oom()
    jump oom()
end
block do_finished(nres: i32)
    jump finished(nres = nres)
end
block do_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
end
]]

-- opcodes metadata (still useful for other tooling)
local opcodes = {
    { name = "MOVE",     mode = "ABC",  handler = "op_move",     effects = {"next"} },
    { name = "LOADK",    mode = "ABx",  handler = "op_loadk",    effects = {"next"} },
    { name = "LOADBOOL", mode = "ABC",  handler = "op_loadbool", effects = {"next"} },
    { name = "LOADNIL",  mode = "ABC",  handler = "op_loadnil",  effects = {"next"} },
    { name = "GETUPVAL", mode = "ABC",  handler = "op_getupval", effects = {"next"} },
    { name = "GETGLOBAL",mode = "ABx",  handler = "op_getglobal",effects = {"next", "call", "error", "oom"} },
    { name = "GETTABLE", mode = "ABC",  handler = "op_gettable", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "SETGLOBAL",mode = "ABx",  handler = "op_setglobal",effects = {"next", "error", "oom"} },
    { name = "SETUPVAL", mode = "ABC",  handler = "op_setupval", effects = {"next"} },
    { name = "SETTABLE", mode = "ABC",  handler = "op_settable", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "NEWTABLE", mode = "ABC",  handler = "op_newtable", effects = {"next", "oom"} },
    { name = "SELF",     mode = "ABC",  handler = "op_self",     effects = {"next", "call", "yield", "error", "oom"} },
    { name = "ADD",      mode = "ABC",  handler = "op_add",      effects = {"next", "call", "yield", "error"} },
    { name = "SUB",      mode = "ABC",  handler = "op_sub",      effects = {"next", "call", "yield", "error"} },
    { name = "MUL",      mode = "ABC",  handler = "op_mul",      effects = {"next", "call", "yield", "error"} },
    { name = "DIV",      mode = "ABC",  handler = "op_div",      effects = {"next", "call", "yield", "error"} },
    { name = "MOD",      mode = "ABC",  handler = "op_mod",      effects = {"next", "call", "yield", "error"} },
    { name = "POW",      mode = "ABC",  handler = "op_pow",      effects = {"next", "call", "yield", "error"} },
    { name = "UNM",      mode = "ABC",  handler = "op_unm",      effects = {"next", "call", "yield", "error"} },
    { name = "NOT",      mode = "ABC",  handler = "op_not",      effects = {"next"} },
    { name = "LEN",      mode = "ABC",  handler = "op_len",      effects = {"next", "call", "yield", "error", "oom"} },
    { name = "CONCAT",   mode = "ABC",  handler = "op_concat",   effects = {"next", "call", "yield", "error", "oom"} },
    { name = "JMP",      mode = "AsBx", handler = "op_jmp",      effects = {"jump"} },
    { name = "EQ",       mode = "ABC",  handler = "op_eq",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "LT",       mode = "ABC",  handler = "op_lt",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "LE",       mode = "ABC",  handler = "op_le",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "TEST",     mode = "ABC",  handler = "op_test",     effects = {"next", "jump"} },
    { name = "TESTSET",  mode = "ABC",  handler = "op_testset",  effects = {"next", "jump"} },
    { name = "CALL",     mode = "ABC",  handler = "op_call",     effects = {"next", "call", "yield", "error", "oom"} },
    { name = "TAILCALL", mode = "ABC",  handler = "op_tailcall", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "RETURN",   mode = "ABC",  handler = "op_return",   effects = {"return", "finished", "error", "oom"} },
    { name = "FORLOOP",  mode = "AsBx", handler = "op_forloop",  effects = {"next", "jump", "error"} },
    { name = "FORPREP",  mode = "AsBx", handler = "op_forprep",  effects = {"jump", "error"} },
    { name = "TFORLOOP", mode = "ABC",  handler = "op_tforloop", effects = {"next", "jump", "call", "yield", "error", "oom"} },
    { name = "SETLIST",  mode = "ABC",  handler = "op_setlist",  effects = {"next", "oom"} },
    { name = "CLOSE",    mode = "A",    handler = "op_close",    effects = {"next", "oom"} },
    { name = "CLOSURE",  mode = "ABx",  handler = "op_closure",  effects = {"next", "oom"} },
    { name = "VARARG",   mode = "ABC",  handler = "op_vararg",   effects = {"next", "oom"} },
}

return {
    dispatch_instruction = dispatch_instruction,
    opcodes = opcodes,
}
