-- Lua Interpreter VM — Typed bytecode builder regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")

local V = {}
for k, v in pairs(const.Op) do V["OP_" .. k] = moon.int(v) end
for k, v in pairs(const.Tag) do V["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do V["TM_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ExpKind) do V["EXP_" .. k] = moon.int(v) end

local emit_compile_error = host.region(V) [[
region emit_compile_error(cu: ptr(CompileUnit), code: i32, token: u16;
                          error: cont(err: CompileError))
entry start()
    let lx: ptr(Lexer) = &cu.lexer
    let e: CompileError = {
        code = code,
        pos = { offset = lx.pos, line = lx.line, col = lx.col },
        token = token
    }
    jump error(err = e)
end
end
]]

local instr_push = host.region(V) [[
region instr_push(v: ptr(InstrVec), inst: Instr;
                  ok: cont(pc: index), oom: cont())
entry start()
    if v.len >= v.cap then jump oom() end
    let pc: index = v.len
    v.data[pc] = inst
    v.len = pc + 1
    jump ok(pc = pc)
end
end
]]

local emit_ABC = host.region(V) [[
region emit_ABC(cu: ptr(CompileUnit), op: u16, a: u16, b: u16, c: u16, k: u8;
                emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump oom() end
    let out_pc: index = fs.code.len
    fs.code.data[out_pc] = { word = as(u32, op) | (as(u32, a) << 7) | (as(u32, k) << 15) | (as(u32, b) << 16) | (as(u32, c) << 24) }
    fs.code.len = out_pc + 1
    fs.pc = fs.code.len
    jump emitted(pc = out_pc)
end
end
]]

local emit_AvBCk = host.region(V) [[
region emit_AvBCk(cu: ptr(CompileUnit), op: u16, a: u16, vb: u16, vc: u16, k: u8;
                  emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump oom() end
    let out_pc: index = fs.code.len
    fs.code.data[out_pc] = { word = as(u32, op) | (as(u32, a) << 7) | (as(u32, k) << 15) | (as(u32, vb) << 16) | (as(u32, vc) << 22) }
    fs.code.len = out_pc + 1
    fs.pc = fs.code.len
    jump emitted(pc = out_pc)
end
end
]]

local emit_ABx = host.region(V) [[
region emit_ABx(cu: ptr(CompileUnit), op: u16, a: u16, bx: u32;
                emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump oom() end
    let out_pc: index = fs.code.len
    fs.code.data[out_pc] = { word = as(u32, op) | (as(u32, a) << 7) | ((bx & 131071) << 15) }
    fs.code.len = out_pc + 1
    fs.pc = fs.code.len
    jump emitted(pc = out_pc)
end
end
]]

local emit_AsBx = host.region(V) [[
region emit_AsBx(cu: ptr(CompileUnit), op: u16, a: u16, sbx: i32;
                 emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump oom() end
    let out_pc: index = fs.code.len
    fs.code.data[out_pc] = { word = as(u32, op) | (as(u32, a) << 7) | (as(u32, sbx + 65535) << 15) }
    fs.code.len = out_pc + 1
    fs.pc = fs.code.len
    jump emitted(pc = out_pc)
end
end
]]

local reserve_reg = host.region(V) [[
region reserve_reg(cu: ptr(CompileUnit);
                   reg: cont(r: u16), limit_error: cont(err: CompileError))
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.freereg >= 255 then
        emit emit_compile_error(cu, @{PERR_TOO_MANY_REGS}, as(u16, 0); error = too_many)
    end
    let r: u16 = fs.freereg
    fs.freereg = r + 1
    if fs.freereg > fs.maxstack then fs.maxstack = fs.freereg end
    jump reg(r = r)
end
block too_many(err: CompileError)
    jump limit_error(err = err)
end
end
]]

local ensure_stack_reg = host.region(V) [[
region ensure_stack_reg(cu: ptr(CompileUnit), reg: u16;
                        ok: cont(), limit_error: cont(err: CompileError))
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if reg >= 255 then
        emit emit_compile_error(cu, @{PERR_TOO_MANY_REGS}, as(u16, 0); error = too_many)
    end
    let need: u16 = reg + 1
    if need > fs.freereg then fs.freereg = need end
    if need > fs.maxstack then fs.maxstack = need end
    jump ok()
end
block too_many(err: CompileError)
    jump limit_error(err = err)
end
end
]]

local emit_load_integer = host.region(V) [[
region emit_load_integer(cu: ptr(CompileUnit), dst: u16, n: i64;
                         ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_AsBx(cu, as(u16, @{OP_LOADI}), dst, as(i32, n);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index)
    jump ok()
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local emit_move = host.region(V) [[
region emit_move(cu: ptr(CompileUnit), dst: u16, src: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    if dst == src then jump ok() end
    emit emit_ABC(cu, as(u16, @{OP_MOVE}), dst, src, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index)
    jump ok()
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local emit_load_false = host.region(V) [[
region emit_load_false(cu: ptr(CompileUnit), dst: u16;
                       ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_LOADFALSE}), dst, as(u16, 0), as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_load_true = host.region(V) [[
region emit_load_true(cu: ptr(CompileUnit), dst: u16;
                      ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_LOADTRUE}), dst, as(u16, 0), as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_load_nil = host.region(V) [[
region emit_load_nil(cu: ptr(CompileUnit), dst: u16;
                     ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_LOADNIL}), dst, as(u16, 0), as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_binary_op = host.region(V) [[
region emit_binary_op(cu: ptr(CompileUnit), op: u16, tm: u16, dst: u16, lhs: u16, rhs: u16;
                      ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len + 1 >= fs.code.cap then jump oom() end
    let pc_op: index = fs.code.len
    fs.code.data[pc_op] = { word = as(u32, op) | (as(u32, dst) << 7) | (as(u32, lhs) << 16) | (as(u32, rhs) << 24) }
    let pc_mm: index = pc_op + 1
    fs.code.data[pc_mm] = { word = as(u32, @{OP_MMBIN}) | (as(u32, lhs) << 7) | (as(u32, rhs) << 16) | (as(u32, tm) << 24) }
    fs.code.len = pc_mm + 1
    fs.pc = fs.code.len
    jump ok()
end
end
]]

local emit_add = host.region(V) [[
region emit_add(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_ADD}), as(u16, @{TM_ADD}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_sub = host.region(V) [[
region emit_sub(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_SUB}), as(u16, @{TM_SUB}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_mul = host.region(V) [[
region emit_mul(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_MUL}), as(u16, @{TM_MUL}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_div = host.region(V) [[
region emit_div(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_DIV}), as(u16, @{TM_DIV}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_mod = host.region(V) [[
region emit_mod(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_MOD}), as(u16, @{TM_MOD}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_idiv = host.region(V) [[
region emit_idiv(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_IDIV}), as(u16, @{TM_IDIV}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_pow = host.region(V) [[
region emit_pow(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
               ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_POW}), as(u16, @{TM_POW}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_band = host.region(V) [[
region emit_band(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_BAND}), as(u16, @{TM_BAND}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_bor = host.region(V) [[
region emit_bor(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_BOR}), as(u16, @{TM_BOR}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_bxor = host.region(V) [[
region emit_bxor(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_BXOR}), as(u16, @{TM_BXOR}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_shl = host.region(V) [[
region emit_shl(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_SHL}), as(u16, @{TM_SHL}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_shr = host.region(V) [[
region emit_shr(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_binary_op(cu, as(u16, @{OP_SHR}), as(u16, @{TM_SHR}), dst, lhs, rhs;
        ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_unary_minus = host.region(V) [[
region emit_unary_minus(cu: ptr(CompileUnit), dst: u16, src: u16;
                        ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    if cu.current.code.len + 1 >= cu.current.code.cap then jump out_of_mem() end
    emit emit_ABC(cu, as(u16, @{OP_UNM}), dst, src, as(u16, 0), as(u8, 0);
        emitted = op_done, limit_error = too_big, oom = out_of_mem)
end
block op_done(pc: index)
    emit emit_ABC(cu, as(u16, @{OP_MMBIN}), dst, src, as(u16, @{TM_UNM}), as(u8, 0);
        emitted = mm_done, limit_error = too_big, oom = out_of_mem)
end
block mm_done(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_bnot = host.region(V) [[
region emit_bnot(cu: ptr(CompileUnit), dst: u16, src: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    if cu.current.code.len + 1 >= cu.current.code.cap then jump out_of_mem() end
    emit emit_ABC(cu, as(u16, @{OP_BNOT}), dst, src, as(u16, 0), as(u8, 0);
        emitted = op_done, limit_error = too_big, oom = out_of_mem)
end
block op_done(pc: index)
    emit emit_ABC(cu, as(u16, @{OP_MMBIN}), dst, src, as(u16, @{TM_BNOT}), as(u8, 0);
        emitted = mm_done, limit_error = too_big, oom = out_of_mem)
end
block mm_done(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_not = host.region(V) [[
region emit_not(cu: ptr(CompileUnit), dst: u16, src: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_NOT}), dst, src, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_call = host.region(V) [[
region emit_call(cu: ptr(CompileUnit), func_reg: u16, nargs: u16, wanted: u16;
                 ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_CALL}), func_reg, nargs + 1, wanted + 1, as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_len = host.region(V) [[
region emit_len(cu: ptr(CompileUnit), dst: u16, src: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_LEN}), dst, src, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_newtable = host.region(V) [[
region emit_newtable(cu: ptr(CompileUnit), dst: u16, array_hint: u16;
                     ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    var vb: u16 = array_hint
    if vb > 63 then vb = 63 end
    emit emit_AvBCk(cu, as(u16, @{OP_NEWTABLE}), dst, vb, as(u16, 1), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_setlist = host.region(V) [[
region emit_setlist(cu: ptr(CompileUnit), table_reg: u16, count: u16;
                    ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    if count == 0 then jump ok() end
    emit ensure_stack_reg(cu, table_reg + count; ok = stack_ok, limit_error = too_big)
end
block stack_ok()
    emit emit_AvBCk(cu, as(u16, @{OP_SETLIST}), table_reg, count, as(u16, 1), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_return0 = host.region(V) [[
region emit_return0(cu: ptr(CompileUnit);
                    ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_RETURN0}), as(u16, 0), as(u16, 0), as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_vararg = host.region(V) [[
region emit_vararg(cu: ptr(CompileUnit), dst: u16, wanted: u16;
                   ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_VARARG}), dst, wanted + 1, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_test_jump_false = host.region(V) [[
region emit_test_jump_false(cu: ptr(CompileUnit), reg: u16;
                            emitted: cont(jmp_pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_TEST}), reg, as(u16, 0), as(u16, 1), as(u8, 0);
        emitted = test_done, limit_error = too_big, oom = out_of_mem)
end
block test_done(pc: index)
    emit emit_jump_placeholder(cu; emitted = got_jmp, limit_error = too_big, oom = out_of_mem)
end
block got_jmp(pc: index) jump emitted(jmp_pc = pc) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_compare_jump_false = host.region(V) [[
region emit_compare_jump_false(cu: ptr(CompileUnit), op: u16, expect: u16, lhs: u16, rhs: u16;
                                emitted: cont(jmp_pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, op, expect, lhs, rhs, as(u8, 0);
        emitted = cmp_done, limit_error = too_big, oom = out_of_mem)
end
block cmp_done(pc: index)
    emit emit_jump_placeholder(cu; emitted = got_jmp, limit_error = too_big, oom = out_of_mem)
end
block got_jmp(pc: index) jump emitted(jmp_pc = pc) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_compare_bool = host.region(V) [[
region emit_compare_bool(cu: ptr(CompileUnit), op: u16, expect: u16, dst: u16, lhs: u16, rhs: u16;
                         ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_compare_jump_false(cu, op, expect, lhs, rhs;
        emitted = got_false_jump,
        limit_error = too_big,
        oom = out_of_mem)
end
block got_false_jump(false_jmp: index)
    cu.scratch_index = false_jmp
    emit emit_load_true(cu, dst; ok = true_loaded, limit_error = too_big, oom = out_of_mem)
end
block true_loaded()
    emit emit_jump_placeholder(cu; emitted = got_end_jump, limit_error = too_big, oom = out_of_mem)
end
block got_end_jump(end_jmp: index)
    cu.scratch_index2 = end_jmp
    emit patch_jump_to_current(cu, cu.scratch_index; ok = false_target_ready)
end
block false_target_ready()
    emit emit_load_false(cu, dst; ok = false_loaded, limit_error = too_big, oom = out_of_mem)
end
block false_loaded()
    emit patch_jump_to_current(cu, cu.scratch_index2; ok = patched_end)
end
block patched_end() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_jump_placeholder = host.region(V) [[
region emit_jump_placeholder(cu: ptr(CompileUnit);
                             emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump out_of_mem() end
    let out_pc: index = fs.code.len
    fs.code.data[out_pc] = { word = as(u32, @{OP_JMP}) | (as(u32, 16777215) << 7) }
    fs.code.len = out_pc + 1
    fs.pc = fs.code.len
    jump emitted(pc = out_pc)
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local patch_jump_to_current = host.region(V) [[
region patch_jump_to_current(cu: ptr(CompileUnit), jmp_pc: index;
                             ok: cont())
entry start()
    let target: index = cu.current.code.len
    let sj: i32 = as(i32, target) - as(i32, jmp_pc)
    cu.current.code.data[jmp_pc].word = as(u32, @{OP_JMP}) | (as(u32, sj + 16777215) << 7)
    jump ok()
end
end
]]

local emit_jump_to_pc = host.region(V) [[
region emit_jump_to_pc(cu: ptr(CompileUnit), target: index;
                       ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len >= fs.code.cap then jump out_of_mem() end
    let pc: index = fs.code.len
    let sj: i32 = as(i32, target) - as(i32, pc)
    fs.code.data[pc] = { word = as(u32, @{OP_JMP}) | (as(u32, sj + 16777215) << 7) }
    fs.code.len = pc + 1
    fs.pc = fs.code.len
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_forprep_placeholder = host.region(V) [[
region emit_forprep_placeholder(cu: ptr(CompileUnit), base_reg: u16;
                                emitted: cont(pc: index), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABx(cu, as(u16, @{OP_FORPREP}), base_reg, as(u32, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump emitted(pc = pc) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_forloop_patch = host.region(V) [[
region emit_forloop_patch(cu: ptr(CompileUnit), base_reg: u16, forprep_pc: index;
                          ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let loop_pc: index = cu.current.code.len
    let bx: u32 = as(u32, loop_pc - forprep_pc - 1)
    cu.current.code.data[forprep_pc].word = as(u32, @{OP_FORPREP}) | (as(u32, base_reg) << 7) | ((bx & 131071) << 15)
    emit emit_ABx(cu, as(u16, @{OP_FORLOOP}), base_reg, bx;
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_return1 = host.region(V) [[
region emit_return1(cu: ptr(CompileUnit), src: u16;
                    ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    emit emit_ABC(cu, as(u16, @{OP_RETURN1}), src, as(u16, 0), as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index)
    jump ok()
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local add_local = host.region(V) [[
region add_local(cu: ptr(CompileUnit), tok: Token, reg: u16;
                 ok: cont(), limit_error: cont(err: CompileError))
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.locals_len >= fs.locals_cap then
        emit emit_compile_error(cu, @{PERR_TOO_MANY_REGS}, tok.kind; error = too_many)
    end
    let i: index = fs.locals_len
    fs.locals[i] = { name_start = tok.start, name_len = tok.len, hash = as(u32, tok.bits), reg = reg, kind = 0 }
    fs.locals_len = i + 1
    fs.nactvar = fs.nactvar + 1
    jump ok()
end
block too_many(err: CompileError)
    jump limit_error(err = err)
end
end
]]

local same_name = host.region [[
region same_name(bytes: ptr(u8), a_start: index, a_len: index, b_start: index, b_len: index;
                 yes: cont(), no: cont())
entry start()
    if a_len ~= b_len then jump no() end
    jump loop(i = as(index, 0))
end
block loop(i: index)
    if i >= a_len then jump yes() end
    if bytes[a_start + i] ~= bytes[b_start + i] then jump no() end
    jump loop(i = i + 1)
end
end
]]

local resolve_local = host.region(V) [[
region resolve_local(cu: ptr(CompileUnit), tok: Token;
                     found: cont(reg: u16), missing: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.locals_len == 0 then jump missing() end
    jump scan(i = fs.locals_len)
end
block scan(i: index)
    if i == 0 then jump missing() end
    let j: index = i - 1
    let local_desc: CompileLocal = cu.current.locals[j]
    if local_desc.hash == as(u32, tok.bits) and local_desc.name_len == tok.len then
        jump compare(idx = j, off = as(index, 0))
    end
    jump scan(i = j)
end
block compare(idx: index, off: index)
    let local_desc: CompileLocal = cu.current.locals[idx]
    if off >= tok.len then jump found(reg = local_desc.reg) end
    if cu.lexer.src.bytes[local_desc.name_start + off] ~= cu.lexer.src.bytes[tok.start + off] then
        jump scan(i = idx)
    end
    jump compare(idx = idx, off = off + 1)
end
end
]]

local close_func_builder = host.region(V) [[
region close_func_builder(cu: ptr(CompileUnit);
                          ok: cont(proto: ptr(Proto)), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    let p: ptr(Proto) = fs.out_proto
    p.code = fs.code.data
    p.code_len = fs.code.len
    p.constants = fs.constants.data
    p.constants_len = fs.constants.len
    p.children = fs.children.data
    p.children_len = fs.children.len
    p.locvars = fs.locvars.data
    p.locvars_len = fs.locvars.len
    p.upvals = fs.upvals.data
    p.upvals_len = fs.upvals.len
    p.numparams = fs.numparams
    p.flag = fs.flag
    if fs.maxstack == 0 then fs.maxstack = 1 end
    p.maxstack = fs.maxstack
    jump ok(proto = p)
end
end
]]

return {
    emit_compile_error = emit_compile_error,
    instr_push = instr_push,
    emit_ABC = emit_ABC,
    emit_AvBCk = emit_AvBCk,
    emit_ABx = emit_ABx,
    emit_AsBx = emit_AsBx,
    reserve_reg = reserve_reg,
    ensure_stack_reg = ensure_stack_reg,
    emit_load_integer = emit_load_integer,
    emit_move = emit_move,
    emit_load_false = emit_load_false,
    emit_load_true = emit_load_true,
    emit_load_nil = emit_load_nil,
    emit_binary_op = emit_binary_op,
    emit_add = emit_add,
    emit_sub = emit_sub,
    emit_mul = emit_mul,
    emit_div = emit_div,
    emit_mod = emit_mod,
    emit_idiv = emit_idiv,
    emit_pow = emit_pow,
    emit_band = emit_band,
    emit_bor = emit_bor,
    emit_bxor = emit_bxor,
    emit_shl = emit_shl,
    emit_shr = emit_shr,
    emit_unary_minus = emit_unary_minus,
    emit_bnot = emit_bnot,
    emit_not = emit_not,
    emit_call = emit_call,
    emit_len = emit_len,
    emit_newtable = emit_newtable,
    emit_setlist = emit_setlist,
    emit_return0 = emit_return0,
    emit_vararg = emit_vararg,
    emit_test_jump_false = emit_test_jump_false,
    emit_compare_jump_false = emit_compare_jump_false,
    emit_compare_bool = emit_compare_bool,
    emit_jump_placeholder = emit_jump_placeholder,
    patch_jump_to_current = patch_jump_to_current,
    emit_jump_to_pc = emit_jump_to_pc,
    emit_forprep_placeholder = emit_forprep_placeholder,
    emit_forloop_patch = emit_forloop_patch,
    emit_return1 = emit_return1,
    add_local = add_local,
    same_name = same_name,
    resolve_local = resolve_local,
    close_func_builder = close_func_builder,
}
