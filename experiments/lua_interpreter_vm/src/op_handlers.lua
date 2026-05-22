-- Lua Interpreter VM — All 85 opcode handler regions (Lua 5.5)
-- Every handler is a Moonlift region with @{TAG_INTEGER} etc. splices.
-- Arith bodies use Lua string concat ONLY for the expression (x + y, etc).

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

-- Values table: every constant available via @{TAG_INTEGER}, @{ERR_ARITH}, etc.
local VALS = {}
for k, v in pairs(const.Tag)    do VALS["TAG_" .. k]    = moon.int(v) end
for k, v in pairs(const.Err)    do VALS["ERR_" .. k]    = moon.int(v) end
for k, v in pairs(const.Resume) do VALS["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.TM)     do VALS["TM_" .. k]     = moon.int(v) end
for k, v in pairs(const.Op)     do VALS["OP_" .. k]     = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do VALS[k] = moon.int(v) end

-- Compile single source (strips leading whitespace for clean region parsing)
local function R(src)
    src = src:match("^%s*(.+)") or src
    return host.region(VALS)(src)
end

-- Build region header: always the same signature pattern
-- H = "L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32"
-- NOTE: NO leading '(' — the region template adds it.
local H = "L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32"

-- ============================================================
-- Arithmetic body templates
-- ============================================================
-- expr, x_expr, y_expr are Lua strings (Moonlift expressions like "x + y")
-- They get concatenated INTO the source at the right spots.
-- Everything else (tags, errors, resume modes) uses @{CONST} splices.

-- Pre-built body templates with concatenated expressions.
-- Register arithmetic in Lua 5.5 is followed by a MMBIN-family instruction.
-- On fast-path success we advance by two instructions; on failure we advance
-- by one so the metamethod instruction can run.
local function _body_int(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    let rhs: Value = L.stack[base + as(index, c)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, rhs.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_both(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    let rhs: Value = L.stack[base + as(index, c)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, rhs.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then\n" ..
    "        let x: f64 = as(f64, lhs.bits)\n" ..
    "        let y: f64 = as(f64, rhs.bits)\n" ..
    "        let r: f64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_float(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    let rhs: Value = L.stack[base + as(index, c)]\n" ..
    "    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then\n" ..
    "        let x: f64 = as(f64, lhs.bits)\n" ..
    "        let y: f64 = as(f64, rhs.bits)\n" ..
    "        let r: f64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_imm_both(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, as(i32, c))\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    if lhs.tag == @{TAG_NUM} then\n" ..
    "        let x: f64 = as(f64, lhs.bits)\n" ..
    "        let y: f64 = as(f64, as(i64, as(i32, c)))\n" ..
    "        let r: f64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_imm_int(expr)
    return "entry start()\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, as(i32, c))\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_k_both(expr)
    return "entry start()\n" ..
    "    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    let rhs: Value = cl.proto.constants[as(index, c)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, rhs.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then\n" ..
    "        let x: f64 = as(f64, lhs.bits)\n" ..
    "        let y: f64 = as(f64, rhs.bits)\n" ..
    "        let r: f64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_k_int(expr)
    return "entry start()\n" ..
    "    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)\n" ..
    "    let lhs: Value = L.stack[base + as(index, b)]\n" ..
    "    let rhs: Value = cl.proto.constants[as(index, c)]\n" ..
    "    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, lhs.bits)\n" ..
    "        let y: i64 = as(i64, rhs.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_unary(expr)
    return "entry start()\n" ..
    "    let v: Value = L.stack[base + as(index, b)]\n" ..
    "    if v.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, v.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    if v.tag == @{TAG_NUM} then\n" ..
    "        let x: f64 = as(f64, v.bits)\n" ..
    "        let r: f64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end
local function _body_unary_int(expr)
    return "entry start()\n" ..
    "    let v: Value = L.stack[base + as(index, b)]\n" ..
    "    if v.tag == @{TAG_INTEGER} then\n" ..
    "        let x: i64 = as(i64, v.bits)\n" ..
    "        let r: i64 = " .. expr .. "\n" ..
    "        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }\n" ..
    "        jump next(frame = frame, pc = pc + 2, base = base, top = top)\n" ..
    "    end\n" ..
    "    frame.resume_a = a\n" ..
    "    jump next(frame = frame, pc = pc + 1, base = base, top = top)\n" ..
    "end\nend\n"
end

local ARITH_STUB_BODY = [[
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]]

local function make_binary_handler(name, body)
    local conts = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index),\n               error: cont(code: i32)"
    return R("region " .. name .. "(" .. H .. "; " .. conts .. ")\n" .. body)
end

local function make_unary_handler(name, body)
    local conts = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index),\n               error: cont(code: i32)"
    return R("region " .. name .. "(" .. H .. "; " .. conts .. ")\n" .. body)
end

-- Generate all arithmetic + bitwise handlers
local arith_ops = {
    { n = "op_add",   body = _body_both("x + y") },
    { n = "op_sub",   body = _body_both("x - y") },
    { n = "op_mul",   body = _body_both("x * y") },
    { n = "op_mod",   body = ARITH_STUB_BODY },
    { n = "op_idiv",  body = ARITH_STUB_BODY },
    { n = "op_pow",   body = ARITH_STUB_BODY },
    { n = "op_div",   body = _body_float("x / y") },
    { n = "op_addi",  body = _body_imm_both("x + y") },
    { n = "op_shli",  body = _body_imm_int("y << x") },
    { n = "op_shri",  body = _body_imm_int("x >> y") },
    { n = "op_addk",  body = _body_k_both("x + y") },
    { n = "op_subk",  body = _body_k_both("x - y") },
    { n = "op_mulk",  body = _body_k_both("x * y") },
    { n = "op_modk",  body = ARITH_STUB_BODY },
    { n = "op_powk",  body = ARITH_STUB_BODY },
    { n = "op_divk",  body = _body_k_both("x / y") },
    { n = "op_idivk", body = ARITH_STUB_BODY },
    { n = "op_band",  body = _body_int("x & y") },
    { n = "op_bor",   body = _body_int("x | y") },
    { n = "op_bxor",  body = _body_int("x ~ y") },
    { n = "op_shl",   body = _body_int("x << y") },
    { n = "op_shr",   body = _body_int("x >> y") },
    { n = "op_bandk", body = _body_k_int("x & y") },
    { n = "op_bork",  body = _body_k_int("x | y") },
    { n = "op_bxork", body = _body_k_int("x ~ y") },
    { n = "op_unm",   body = _body_unary("-(x)") },
    { n = "op_bnot",  body = _body_unary_int("~x") },
}

local arith_handlers = {}
for _, entry in ipairs(arith_ops) do
    if entry.n:find("unm") then
        arith_handlers[entry.n] = make_unary_handler(entry.n, entry.body)
    else
        arith_handlers[entry.n] = make_binary_handler(entry.n, entry.body)
    end
end

-- ============================================================
-- MMBIN handlers (enter_lua / enter_native / yielded / error / oom)
-- ============================================================

local MMBIN_CONTS = "enter_lua: cont(child: ptr(Frame)),\n               enter_native: cont(cl: ptr(CClosure)),\n               yielded: cont(nres: i32),\n               error: cont(code: i32),\n               oom: cont()"

-- op_mmbin: generic MMBIN fallback handler (stub for now)
local op_mmbin = R [[
region op_mmbin(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                enter_lua: cont(child: ptr(Frame)),
                enter_native: cont(cl: ptr(CClosure)),
                yielded: cont(nres: i32),
                error: cont(code: i32),
                oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

-- op_mmbini: k determines operand order
-- op_mmbini: k determines operand order (stub)
local op_mmbini = R [[
region op_mmbini(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                 enter_lua: cont(child: ptr(Frame)),
                 enter_native: cont(cl: ptr(CClosure)),
                 yielded: cont(nres: i32),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

-- op_mmbink: k determines operand order, bx is constant index
-- op_mmbink: k determines operand order (stub)
local op_mmbink = R [[
region op_mmbink(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                 enter_lua: cont(child: ptr(Frame)),
                 enter_native: cont(cl: ptr(CClosure)),
                 yielded: cont(nres: i32),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

-- ============================================================
-- Simple one-line handlers (next only)
-- ============================================================

local next_only = "\n               next: cont(frame: ptr(Frame), pc: index, base: index, top: index)"

local op_move = R([[
region op_move(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadk = R([[
region op_loadk(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    L.stack[base + as(index, a)] = cl.proto.constants[bx]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadkx = R([[
region op_loadkx(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let extra: Instr = cl.proto.code[pc + 1]
    L.stack[base + as(index, a)] = cl.proto.constants[extra.bx]
    jump next(frame = frame, pc = pc + 2, base = base, top = top)
end
end
]])

local op_loadi = R([[
region op_loadi(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, sbx)) }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadf = R([[
region op_loadf(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, as(f64, as(i64, sbx))) }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadfalse = R([[
region op_loadfalse(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadtrue = R([[
region op_loadtrue(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_lfalseskip = R([[
region op_lfalseskip(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 2, base = base, top = top)
end
end
]])

local op_not = R([[
region op_not(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let val: Value = L.stack[base + as(index, b)]
    if val.tag == @{TAG_NIL} or val.tag == @{TAG_FALSE} then
        L.stack[base + as(index, a)] = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    else
        L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_getupval = R([[
region op_getupval(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    L.stack[base + as(index, a)] = *uv.v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_setupval = R([[
region op_setupval(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    let p: ptr(Value) = uv.v
    p[0] = L.stack[base + as(index, a)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_extraarg = R([[
region op_extraarg(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- LOADNIL with loop
local op_loadnil = R([[
region op_loadnil(]] .. H .. [[;]] .. next_only .. [[)
entry start()
    let first: index = base + as(index, a)
    let last: index = first + as(index, b)
    jump loop(i = first, last = last, ret_pc = pc + 1, ret_base = base, ret_top = top)
end
block loop(i: index, last: index, ret_pc: index, ret_base: index, ret_top: index)
    if i > last then jump next(frame = frame, pc = ret_pc, base = ret_base, top = ret_top) end
    L.stack[i] = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump loop(i = i + 1, last = last, ret_pc = ret_pc, ret_base = ret_base, ret_top = ret_top)
end
end
]])

-- JMP
local op_jmp = R([[
region op_jmp(]] .. H .. [[;
              do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]])

-- TEST / TESTSET
local op_test = R([[
region op_test(]] .. H .. [[;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, a)]
    var is_true: bool = false
    if val.tag ~= @{TAG_NIL} and val.tag ~= @{TAG_FALSE} then
        is_true = true
    end
    if is_true ~= (c == 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_testset = R([[
region op_testset(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, b)]
    var is_true: bool = false
    if val.tag ~= @{TAG_NIL} and val.tag ~= @{TAG_FALSE} then
        is_true = true
    end
    if is_true ~= (c == 0) then
        L.stack[base + as(index, a)] = val
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- CLOSE / TBC
local op_close = R([[
region op_close(]] .. H .. [[;
                next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                oom: cont())
entry start()
    let close_idx: index = base + as(index, a)
    emit close_upvalues(L, close_idx;
        done = closed,
        oom = out_of_mem)
end
block closed()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_tbc = R([[
region op_tbc(]] .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    L.tbc_head = base + as(index, a)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- ============================================================
-- TABLE ACCESS HANDLERS
-- ============================================================

-- Helper: common continuation list for table ops
local TABLE_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]

-- Common metamethod return blocks for table gets
local TABLE_GET_MM_BLOCKS = [[
block do_mm(mm: Value, self: Value, key: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    emit prepare_call(L, base, 2, 1, as(u16, @{RESUME_GETTABLE_MM});
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
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block mm_returned(nres: i32)
    let v: Value = L.stack[base]
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
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    L.stack[base + 3] = value
    emit prepare_call(L, base, 3, 0, as(u16, @{RESUME_SETTABLE_MM});
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
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
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

local op_gettabup = R([[
region op_gettabup(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    let tbl_val: Value = *uv.v
    let key: Value = cl.proto.constants[c]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl_val, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_gettable = R([[
region op_gettable(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_geti = R([[
region op_geti(]] .. H .. [[;
               ]] .. TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, c)) }
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_getfield = R([[
region op_getfield(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = cl.proto.constants[c]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_settabup = R([[
region op_settabup(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[a]
    let tbl_val: Value = *uv.v
    let key: Value = cl.proto.constants[b]
    let inst_stab: Instr = cl.proto.code[pc]
    emit resolve_rk(L, base, inst_stab.k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let cl_rk_stab: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv_rk_stab: ptr(UpVal) = cl_rk_stab.upvals[a]
    let tbl_val: Value = *uv_rk_stab.v
    let key: Value = cl_rk_stab.proto.constants[b]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl_val, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_settable = R([[
region op_settable(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    let val: Value = L.stack[base + as(index, a)]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, val;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_setti = R([[
region op_setti(]] .. H .. [[;
                ]] .. TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_sti: Instr = cl.proto.code[pc]
    emit resolve_rk(L, base, inst_sti.k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let tbl: Value = L.stack[base + as(index, a)]
    let key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, b)) }
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_setfield = R([[
region op_setfield(]] .. H .. [[;
                   ]] .. TABLE_CONTS .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_sf: Instr = cl.proto.code[pc]
    emit resolve_rk(L, base, inst_sf.k, c, cl.proto.constants;
        value = rk_val)
end
block rk_val(v: Value)
    let cl_rk_sf: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let tbl: Value = L.stack[base + as(index, a)]
    let key: Value = cl_rk_sf.proto.constants[b]
    frame.pc = pc
    L.top = top
    emit table_set(L, tbl, key, v;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_SET_MM_BLOCKS .. [[
end
]])

local op_newtable = R([[
region op_newtable(]] .. H .. [[;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   oom: cont())
entry start()
    jump oom()
end
end
]])

local op_self = R([[
region op_self(]] .. H .. [[;
               ]] .. TABLE_CONTS .. [[)
entry start()
    L.stack[base + as(index, a + 1)] = L.stack[base + as(index, b)]
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
]] .. TABLE_GET_MM_BLOCKS .. [[
end
]])

local op_setlist = R([[
region op_setlist(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  oom: cont())
entry start()
    jump oom()
end
end
]])

-- ============================================================
-- COMPARISON HANDLERS
-- ============================================================

local CMP_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]

local op_eq = R([[
region op_eq(]] .. H .. [[;
             ]] .. CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_equal(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_equal: bool)
    if is_equal == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_lt = R([[
region op_lt(]] .. H .. [[;
             ]] .. CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_less_than(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_lt: bool)
    if is_lt == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_le = R([[
region op_le(]] .. H .. [[;
             ]] .. CMP_CONTS .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    emit value_less_equal(L, lhs, rhs;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(is_le: bool)
    if is_le == (a ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value, fallback_lt: bool)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

-- EQK: R[A] == K[B]; k inverts skip
local op_eqk = R([[
region op_eqk(]] .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let cur_instr_eqk: Instr = cl.proto.code[pc]
    let lhs: Value = L.stack[base + as(index, a)]
    let rhs: Value = cl.proto.constants[bx]
    let kbit_eqk: u8 = cur_instr_eqk.k
    emit value_raw_equal(lhs, rhs;
        equal = yes,
        not_equal = no)
end
block yes()
    let cl_yes: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_yes: Instr = cl_yes.proto.code[pc]
    if inst_yes.k == 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block no()
    let cl_no: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_no: Instr = cl_no.proto.code[pc]
    if inst_no.k ~= 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- Comparison-with-immediate: k inverts skip, sbx is immediate
local function make_cmp_imm_handler(op_name, region_name, result_field, g_flip)
    local lhs, rhs
    if g_flip then
        lhs = "int_val"
        rhs = "L.stack[base + as(index, a)]"
    else
        lhs = "L.stack[base + as(index, a)]"
        rhs = "int_val"
    end

    return R([[
region ]] .. op_name .. "(" .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    let int_val: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, sbx)) }
    emit ]] .. region_name .. [[(L, ]] .. lhs .. [[, ]] .. rhs .. [[;
        result = cmp_result,
        call_mm = do_mm,
        error = cmp_err,
        oom = out_of_mem)
end
block cmp_result(]] .. result_field .. [[: bool)
    let cl_ci: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_ci: Instr = cl_ci.proto.code[pc]
    if ]] .. result_field .. [[ ~= (inst_ci.k ~= 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value)
    jump error(code = @{ERR_COMPARE})
end
block cmp_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])
end

local op_eqi = make_cmp_imm_handler("op_eqi", "value_equal", "is_equal", false)
local op_lti = make_cmp_imm_handler("op_lti", "value_less_than", "is_lt", false)
local op_lei = make_cmp_imm_handler("op_lei", "value_less_equal", "is_le", false)
local op_gti = make_cmp_imm_handler("op_gti", "value_less_than", "is_lt", true)
local op_gei = make_cmp_imm_handler("op_gei", "value_less_equal", "is_le", true)

-- ============================================================
-- LEN / CONCAT (stubs)
-- ============================================================

local STUB_CALL_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]

local op_len = R([[
region op_len(]] .. H .. [[;
              ]] .. STUB_CALL_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_concat = R([[
region op_concat(]] .. H .. [[;
                 ]] .. STUB_CALL_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

-- ============================================================
-- CALL / RETURN / TAILCALL
-- ============================================================

local CALL_CONTS = [[
next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont()]]

local op_call = R([[
region op_call(]] .. H .. [[;
               ]] .. CALL_CONTS .. [[)
entry start()
    let func_slot: index = base + as(index, a)
    var nargs: i32 = 0
    if b == 0 then
        nargs = as(i32, top - func_slot - 1)
    else
        nargs = as(i32, b - 1)
    end
    var wanted: i32 = 0
    if c == 0 then
        wanted = -1
    else
        wanted = as(i32, c - 1)
    end
    frame.pc = pc
    L.top = top
    emit prepare_call(L, func_slot, nargs, wanted, as(u16, @{RESUME_NORMAL});
        enter_lua = do_lua,
        enter_native = do_native,
        returned = call_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume_a = a
    child.resume_pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block call_returned(nres: i32)
    let func_slot: index = base + as(index, a)
    let dst: index = base + as(index, a)
    var wanted: i32 = 0
    if c == 0 then
        wanted = -1
    else
        wanted = as(i32, c - 1)
    end
    emit adjust_results(L, func_slot + 1, nres, wanted, dst;
        done = res_adjusted,
        oom = out_of_mem)
end
block res_adjusted(nplaced: i32)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
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
end
]])

local op_tailcall = R([[
region op_tailcall(]] .. H .. [[;
                   ]] .. CALL_CONTS .. [[)
entry start()
    let func_slot: index = base + as(index, a)
    var nargs: i32 = 0
    if b == 0 then
        nargs = as(i32, top - func_slot - 1)
    else
        nargs = as(i32, b - 1)
    end
    frame.pc = pc
    L.top = top
    emit prepare_call(L, func_slot, nargs, frame.wanted, as(u16, @{RESUME_TAILCALL});
        enter_lua = do_lua,
        enter_native = do_native,
        returned = call_returned,
        yielded = do_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block call_returned(nres: i32)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_yielded(nres: i32)
    jump yielded(nres = nres)
end
block call_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]])

local RET_CONTS = [[
resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                 finished: cont(nres: i32),
                 error: cont(code: i32),
                 oom: cont()]]

local op_return = R([[
region op_return(]] .. H .. [[;
                 ]] .. RET_CONTS .. [[)
entry start()
    let first: index = base + as(index, a)
    if b == 1 then
        jump do_return(first = first, nres = 0)
    end
    if b == 0 then
        jump do_return(first = first, nres = as(i32, top - first))
    end
    jump do_return(first = first, nres = as(i32, b - 1))
end
block do_return(first: index, nres: i32)
    let cl_ret: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_ret: Instr = cl_ret.proto.code[pc]
    if inst_ret.k ~= 0 then
        frame.resume_base = first
        frame.resume_a = as(u16, nres)
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = op_ret_error,
            oom = op_ret_oom)
    end
    jump after_tbc(first = first, nres = nres)
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume_base, nres = as(i32, frame.resume_a))
end
block after_tbc(first: index, nres: i32)
    emit return_from_lua(L, frame, first, nres;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

local op_return0 = R([[
region op_return0(]] .. H .. [[;
                  ]] .. RET_CONTS .. [[)
entry start()
    let cl_ret0: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_ret0: Instr = cl_ret0.proto.code[pc]
    if inst_ret0.k ~= 0 then
        frame.resume_base = base
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = op_ret_error,
            oom = op_ret_oom)
    end
    jump after_tbc(first = base)
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume_base)
end
block after_tbc(first: index)
    emit return_from_lua(L, frame, first, 0;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

local op_return1 = R([[
region op_return1(]] .. H .. [[;
                  ]] .. RET_CONTS .. [[)
entry start()
    let first: index = base + as(index, a)
    let cl_ret1: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let inst_ret1: Instr = cl_ret1.proto.code[pc]
    if inst_ret1.k ~= 0 then
        frame.resume_base = first
        emit tbc_close_chain(L, frame.base;
            done = after_tbc_saved,
            error = op_ret_error,
            oom = op_ret_oom)
    end
    jump after_tbc(first = first)
end
block after_tbc_saved()
    jump after_tbc(first = frame.resume_base)
end
block after_tbc(first: index)
    emit return_from_lua(L, frame, first, 1;
        resume_parent = op_ret_resume,
        finished = op_ret_finished,
        yielded = op_ret_yielded,
        error = op_ret_error,
        oom = op_ret_oom)
end
block op_ret_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block op_ret_finished(nres: i32)
    jump finished(nres = nres)
end
block op_ret_yielded(nres: i32)
    jump finished(nres = nres)
end
block op_ret_error(code: i32)
    jump error(code = code)
end
block op_ret_oom()
    jump oom()
end
end
]])

-- ============================================================
-- FOR LOOP
-- ============================================================

local op_forloop = R([[
region op_forloop(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32))
entry start()
    let idx_slot: index = base + as(index, a)
    let limit_slot: index = base + as(index, a + 1)
    let step_slot: index = base + as(index, a + 2)
    let idx_val: Value = L.stack[idx_slot]
    let limit_val: Value = L.stack[limit_slot]
    let step_val: Value = L.stack[step_slot]
    if idx_val.tag == @{TAG_INTEGER} and limit_val.tag == @{TAG_INTEGER} and step_val.tag == @{TAG_INTEGER} then
        let idx: i64 = as(i64, idx_val.bits) + as(i64, step_val.bits)
        L.stack[idx_slot] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, idx) }
        let limit: i64 = as(i64, limit_val.bits)
        let step: i64 = as(i64, step_val.bits)
        if (step >= 0 and idx <= limit) or (step < 0 and idx >= limit) then
            L.stack[base + as(index, a + 3)] = L.stack[idx_slot]
            let new_pc: index = as(index, as(i32, pc) + sbx)
            jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
        end
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    if idx_val.tag == @{TAG_NUM} and limit_val.tag == @{TAG_NUM} and step_val.tag == @{TAG_NUM} then
        let idx: f64 = as(f64, idx_val.bits) + as(f64, step_val.bits)
        L.stack[idx_slot] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, idx) }
        let limit: f64 = as(f64, limit_val.bits)
        let step: f64 = as(f64, step_val.bits)
        if (step >= 0.0 and idx <= limit) or (step < 0.0 and idx >= limit) then
            L.stack[base + as(index, a + 3)] = L.stack[idx_slot]
            let new_pc: index = as(index, as(i32, pc) + sbx)
            jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
        end
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_forprep = R([[
region op_forprep(]] .. H .. [[;
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32))
entry start()
    let init_slot: index = base + as(index, a)
    let limit_slot: index = base + as(index, a + 1)
    let step_slot: index = base + as(index, a + 2)
    let init_val: Value = L.stack[init_slot]
    let limit_val: Value = L.stack[limit_slot]
    let step_val: Value = L.stack[step_slot]
    if init_val.tag == @{TAG_INTEGER} and limit_val.tag == @{TAG_INTEGER} and step_val.tag == @{TAG_INTEGER} then
        let prepared: i64 = as(i64, init_val.bits) - as(i64, step_val.bits)
        L.stack[init_slot] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, prepared) }
        let new_pc: index = as(index, as(i32, pc) + sbx)
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    if init_val.tag == @{TAG_NUM} and limit_val.tag == @{TAG_NUM} and step_val.tag == @{TAG_NUM} then
        let prepared: f64 = as(f64, init_val.bits) - as(f64, step_val.bits)
        L.stack[init_slot] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, prepared) }
        let new_pc: index = as(index, as(i32, pc) + sbx)
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_tforprep = R([[
region op_tforprep(]] .. H .. [[;
                   do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]])

local op_tforcall = R([[
region op_tforcall(]] .. H .. [[;
                   ]] .. MMBIN_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_tforloop = R([[
region op_tforloop(]] .. H .. [[;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let var_val: Value = L.stack[base + as(index, a + 2)]
    if var_val.tag ~= @{TAG_NIL} then
        L.stack[base + as(index, a)] = var_val
        let new_pc: index = as(index, as(i32, pc) - as(i32, bx))
        jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- ============================================================
-- VARARG / CLOSURE / ERR
-- ============================================================

local op_closure = R([[
region op_closure(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_vararg = R([[
region op_vararg(]] .. H .. [[;
                 next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_getvarg = R([[
region op_getvarg(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_errnnil = R([[
region op_errnnil(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    let val: Value = L.stack[base + as(index, a)]
    if val.tag == @{TAG_NIL} then
        jump error(code = @{ERR_RUNTIME})
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_varargprep = R([[
region op_varargprep(]] .. H .. [[;
                     next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                     oom: cont())
entry start()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- ============================================================
-- QUICKENED
-- ============================================================

local op_move_fast = R([[
region op_move_fast(]] .. H .. [[;
                    ]] .. next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadk_fast = R([[
region op_loadk_fast(]] .. H .. [[;
                     ]] .. next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    L.stack[base + as(index, a)] = cl.proto.constants[bx]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_add_num = R([[
region op_add_num(]] .. H .. [[;
                  ]] .. next_only .. [[)
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) + as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

-- ============================================================
-- EXPORT
-- ============================================================

return setmetatable({
    -- Simple
    op_move = op_move, op_loadk = op_loadk, op_loadkx = op_loadkx,
    op_loadfalse = op_loadfalse, op_loadtrue = op_loadtrue, op_lfalseskip = op_lfalseskip,
    op_loadi = op_loadi, op_loadf = op_loadf, op_loadnil = op_loadnil,
    op_getupval = op_getupval, op_setupval = op_setupval,
    op_not = op_not, op_jmp = op_jmp,
    op_test = op_test, op_testset = op_testset,
    op_close = op_close, op_tbc = op_tbc, op_extraarg = op_extraarg,
    -- Table
    op_gettabup = op_gettabup, op_gettable = op_gettable,
    op_geti = op_geti, op_getfield = op_getfield,
    op_settabup = op_settabup, op_settable = op_settable,
    op_setti = op_setti, op_setfield = op_setfield,
    op_self = op_self, op_newtable = op_newtable, op_setlist = op_setlist,
    -- Comparisons
    op_eq = op_eq, op_lt = op_lt, op_le = op_le,
    op_eqk = op_eqk, op_eqi = op_eqi, op_lti = op_lti,
    op_lei = op_lei, op_gti = op_gti, op_gei = op_gei,
    -- MMBIN
    op_mmbin = op_mmbin, op_mmbini = op_mmbini, op_mmbink = op_mmbink,
    -- Call/Return
    op_call = op_call, op_tailcall = op_tailcall,
    op_return = op_return, op_return0 = op_return0, op_return1 = op_return1,
    -- For-loop
    op_forloop = op_forloop, op_forprep = op_forprep,
    op_tforprep = op_tforprep, op_tforcall = op_tforcall, op_tforloop = op_tforloop,
    -- Vararg / Closure
    op_len = op_len, op_concat = op_concat,
    op_closure = op_closure,
    op_vararg = op_vararg, op_getvarg = op_getvarg,
    op_errnnil = op_errnnil, op_varargprep = op_varargprep,
    -- Quickened
    op_move_fast = op_move_fast, op_loadk_fast = op_loadk_fast, op_add_num = op_add_num,
}, {
    -- Fallback: if a handler key isn't in the table, look it up in arith_handlers
    __index = arith_handlers,
})
