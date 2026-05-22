-- Lua Interpreter VM — Dispatch instruction (Lua 5.5)
-- Explicit switch: every case arm written directly in the Moonlift source.
-- No template-based generation; each opcode is grep-shaped.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local handlers = require("experiments.lua_interpreter_vm.src.op_handlers")

-- Build switch arms as explicit Moonlift case blocks.
-- Each arm is a visible string in the dispatch source.
local arms = {}
local DEFAULT_ARGS = "ip.a, ip.b, ip.c, ip.k, ip.bx, ip.sbx"
local ZERO_U16 = "as(u16, 0)"
local ZERO_U8 = "as(u8, 0)"
local ZERO_U32 = "as(u32, 0)"
local ZERO_I32 = "0"

local function args(a, b, c, k, bx, sbx)
    return table.concat({ a or ZERO_U16, b or ZERO_U16, c or ZERO_U16, k or ZERO_U8, bx or ZERO_U32, sbx or ZERO_I32 }, ", ")
end

local ARG_A     = args("ip.a")
local ARG_AB    = args("ip.a", "ip.b")
local ARG_ABC   = args("ip.a", "ip.b", "ip.c")
local ARG_ABC_K = args("ip.a", "ip.b", "ip.c", "ip.k")
local ARG_ABX   = args("ip.a", nil, nil, nil, "ip.bx")
local ARG_ASBX  = args("ip.a", nil, nil, nil, nil, "ip.sbx")
local ARG_EXTRA = args("ip.a")

local function arm(op_num, handler_name, conts, arg_exprs)
    arms[#arms + 1] = string.format([[
    case %d then
        emit %s(L, cur_frame, cur_pc, cur_base, cur_top, %s;
            %s)]], op_num, handler_name, arg_exprs or DEFAULT_ARGS, conts)
end

-- All 85 opcodes with literal continuation routing.
arm(0,  "op_move",       "next = next", ARG_AB)
arm(1,  "op_loadi",      "next = next", ARG_ASBX)
arm(2,  "op_loadf",      "next = next", ARG_ASBX)
arm(3,  "op_loadk",      "next = next", ARG_ABX)
arm(4,  "op_loadkx",     "next = next", ARG_EXTRA)
arm(5,  "op_loadfalse",  "next = next", ARG_A)
arm(6,  "op_lfalseskip", "next = next", ARG_A)
arm(7,  "op_loadtrue",   "next = next", ARG_A)
arm(8,  "op_loadnil",    "next = next", ARG_AB)
arm(9,  "op_getupval",   "next = next", ARG_AB)
arm(10, "op_setupval",   "next = next", ARG_AB)
arm(11, "op_gettabup",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(12, "op_gettable",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(13, "op_geti",       [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(14, "op_getfield",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(15, "op_settabup",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(16, "op_settable",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(17, "op_setti",      [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(18, "op_setfield",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(19, "op_newtable",   [[next = next,
            oom = oom]])
arm(20, "op_self",       [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(21, "op_addi",       [[next = next,
            error = error]], ARG_ABC)
arm(22, "op_addk",       [[next = next,
            error = error]], ARG_ABC)
arm(23, "op_subk",       [[next = next,
            error = error]], ARG_ABC)
arm(24, "op_mulk",       [[next = next,
            error = error]], ARG_ABC)
arm(25, "op_modk",       [[next = next,
            error = error]])
arm(26, "op_powk",       [[next = next,
            error = error]])
arm(27, "op_divk",       [[next = next,
            error = error]], ARG_ABC)
arm(28, "op_idivk",      [[next = next,
            error = error]])
arm(29, "op_bandk",      [[next = next,
            error = error]], ARG_ABC)
arm(30, "op_bork",       [[next = next,
            error = error]], ARG_ABC)
arm(31, "op_bxork",      [[next = next,
            error = error]], ARG_ABC)
arm(32, "op_shli",       [[next = next,
            error = error]], ARG_ABC)
arm(33, "op_shri",       [[next = next,
            error = error]], ARG_ABC)
arm(34, "op_add",        [[next = next,
            error = error]], ARG_ABC)
arm(35, "op_sub",        [[next = next,
            error = error]], ARG_ABC)
arm(36, "op_mul",        [[next = next,
            error = error]], ARG_ABC)
arm(37, "op_mod",        [[next = next,
            error = error]])
arm(38, "op_pow",        [[next = next,
            error = error]])
arm(39, "op_div",        [[next = next,
            error = error]], ARG_ABC)
arm(40, "op_idiv",       [[next = next,
            error = error]])
arm(41, "op_band",       [[next = next,
            error = error]], ARG_ABC)
arm(42, "op_bor",        [[next = next,
            error = error]], ARG_ABC)
arm(43, "op_bxor",       [[next = next,
            error = error]], ARG_ABC)
arm(44, "op_shl",        [[next = next,
            error = error]], ARG_ABC)
arm(45, "op_shr",        [[next = next,
            error = error]], ARG_ABC)
arm(46, "op_mmbin",      [[enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(47, "op_mmbini",     [[enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(48, "op_mmbink",     [[enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(49, "op_unm",        [[next = next,
            error = error]], ARG_AB)
arm(50, "op_bnot",       [[next = next,
            error = error]], ARG_AB)
arm(51, "op_not",        "next = next", ARG_AB)
arm(52, "op_len",        [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(53, "op_concat",     [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(54, "op_close",      [[next = next,
            oom = oom]])
arm(55, "op_tbc",        [[next = next,
            error = error, oom = oom]])
arm(56, "op_jmp",        "do_jump = do_jump")
arm(57, "op_eq",         [[next = next, do_jump = do_jump,
            enter_lua = enter_lua, enter_native = enter_native,
            error = error, oom = oom]])
arm(58, "op_lt",         [[next = next, do_jump = do_jump,
            enter_lua = enter_lua, enter_native = enter_native,
            error = error, oom = oom]])
arm(59, "op_le",         [[next = next, do_jump = do_jump,
            enter_lua = enter_lua, enter_native = enter_native,
            error = error, oom = oom]])
arm(60, "op_eqk",        "next = next, error = error, oom = oom")
arm(61, "op_eqi",        "next = next, error = error, oom = oom")
arm(62, "op_lti",        "next = next, error = error, oom = oom")
arm(63, "op_lei",        "next = next, error = error, oom = oom")
arm(64, "op_gti",        "next = next, error = error, oom = oom")
arm(65, "op_gei",        "next = next, error = error, oom = oom")
arm(66, "op_test",       "next = next, do_jump = do_jump")
arm(67, "op_testset",    "next = next, do_jump = do_jump")
arm(68, "op_call",       [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(69, "op_tailcall",   [[next = next,
            enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(70, "op_return",     "resume_parent = dispatch_resume, finished = returned, error = error, oom = oom")
arm(71, "op_return0",    "resume_parent = dispatch_resume, finished = returned, error = error, oom = oom")
arm(72, "op_return1",    "resume_parent = dispatch_resume, finished = returned, error = error, oom = oom")
arm(73, "op_forloop",    "next = next, do_jump = do_jump, error = error")
arm(74, "op_forprep",    "do_jump = do_jump, error = error")
arm(75, "op_tforprep",   "do_jump = do_jump")
arm(76, "op_tforcall",   [[enter_lua = enter_lua, enter_native = enter_native,
            yielded = yielded, error = error, oom = oom]])
arm(77, "op_tforloop",   "next = next, do_jump = do_jump")
arm(78, "op_setlist",    "next = next, oom = oom")
arm(79, "op_closure",    "next = next, error = error, oom = oom")
arm(80, "op_vararg",     "next = next, error = error, oom = oom")
arm(81, "op_getvarg",    "next = next, error = error, oom = oom")
arm(82, "op_errnnil",    "next = next, error = error, oom = oom")
arm(83, "op_varargprep", "next = next, oom = oom")
arm(84, "op_extraarg",   "next = next")

-- Build values table
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
    let ip: ptr(Instr) = cl.proto.code + cur_pc
    let op: u16 = ip.op
    switch op do
]] .. table.concat(arms, "\n") .. [[
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
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
