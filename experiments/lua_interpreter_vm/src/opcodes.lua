-- Lua Interpreter VM — Instruction dispatch (Lua 5.5)
-- Switch arms are built as typed moon.switch_arms-compatible values.
-- Hot inline arms (MOVE, LOADK, ADD) avoid second-level region emit.
-- Every arm is a grep-shaped { raw_key, body } pair.

local moon = require("moonlift")
local const = require("experiments.lua_interpreter_vm.src.constants")
local bytecode = require("experiments.lua_interpreter_vm.src.bytecode")
local handlers = require("experiments.lua_interpreter_vm.src.op_handlers")

local VALS = {}
for k, v in pairs(const.Tag)    do VALS["TAG_" .. k]    = moon.int(v) end
for k, v in pairs(const.Err)    do VALS["ERR_" .. k]    = moon.int(v) end
for k, v in pairs(const.Op)     do VALS["OP_" .. k]     = moon.int(v) end
for k, v in pairs(const.Resume) do VALS["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do VALS["PF_" .. k] = moon.int(v) end

-- Handler regions are spliced into emit targets as region fragments.  Opcode
-- argument lists are spliced as expression lists.  This keeps generation in the
-- intended moon.xxxx{values}[[...]] API instead of assembling Moonlift source
-- with Lua string concatenation.

local expr = moon.expr(VALS)
local stmts = moon.stmts(VALS)

-- Decode helpers — typed Moonlift expressions from the packed instruction word.
local D = bytecode.exprs(expr)
local A, B, C, K = D.A, D.B, D.C, D.K
local VB, VC = D.VB, D.VC
local BX, SBX, AX, SJ, SC = D.BX, D.SBX, D.AX, D.SJ, D.SC
local Z     = expr [[as(u16, 0)]]
local Z8    = expr [[as(u8, 0)]]
local Z32   = expr [[as(u32, 0)]]
local ZI    = expr [[0]]

local function args(a, b, c, k, bx, sbx, ax, sj, sc, vb, vc)
    return { a or Z, b or Z, c or Z, k or Z8, bx or Z32, sbx or ZI,
             ax or Z32, sj or ZI, sc or ZI, vb or Z, vc or Z }
end

local ARGS_A     = args(A)
local ARGS_AB    = args(A, B)
local ARGS_ABC   = args(A, B, C)
local ARGS_ABX   = args(A, nil, nil, nil, BX)
local ARGS_ASBX  = args(A, nil, nil, nil, nil, SBX)
local ARGS_AX    = args(nil, nil, nil, nil, nil, nil, AX)
local ARGS_ASJ   = args(nil, nil, nil, nil, nil, nil, nil, SJ)
local ARGS_ASC   = args(A, B, nil, nil, nil, nil, nil, nil, SC)
local ARGS_AVBC  = args(A, nil, nil, K, nil, nil, AX, nil, nil, VB, VC)
local ARGS_EXTRA = args(A, nil, nil, nil, nil, nil, AX)

-- ── Switch arms built as { raw_key, body } ───────────────────────────────

local switch_arms = {}
local inlined_ops = {}

local function inline_arm(op_num, body_src)
    inlined_ops[op_num] = true
    switch_arms[#switch_arms + 1] = {
        raw_key = tostring(op_num),
        body = stmts(body_src),
    }
end

-- Continuation mapping sets used by opcode handlers.  Cont_next / cont_jump /
-- cont_resume are adapter blocks that receive the handler's simple
-- (frame, pc, base, top) and forward to dispatch's richer continuations using
-- the region-level cur_code/cur_consts parameters.
local C_NEXT         = "next"
local C_NEXT_ERR     = "next_error"
local C_NEXT_OOM     = "next_oom"
local C_NEXT_ERR_OOM = "next_error_oom"
local C_TABLE        = "table"
local C_CMP          = "compare"
local C_MMBIN        = "metamethod_binary"
local C_TFORCALL     = "generic_for_call"
local C_CALL         = "call"
local C_RET          = "return"
local C_JMP          = "jump"
local C_JMP_ERR      = "jump_error"
local C_LOOP         = "loop"
local C_RET0         = "return0"
local C_JMP_NEXT     = "jump_next"
local C_NEXT_JMP     = "next_jump"

local emit_templates = {}

emit_templates[C_NEXT] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next)
]] end

emit_templates[C_NEXT_ERR] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next, error = cont_error)
]] end

emit_templates[C_NEXT_OOM] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next, oom = cont_oom)
]] end

emit_templates[C_NEXT_ERR_OOM] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next, error = cont_error, oom = cont_oom)
]] end

emit_templates[C_TABLE] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next,
        enter_lua = cont_enter_lua, enter_native = cont_enter_native, yielded = cont_yielded,
        error = cont_error, oom = cont_oom)
]] end

emit_templates[C_CMP] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next,
        do_jump = cont_jump, enter_lua = cont_enter_lua, enter_native = cont_enter_native,
        yielded = cont_yielded, error = cont_error, oom = cont_oom)
]] end

emit_templates[C_MMBIN] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...};
        enter_lua = cont_enter_lua, enter_native = cont_enter_native, yielded = cont_yielded,
        error = cont_error, oom = cont_oom)
]] end

emit_templates[C_TFORCALL] = emit_templates[C_MMBIN]

emit_templates[C_CALL] = emit_templates[C_TABLE]

emit_templates[C_RET] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...};
        resume_parent = cont_resume, finished = cont_returned, error = cont_error, oom = cont_oom)
]] end

emit_templates[C_JMP] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; do_jump = cont_jump)
]] end

emit_templates[C_JMP_ERR] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; do_jump = cont_jump, error = cont_error)
]] end

emit_templates[C_LOOP] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next,
        do_jump = cont_jump, error = cont_error)
]] end

emit_templates[C_RET0] = emit_templates[C_RET]

emit_templates[C_JMP_NEXT] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; do_jump = cont_jump, next = cont_next)
]] end

emit_templates[C_NEXT_JMP] = function(v) return moon.stmts(v) [[
    emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next, do_jump = cont_jump)
]] end

-- Build a single emit statement referencing a spliced handler region and a
-- spliced list of already-parsed Moonlift argument expressions.
local function emit_arm(op_num, handler_name, cont_set, arg_exprs)
    if inlined_ops[op_num] then return end
    local handler = assert(handlers[handler_name], "missing opcode handler " .. tostring(handler_name))
    local template = assert(emit_templates[cont_set], "missing opcode continuation template " .. tostring(cont_set))
    local values = { handler = handler, args = arg_exprs or args() }
    switch_arms[#switch_arms + 1] = {
        raw_key = tostring(op_num),
        body = template(values),
    }
end

-- ── Inline hot opcodes (no second region boundary) ────────────────────────

inline_arm(0, [[
    let src: index = cur_base + as(index, (word >> 16) & 255)
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    let tag: u32 = L.stack[src].tag
    let aux: u32 = L.stack[src].aux
    let bits: u64 = L.stack[src].bits
    L.stack[dst].tag = tag
    L.stack[dst].aux = aux
    L.stack[dst].bits = bits
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(3, [[
    let src: ptr(Value) = cur_consts + as(index, (word >> 15) & 131071)
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    let tag: u32 = src.tag
    let aux: u32 = src.aux
    let bits: u64 = src.bits
    L.stack[dst].tag = tag
    L.stack[dst].aux = aux
    L.stack[dst].bits = bits
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(34, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
    let lt: u32 = lhs.tag
    let rt: u32 = rhs.tag
    let lb: u64 = lhs.bits
    let rb: u64 = rhs.bits
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lt == @{TAG_NUM} and rt == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lb) + bitcast(f64, rb))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lt == @{TAG_INTEGER} and rt == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = as(u64, as(i64, lb) + as(i64, rb))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lt == @{TAG_INTEGER} and rt == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lb)) + bitcast(f64, rb))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lt == @{TAG_NUM} and rt == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lb) + as(f64, as(i64, rb)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(1, [[
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    L.stack[dst].tag = @{TAG_INTEGER}
    L.stack[dst].aux = 0
    L.stack[dst].bits = as(u64, as(i64, as(i32, ((word >> 15) & 131071)) - 65535))
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(2, [[
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    let v: i32 = as(i32, ((word >> 15) & 131071)) - 65535
    L.stack[dst].tag = @{TAG_NUM}
    L.stack[dst].aux = 0
    L.stack[dst].bits = bitcast(u64, as(f64, as(i64, v)))
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(4, [[
    let extra: ptr(Instr) = cur_code + (cur_pc + 1)
    let extra_ax: u32 = (extra.word >> 7) & 33554431
    let src: ptr(Value) = cur_consts + as(index, extra_ax)
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    L.stack[dst].tag = src.tag
    L.stack[dst].aux = src.aux
    L.stack[dst].bits = src.bits
    jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
]])

inline_arm(5, [[
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    L.stack[dst].tag = @{TAG_FALSE}
    L.stack[dst].aux = 0
    L.stack[dst].bits = 0
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(6, [[
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    L.stack[dst].tag = @{TAG_FALSE}
    L.stack[dst].aux = 0
    L.stack[dst].bits = 0
    jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
]])

inline_arm(7, [[
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    L.stack[dst].tag = @{TAG_TRUE}
    L.stack[dst].aux = 0
    L.stack[dst].bits = 0
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

local loadnil_values = { handler = handlers.op_loadnil, args = ARGS_AB }
for k, v in pairs(VALS) do loadnil_values[k] = v end
inlined_ops[8] = true
switch_arms[#switch_arms + 1] = {
    raw_key = "8",
    body = moon.stmts(loadnil_values) [[
        let first: index = cur_base + as(index, (word >> 7) & 255)
        let count: u16 = as(u16, (word >> 16) & 255)
        L.stack[first].tag = @{TAG_NIL}
        L.stack[first].aux = 0
        L.stack[first].bits = 0
        if count == as(u16, 0) then
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        L.stack[first + 1].tag = @{TAG_NIL}
        L.stack[first + 1].aux = 0
        L.stack[first + 1].bits = 0
        if count == as(u16, 1) then
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        L.stack[first + 2].tag = @{TAG_NIL}
        L.stack[first + 2].aux = 0
        L.stack[first + 2].bits = 0
        if count == as(u16, 2) then
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next)
    ]],
}

inline_arm(21, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let imm: i32 = as(i32, ((word >> 24) & 255)) - 127
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = lhs.bits + as(u64, imm)
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) + as(f64, as(i64, imm)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(22, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = cur_consts + as(index, (word >> 24) & 255)
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = lhs.bits + rhs.bits
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) + bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lhs.bits)) + bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) + as(f64, as(i64, rhs.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(35, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = lhs.bits - rhs.bits
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) - bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lhs.bits)) - bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) - as(f64, as(i64, rhs.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(36, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = lhs.bits * rhs.bits
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) * bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lhs.bits)) * bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) * as(f64, as(i64, rhs.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(39, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) / bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lhs.bits)) / as(f64, as(i64, rhs.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, as(f64, as(i64, lhs.bits)) / bitcast(f64, rhs.bits))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lhs.bits) / as(f64, as(i64, rhs.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(49, [[
    let src: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if src.tag == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = -(src.bits)
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    if src.tag == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, -(bitcast(f64, src.bits)))
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    cur_frame.resume.a = as(u16, (word >> 7) & 255)
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(51, [[
    let src: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let dst: index = cur_base + as(index, (word >> 7) & 255)
    if src.tag == @{TAG_NIL} or src.tag == @{TAG_FALSE} then
        L.stack[dst].tag = @{TAG_TRUE}
        L.stack[dst].aux = 0
        L.stack[dst].bits = 0
    else
        L.stack[dst].tag = @{TAG_FALSE}
        L.stack[dst].aux = 0
        L.stack[dst].bits = 0
    end
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

inline_arm(56, [[
    let new_pc: index = as(index, as(i32, cur_pc) + (as(i32, ((word >> 7) & 33554431)) - 16777215))
    jump cont_jump(frame = cur_frame, pc = new_pc, base = cur_base, top = cur_top)
]])

inline_arm(57, [[
    let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
    let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
    let expect: bool = as(u16, (word >> 7) & 255) ~= 0
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        if (bitcast(f64, lhs.bits) == bitcast(f64, rhs.bits)) == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        if (lhs.bits == rhs.bits) == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
        if (as(f64, as(i64, lhs.bits)) == bitcast(f64, rhs.bits)) == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
        if (bitcast(f64, lhs.bits) == as(f64, as(i64, rhs.bits))) == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if lhs.tag ~= rhs.tag then
        if false == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if lhs.tag == @{TAG_NIL} or lhs.tag == @{TAG_FALSE} or lhs.tag == @{TAG_TRUE} then
        if true == expect then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if (lhs.bits == rhs.bits) == expect then
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

local lt_values = { handler = handlers.op_lt, args = ARGS_ABC }
for k, v in pairs(VALS) do lt_values[k] = v end
inlined_ops[58] = true
switch_arms[#switch_arms + 1] = {
    raw_key = "58",
    body = moon.stmts(lt_values) [[
        let lhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 16) & 255))
        let rhs: ptr(Value) = L.stack + (cur_base + as(index, (word >> 24) & 255))
        let expect: bool = as(u16, (word >> 7) & 255) ~= 0
        if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
            if (bitcast(f64, lhs.bits) < bitcast(f64, rhs.bits)) == expect then
                jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
            end
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
            if (as(i64, lhs.bits) < as(i64, rhs.bits)) == expect then
                jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
            end
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_NUM} then
            if (as(f64, as(i64, lhs.bits)) < bitcast(f64, rhs.bits)) == expect then
                jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
            end
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_INTEGER} then
            if (bitcast(f64, lhs.bits) < as(f64, as(i64, rhs.bits))) == expect then
                jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
            end
            jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
        end
        emit @{handler}(L, cur_frame, cur_pc, cur_base, cur_top, @{args...}; next = cont_next,
            do_jump = cont_jump, enter_lua = cont_enter_lua, enter_native = cont_enter_native,
            yielded = cont_yielded, error = cont_error, oom = cont_oom)
    ]],
}

inline_arm(66, [[
    let val: ptr(Value) = L.stack + (cur_base + as(index, (word >> 7) & 255))
    let expect_false: bool = as(u16, (word >> 24) & 255) == 0
    if val.tag == @{TAG_NIL} or val.tag == @{TAG_FALSE} then
        if false ~= expect_false then
            jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
        end
        jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
    end
    if true ~= expect_false then
        jump cont_next(frame = cur_frame, pc = cur_pc + 2, base = cur_base, top = cur_top)
    end
    jump cont_next(frame = cur_frame, pc = cur_pc + 1, base = cur_base, top = cur_top)
]])

-- ── All other opcodes via handler region emit ─────────────────────────────

emit_arm(1,  "op_loadi",      C_NEXT,       ARGS_ASBX)
emit_arm(2,  "op_loadf",      C_NEXT,       ARGS_ASBX)
emit_arm(4,  "op_loadkx",     C_NEXT,       ARGS_EXTRA)
emit_arm(5,  "op_loadfalse",  C_NEXT,       ARGS_A)
emit_arm(6,  "op_lfalseskip", C_NEXT,       ARGS_A)
emit_arm(7,  "op_loadtrue",   C_NEXT,       ARGS_A)
emit_arm(8,  "op_loadnil",    C_NEXT,       ARGS_AB)
emit_arm(9,  "op_getupval",   C_NEXT,       ARGS_AB)
emit_arm(10, "op_setupval",   C_NEXT,       ARGS_AB)
emit_arm(11, "op_gettabup",   C_TABLE,      ARGS_ABC)
emit_arm(12, "op_gettable",   C_TABLE,      ARGS_ABC)
emit_arm(13, "op_geti",       C_TABLE,      ARGS_ABC)
emit_arm(14, "op_getfield",   C_TABLE,      ARGS_ABC)
emit_arm(15, "op_settabup",   C_TABLE,      ARGS_ABC)
emit_arm(16, "op_settable",   C_TABLE,      ARGS_ABC)
emit_arm(17, "op_setti",      C_TABLE,      ARGS_ABC)
emit_arm(18, "op_setfield",   C_TABLE,      ARGS_ABC)
emit_arm(19, "op_newtable",   C_NEXT_OOM,   ARGS_AVBC)
emit_arm(20, "op_self",       C_TABLE,      ARGS_ABC)
emit_arm(21, "op_addi",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(22, "op_addk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(23, "op_subk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(24, "op_mulk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(25, "op_modk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(26, "op_powk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(27, "op_divk",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(28, "op_idivk",      C_NEXT_ERR,   ARGS_ABC)
emit_arm(29, "op_bandk",      C_NEXT_ERR,   ARGS_ABC)
emit_arm(30, "op_bork",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(31, "op_bxork",      C_NEXT_ERR,   ARGS_ABC)
emit_arm(32, "op_shli",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(33, "op_shri",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(35, "op_sub",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(36, "op_mul",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(37, "op_mod",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(38, "op_pow",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(39, "op_div",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(40, "op_idiv",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(41, "op_band",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(42, "op_bor",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(43, "op_bxor",       C_NEXT_ERR,   ARGS_ABC)
emit_arm(44, "op_shl",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(45, "op_shr",        C_NEXT_ERR,   ARGS_ABC)
emit_arm(46, "op_mmbin",      C_MMBIN,      ARGS_ABC)
emit_arm(47, "op_mmbini",     C_MMBIN,      ARGS_ABC)
emit_arm(48, "op_mmbink",     C_MMBIN,      ARGS_ABC)
emit_arm(49, "op_unm",        C_NEXT_ERR,   ARGS_AB)
emit_arm(50, "op_bnot",       C_NEXT_ERR,   ARGS_AB)
emit_arm(51, "op_not",        C_NEXT,       ARGS_AB)
emit_arm(52, "op_len",        C_TABLE,      ARGS_ABC)
emit_arm(53, "op_concat",     C_TABLE,      ARGS_ABC)
emit_arm(54, "op_close",      C_NEXT_OOM,   ARGS_A)
emit_arm(55, "op_tbc",        C_NEXT_ERR_OOM, ARGS_A)
emit_arm(56, "op_jmp",        C_JMP,        ARGS_ASJ)
emit_arm(57, "op_eq",         C_CMP,        ARGS_ABC)
emit_arm(58, "op_lt",         C_CMP,        ARGS_ABC)
emit_arm(59, "op_le",         C_CMP,        ARGS_ABC)
emit_arm(60, "op_eqk",        C_NEXT_ERR_OOM, ARGS_ABX)
emit_arm(61, "op_eqi",        C_NEXT_ERR_OOM, ARGS_ASC)
emit_arm(62, "op_lti",        C_NEXT_ERR_OOM, ARGS_ASC)
emit_arm(63, "op_lei",        C_NEXT_ERR_OOM, ARGS_ASC)
emit_arm(64, "op_gti",        C_NEXT_ERR_OOM, ARGS_ASC)
emit_arm(65, "op_gei",        C_NEXT_ERR_OOM, ARGS_ASC)
emit_arm(66, "op_test",       C_JMP_NEXT,   ARGS_ABC)
emit_arm(67, "op_testset",    C_JMP_NEXT,   ARGS_ABC)
emit_arm(68, "op_call",       C_CALL,       ARGS_ABC)
emit_arm(69, "op_tailcall",   C_CALL,       ARGS_ABC)
emit_arm(70, "op_return",     C_RET,        ARGS_ABC)
emit_arm(71, "op_return0",    C_RET0,       ARGS_A)
emit_arm(72, "op_return1",    C_RET0,       ARGS_A)
emit_arm(73, "op_forloop",    C_LOOP,       ARGS_ABX)
emit_arm(74, "op_forprep",    C_JMP_ERR,    ARGS_ABX)
emit_arm(75, "op_tforprep",   C_JMP,        ARGS_ABX)
emit_arm(76, "op_tforcall",   C_TFORCALL,   ARGS_ABC)
emit_arm(77, "op_tforloop",   C_NEXT_JMP,   ARGS_ABX)
emit_arm(78, "op_setlist",    C_NEXT_OOM,   ARGS_AVBC)
emit_arm(79, "op_closure",    C_NEXT_ERR_OOM, ARGS_ABX)
emit_arm(80, "op_vararg",     C_NEXT_ERR_OOM, ARGS_ABC)
emit_arm(81, "op_getvarg",    C_NEXT_ERR_OOM, ARGS_ABC)
emit_arm(82, "op_errnnil",    C_NEXT_ERR_OOM, ARGS_ASBX)
emit_arm(83, "op_varargprep", C_NEXT_OOM,   ARGS_A)
emit_arm(84, "op_extraarg",   C_NEXT,       ARGS_AX)

-- ── Region source with @{switch_arms...} splice ───────────────────────────
-- Handler regions use simple continuation signatures.  Adapter blocks below
-- provide concrete labels for generated arm bodies and forward to dispatch's
-- richer continuations, adding cur_code/cur_consts where needed.

local dispatch_src = [[
region dispatch_instruction(
    L: ptr(LuaThread),
    cur_frame: ptr(Frame),
    cur_pc: index,
    cur_base: index,
    cur_top: index,
    cur_code: ptr(Instr),
    cur_consts: ptr(Value);
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index,
               code: ptr(Instr), constants: ptr(Value)),
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index,
                  code: ptr(Instr), constants: ptr(Value)),
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index,
                        code: ptr(Instr), constants: ptr(Value)),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure), ctx: NativeCallContext),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
entry decode()
    let ip: ptr(Instr) = cur_code + cur_pc
    let word: u32 = ip.word
    let op: u16 = as(u16, word & 127)
    switch op do
@{switch_arms...}
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
block cont_next(frame: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = frame, pc = pc, base = base, top = top,
              code = cur_code, constants = cur_consts)
end
block cont_jump(frame: ptr(Frame), pc: index, base: index, top: index)
    jump do_jump(frame = frame, pc = pc, base = base, top = top,
                 code = cur_code, constants = cur_consts)
end
block cont_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    -- cur_code/cur_consts may belong to the returning child frame. vm_loop
    -- must reload cached proto pointers when this continuation switches frames.
    jump resume_parent(parent = parent, pc = pc, base = base, top = top,
                       code = cur_code, constants = cur_consts)
end
block cont_enter_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block cont_enter_native(cl: ptr(CClosure), ctx: NativeCallContext)
    jump enter_native(cl = cl, ctx = ctx)
end
block cont_returned(nres: i32)
    jump returned(nres = nres)
end
block cont_yielded(nres: i32)
    jump yielded(nres = nres)
end
block cont_error(code: i32)
    jump error(code = code)
end
block cont_oom()
    jump oom()
end
end
]]

local dispatch_values = {}
for k, v in pairs(VALS) do dispatch_values[k] = v end
dispatch_values.switch_arms = switch_arms

local dispatch_instruction = moon.region(dispatch_values)(dispatch_src)

-- ── Opcode metadata (tooling, disassembly) ────────────────────────────────

local opcodes_meta = {}
for name, val in pairs(const.Op) do if val <= 84 then
    local hname = "op_" .. name:lower()
    if name == "SETI" then hname = "op_setti" end
    local entry = { name = name, op = val, handler = hname }
    if     name == "MOVE"       then entry.mode = "ABC"  elseif name == "LOADI"      then entry.mode = "AsBx"
    elseif name == "LOADF"      then entry.mode = "AsBx" elseif name == "LOADK"      then entry.mode = "ABx"
    elseif name == "LOADKX"     then entry.mode = "ABx"  elseif name == "LOADFALSE"  then entry.mode = "A"
    elseif name == "LFALSESKIP" then entry.mode = "A"    elseif name == "LOADTRUE"   then entry.mode = "A"
    elseif name == "LOADNIL"    then entry.mode = "AB"   elseif name == "GETUPVAL"   then entry.mode = "ABC"
    elseif name == "SETUPVAL"   then entry.mode = "ABC"  elseif name == "GETTABUP"   then entry.mode = "ABC"
    elseif name == "GETTABLE"   then entry.mode = "ABC"  elseif name == "GETI"       then entry.mode = "ABC"
    elseif name == "GETFIELD"   then entry.mode = "ABC"  elseif name == "SETTABUP"   then entry.mode = "ABC"
    elseif name == "SETTABLE"   then entry.mode = "ABC"  elseif name == "SETTI"      then entry.mode = "ABC"
    elseif name == "SETFIELD"   then entry.mode = "ABC"  elseif name == "NEWTABLE"   then entry.mode = "AvBCk"
    elseif name == "SELF"       then entry.mode = "ABC"  elseif name == "ADDI"       then entry.mode = "AsC"
    elseif name == "ADDK"       then entry.mode = "ABC"  elseif name == "SUBK"       then entry.mode = "ABC"
    elseif name == "MULK"       then entry.mode = "ABC"  elseif name == "MODK"       then entry.mode = "ABC"
    elseif name == "POWK"       then entry.mode = "ABC"  elseif name == "DIVK"       then entry.mode = "ABC"
    elseif name == "IDIVK"      then entry.mode = "ABC"  elseif name == "BANDK"      then entry.mode = "ABC"
    elseif name == "BORK"       then entry.mode = "ABC"  elseif name == "BXORK"      then entry.mode = "ABC"
    elseif name == "SHLI"       then entry.mode = "ABC"  elseif name == "SHRI"       then entry.mode = "ABC"
    elseif name == "ADD"        then entry.mode = "ABC"  elseif name == "SUB"        then entry.mode = "ABC"
    elseif name == "MUL"        then entry.mode = "ABC"  elseif name == "MOD"        then entry.mode = "ABC"
    elseif name == "POW"        then entry.mode = "ABC"  elseif name == "DIV"        then entry.mode = "ABC"
    elseif name == "IDIV"       then entry.mode = "ABC"  elseif name == "BAND"       then entry.mode = "ABC"
    elseif name == "BOR"        then entry.mode = "ABC"  elseif name == "BXOR"       then entry.mode = "ABC"
    elseif name == "SHL"        then entry.mode = "ABC"  elseif name == "SHR"        then entry.mode = "ABC"
    elseif name == "MMBIN"      then entry.mode = "ABC"  elseif name == "MMBINI"     then entry.mode = "ABC"
    elseif name == "MMBINK"     then entry.mode = "ABC"  elseif name == "UNM"        then entry.mode = "ABC"
    elseif name == "BNOT"       then entry.mode = "ABC"  elseif name == "NOT"        then entry.mode = "ABC"
    elseif name == "LEN"        then entry.mode = "ABC"  elseif name == "CONCAT"     then entry.mode = "ABC"
    elseif name == "CLOSE"      then entry.mode = "A"    elseif name == "TBC"        then entry.mode = "A"
    elseif name == "JMP"        then entry.mode = "sJ"   elseif name == "EQ"         then entry.mode = "ABC"
    elseif name == "LT"         then entry.mode = "ABC"  elseif name == "LE"         then entry.mode = "ABC"
    elseif name == "EQK"        then entry.mode = "ABx"  elseif name == "EQI"        then entry.mode = "AsC"
    elseif name == "LTI"        then entry.mode = "AsC"  elseif name == "LEI"        then entry.mode = "AsC"
    elseif name == "GTI"        then entry.mode = "AsC"  elseif name == "GEI"        then entry.mode = "AsC"
    elseif name == "TEST"       then entry.mode = "ABC"  elseif name == "TESTSET"    then entry.mode = "ABC"
    elseif name == "CALL"       then entry.mode = "ABC"  elseif name == "TAILCALL"   then entry.mode = "ABC"
    elseif name == "RETURN"     then entry.mode = "ABC"  elseif name == "RETURN0"    then entry.mode = "A"
    elseif name == "RETURN1"    then entry.mode = "A"    elseif name == "FORLOOP"    then entry.mode = "ABx"
    elseif name == "FORPREP"    then entry.mode = "ABx"  elseif name == "TFORPREP"   then entry.mode = "ABx"
    elseif name == "TFORCALL"   then entry.mode = "ABC"  elseif name == "TFORLOOP"   then entry.mode = "ABx"
    elseif name == "SETLIST"    then entry.mode = "AvBCk" elseif name == "CLOSURE"    then entry.mode = "ABx"
    elseif name == "VARARG"     then entry.mode = "ABC"  elseif name == "GETVARG"    then entry.mode = "ABC"
    elseif name == "ERRNNIL"    then entry.mode = "AsBx" elseif name == "VARARGPREP" then entry.mode = "A"
    elseif name == "EXTRAARG"   then entry.mode = "Ax"   end
    opcodes_meta[val] = entry
end end

return {
    dispatch_instruction = dispatch_instruction,
    opcodes = opcodes_meta,
}
