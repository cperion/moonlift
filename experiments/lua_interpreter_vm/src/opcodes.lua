-- Lua Interpreter VM — Dispatch instruction (Lua 5.5)
-- Uses @{arms...} switch spread + moon.stmts for typed handler bodies.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local handlers = require("experiments.lua_interpreter_vm.src.op_handlers")

-- Effect sets per handler: which continuations the handler uses.
local E = {}
local function e(t) return t end
E.op_move          = e { next = true }
E.op_loadi         = e { next = true }
E.op_loadf         = e { next = true }
E.op_loadk         = e { next = true }
E.op_loadkx        = e { next = true }
E.op_loadfalse     = e { next = true }
E.op_lfalseskip    = e { next = true }
E.op_loadtrue      = e { next = true }
E.op_loadnil       = e { next = true }
E.op_getupval      = e { next = true }
E.op_setupval      = e { next = true }
E.op_gettabup      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_gettable      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_geti          = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_getfield      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_settabup      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_settable      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_setti         = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_setfield      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_newtable      = e { next = true, oom = true }
E.op_self          = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_addi          = e { next = true, error = true }
E.op_addk          = e { next = true, error = true }
E.op_subk          = e { next = true, error = true }
E.op_mulk          = e { next = true, error = true }
E.op_modk          = e { next = true, error = true }
E.op_powk          = e { next = true, error = true }
E.op_divk          = e { next = true, error = true }
E.op_idivk         = e { next = true, error = true }
E.op_bandk         = e { next = true, error = true }
E.op_bork          = e { next = true, error = true }
E.op_bxork         = e { next = true, error = true }
E.op_shli          = e { next = true, error = true }
E.op_shri          = e { next = true, error = true }
E.op_add           = e { next = true, error = true }
E.op_sub           = e { next = true, error = true }
E.op_mul           = e { next = true, error = true }
E.op_mod           = e { next = true, error = true }
E.op_pow           = e { next = true, error = true }
E.op_div           = e { next = true, error = true }
E.op_idiv          = e { next = true, error = true }
E.op_band          = e { next = true, error = true }
E.op_bor           = e { next = true, error = true }
E.op_bxor          = e { next = true, error = true }
E.op_shl           = e { next = true, error = true }
E.op_shr           = e { next = true, error = true }
E.op_mmbin         = e { call = true, error = true, oom = true }
E.op_mmbini        = e { call = true, error = true, oom = true }
E.op_mmbink        = e { call = true, error = true, oom = true }
E.op_unm           = e { next = true, error = true }
E.op_bnot          = e { next = true, error = true }
E.op_not           = e { next = true }
E.op_len           = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_concat        = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_close         = e { next = true, oom = true }
E.op_tbc           = e { next = true, error = true, oom = true }
E.op_jmp           = e { jump = true }
E.op_eq            = e { next = true, jump = true, call = true, error = true, oom = true }
E.op_lt            = e { next = true, jump = true, call = true, error = true, oom = true }
E.op_le            = e { next = true, jump = true, call = true, error = true, oom = true }
E.op_eqk           = e { next = true, error = true, oom = true }
E.op_eqi           = e { next = true, error = true, oom = true }
E.op_lti           = e { next = true, error = true, oom = true }
E.op_lei           = e { next = true, error = true, oom = true }
E.op_gti           = e { next = true, error = true, oom = true }
E.op_gei           = e { next = true, error = true, oom = true }
E.op_test          = e { next = true, jump = true }
E.op_testset       = e { next = true, jump = true }
E.op_call          = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_tailcall      = e { next = true, call = true, yield = true, error = true, oom = true }
E.op_return        = e { returns = true, finished = true, error = true, oom = true }
E.op_return0       = e { returns = true, finished = true, error = true, oom = true }
E.op_return1       = e { returns = true, finished = true, error = true, oom = true }
E.op_forloop       = e { next = true, jump = true, error = true }
E.op_forprep       = e { jump = true, error = true }
E.op_tforprep      = e { jump = true }
E.op_tforcall      = e { call = true, yield = true, error = true, oom = true }
E.op_tforloop      = e { next = true, jump = true }
E.op_setlist       = e { next = true, oom = true }
E.op_closure       = e { next = true, error = true, oom = true }
E.op_vararg        = e { next = true, error = true, oom = true }
E.op_getvarg       = e { next = true, error = true, oom = true }
E.op_errnnil       = e { next = true, error = true, oom = true }
E.op_varargprep    = e { next = true, oom = true }
E.op_extraarg      = e { next = true }
E.op_loadk_fast    = e { next = true }
E.op_move_fast     = e { next = true }
E.op_add_num       = e { next = true }

-- Map opcode value → handler name
local by_op = {}
for k, v in pairs(const.Op) do
    local lname = k:lower()
    if lname ~= "loadk_fast" and lname ~= "move_fast" and lname ~= "add_num" then
        if lname == "seti" then
            by_op[v] = "op_setti"
        else
            by_op[v] = "op_" .. lname
        end
    end
end
by_op[const.Op.LOADK_FAST] = "op_loadk_fast"
by_op[const.Op.MOVE_FAST] = "op_move_fast"
by_op[const.Op.ADD_NUM] = "op_add_num"

-- Gather all needed opcodes
local all_ops = {}
for op = 0, 84 do
    local hname = by_op[op]
    if hname then table.insert(all_ops, { op = op, handler = hname, region = handlers[hname] }) end
end
for _, extra in ipairs({ { op = const.Op.LOADK_FAST, h = "op_loadk_fast" },
                         { op = const.Op.MOVE_FAST,  h = "op_move_fast" },
                         { op = const.Op.ADD_NUM,    h = "op_add_num" } }) do
    table.insert(all_ops, { op = extra.op, handler = extra.h, region = handlers[extra.h] })
end

-- Build switch arms as concrete Moonlift source.  The semantic values are the
-- typed handler region names; the generated text is only structural glue.
local function build_continuation_src(eff)
    local parts = {}
    if eff.next     then parts[#parts+1] = "next = do_next" end
    if eff.jump     then parts[#parts+1] = "do_jump = forward_jump" end
    if eff.call     then parts[#parts+1] = "enter_lua = dispatch_lua, enter_native = dispatch_native" end
    if eff.yield    then parts[#parts+1] = "yielded = dispatch_yielded" end
    if eff.error    then parts[#parts+1] = "error = dispatch_error" end
    if eff.oom      then parts[#parts+1] = "oom = dispatch_oom" end
    if eff.returns  then parts[#parts+1] = "resume_parent = dispatch_resume" end
    if eff.finished then parts[#parts+1] = "finished = dispatch_finished" end
    return table.concat(parts, ",\n            ")
end

local function make_arm_src(entry, eff)
    local conts = build_continuation_src(eff)
    return string.format([[
    case %d then
        emit %s(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx;
            %s)
]], entry.op, entry.handler, conts)
end

local dispatch_arm_src = {}
for _, entry in ipairs(all_ops) do
    local eff = E[entry.handler] or { next = true, error = true, oom = true }
    dispatch_arm_src[#dispatch_arm_src + 1] = make_arm_src(entry, eff)
end

-- Build values table with ALL needed constants
local VALS = {}
for k, v in pairs(const.Tag) do VALS["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do VALS["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do VALS["OP_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do VALS["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do VALS["PF_" .. k] = moon.int(v) end

local dispatch_src = [[
region dispatch_instruction(
    L: ptr(LuaThread),
    cur_frame: ptr(Frame),
    cur_pc: index,
    cur_base: index,
    cur_top: index;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
entry decode()
    let cl: ptr(LClosure) = as(ptr(LClosure), cur_frame.closure.bits)
    let code_ptr: ptr(Instr) = cl.proto.code + cur_pc
    let instr: Instr = *code_ptr
    let a: u16 = instr.a
    let b: u16 = instr.b
    let c: u16 = instr.c
    let bx: u32 = instr.bx
    let sbx: i32 = instr.sbx
    switch instr.op do
]] .. table.concat(dispatch_arm_src, "\n") .. [[
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
block do_next(frame: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = frame, pc = pc, base = base, top = top)
end
block forward_jump(frame: ptr(Frame), pc: index, base: index, top: index)
    jump do_jump(frame = frame, pc = pc, base = base, top = top)
end
block dispatch_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block dispatch_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block dispatch_returned(nres: i32)
    jump returned(nres = nres)
end
block dispatch_yielded(nres: i32)
    jump yielded(nres = nres)
end
block dispatch_error(code: i32)
    jump error(code = code)
end
block dispatch_oom()
    jump oom()
end
block dispatch_finished(nres: i32)
    jump returned(nres = nres)
end
block dispatch_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = parent, pc = pc, base = base, top = top)
end
end
]]

local dispatch_instruction = host.region(VALS)(dispatch_src)

-- Opcode metadata (for tooling, disassembly, etc.)
local opcodes_meta = {}
for name, val in pairs(const.Op) do if val <= 84 then
    local hname = "op_" .. name:lower()
    if name == "SETI" then hname = "op_setti" end
    local entry = { name = name, op = val, handler = hname }
    if name == "MOVE"       then entry.mode = "ABC" elseif name == "LOADI"      then entry.mode = "AsBx"
    elseif name == "LOADF"   then entry.mode = "AsBx" elseif name == "LOADK"     then entry.mode = "ABx"
    elseif name == "LOADKX"  then entry.mode = "ABx"  elseif name == "LOADFALSE" then entry.mode = "A"
    elseif name == "LFALSESKIP" then entry.mode = "A" elseif name == "LOADTRUE" then entry.mode = "A"
    elseif name == "LOADNIL" then entry.mode = "AB"   elseif name == "GETUPVAL"  then entry.mode = "ABC"
    elseif name == "SETUPVAL" then entry.mode = "ABC" elseif name == "GETTABUP"  then entry.mode = "ABC"
    elseif name == "GETTABLE" then entry.mode = "ABC" elseif name == "GETI"      then entry.mode = "ABC"
    elseif name == "GETFIELD" then entry.mode = "ABC" elseif name == "SETTABUP"  then entry.mode = "ABC"
    elseif name == "SETTABLE" then entry.mode = "ABC" elseif name == "SETTI"     then entry.mode = "ABC"
    elseif name == "SETFIELD" then entry.mode = "ABC" elseif name == "NEWTABLE"  then entry.mode = "ABC"
    elseif name == "SELF"    then entry.mode = "ABC"  elseif name == "ADDI"      then entry.mode = "ABC"
    elseif name == "ADDK"    then entry.mode = "ABx"  elseif name == "SUBK"      then entry.mode = "ABx"
    elseif name == "MULK"    then entry.mode = "ABx"  elseif name == "MODK"      then entry.mode = "ABx"
    elseif name == "POWK"    then entry.mode = "ABx"  elseif name == "DIVK"      then entry.mode = "ABx"
    elseif name == "IDIVK"   then entry.mode = "ABx"  elseif name == "BANDK"     then entry.mode = "ABx"
    elseif name == "BORK"    then entry.mode = "ABx"  elseif name == "BXORK"     then entry.mode = "ABx"
    elseif name == "SHLI"    then entry.mode = "ABC"  elseif name == "SHRI"      then entry.mode = "ABC"
    elseif name == "ADD"     then entry.mode = "ABC"  elseif name == "SUB"       then entry.mode = "ABC"
    elseif name == "MUL"     then entry.mode = "ABC"  elseif name == "MOD"       then entry.mode = "ABC"
    elseif name == "POW"     then entry.mode = "ABC"  elseif name == "DIV"       then entry.mode = "ABC"
    elseif name == "IDIV"    then entry.mode = "ABC"  elseif name == "BAND"      then entry.mode = "ABC"
    elseif name == "BOR"     then entry.mode = "ABC"  elseif name == "BXOR"      then entry.mode = "ABC"
    elseif name == "SHL"     then entry.mode = "ABC"  elseif name == "SHR"       then entry.mode = "ABC"
    elseif name == "MMBIN"   then entry.mode = "ABC"  elseif name == "MMBINI"    then entry.mode = "ABC"
    elseif name == "MMBINK"  then entry.mode = "ABx"  elseif name == "UNM"       then entry.mode = "ABC"
    elseif name == "BNOT"    then entry.mode = "ABC"  elseif name == "NOT"       then entry.mode = "ABC"
    elseif name == "LEN"     then entry.mode = "ABC"  elseif name == "CONCAT"    then entry.mode = "ABC"
    elseif name == "CLOSE"   then entry.mode = "A"    elseif name == "TBC"       then entry.mode = "A"
    elseif name == "JMP"     then entry.mode = "AsBx" elseif name == "EQ"        then entry.mode = "ABC"
    elseif name == "LT"      then entry.mode = "ABC"  elseif name == "LE"        then entry.mode = "ABC"
    elseif name == "EQK"     then entry.mode = "ABx"  elseif name == "EQI"       then entry.mode = "AsBx"
    elseif name == "LTI"     then entry.mode = "AsBx" elseif name == "LEI"       then entry.mode = "AsBx"
    elseif name == "GTI"     then entry.mode = "AsBx" elseif name == "GEI"       then entry.mode = "AsBx"
    elseif name == "TEST"    then entry.mode = "ABC"  elseif name == "TESTSET"   then entry.mode = "ABC"
    elseif name == "CALL"    then entry.mode = "ABC"  elseif name == "TAILCALL"  then entry.mode = "ABC"
    elseif name == "RETURN"  then entry.mode = "ABC"  elseif name == "RETURN0"   then entry.mode = "A"
    elseif name == "RETURN1" then entry.mode = "A"    elseif name == "FORLOOP"   then entry.mode = "AsBx"
    elseif name == "FORPREP" then entry.mode = "AsBx" elseif name == "TFORPREP"  then entry.mode = "AsBx"
    elseif name == "TFORCALL" then entry.mode = "ABC" elseif name == "TFORLOOP"  then entry.mode = "ABC"
    elseif name == "SETLIST" then entry.mode = "ABC"  elseif name == "CLOSURE"   then entry.mode = "ABx"
    elseif name == "VARARG"  then entry.mode = "ABC"  elseif name == "GETVARG"   then entry.mode = "ABC"
    elseif name == "ERRNNIL" then entry.mode = "AsBx" elseif name == "VARARGPREP" then entry.mode = "A"
    elseif name == "EXTRAARG" then entry.mode = "Ax"  end
    opcodes_meta[val] = entry
end end

return {
    dispatch_instruction = dispatch_instruction,
    opcodes = opcodes_meta,
}
