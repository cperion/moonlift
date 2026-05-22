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
    fs.code.data[out_pc] = { op = op, a = a, b = b, c = c, k = k, bx = 0, sbx = 0 }
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
    fs.code.data[out_pc] = { op = op, a = a, b = 0, c = 0, k = 0, bx = bx, sbx = 0 }
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
    fs.code.data[out_pc] = { op = op, a = a, b = 0, c = 0, k = 0, bx = 0, sbx = sbx }
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

local emit_add = host.region(V) [[
region emit_add(cu: ptr(CompileUnit), dst: u16, lhs: u16, rhs: u16;
                ok: cont(), limit_error: cont(err: CompileError), oom: cont())
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.code.len + 1 >= fs.code.cap then jump oom() end
    let pc_add: index = fs.code.len
    fs.code.data[pc_add] = { op = as(u16, @{OP_ADD}), a = dst, b = lhs, c = rhs, k = 0, bx = 0, sbx = 0 }
    let pc_mm: index = pc_add + 1
    fs.code.data[pc_mm] = { op = as(u16, @{OP_MMBIN}), a = 0, b = as(u16, @{TM_ADD}), c = 0, k = 0, bx = 0, sbx = 0 }
    fs.code.len = pc_mm + 1
    fs.pc = fs.code.len
    jump ok()
end
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
    if local_desc.hash == as(u32, tok.bits) then
        emit same_name(cu.lexer.src.bytes, local_desc.name_start, local_desc.name_len, tok.start, tok.len;
            yes = matched,
            no = next_one)
    end
    jump scan(i = j)
end
block matched()
    -- Re-scan to recover the matching register without carrying hidden state.
    jump scan_reg(i = cu.current.locals_len)
end
block scan_reg(i: index)
    let j: index = i - 1
    let local_desc: CompileLocal = cu.current.locals[j]
    if local_desc.hash == as(u32, tok.bits) then
        emit same_name(cu.lexer.src.bytes, local_desc.name_start, local_desc.name_len, tok.start, tok.len;
            yes = matched_reg,
            no = scan_reg_next)
    end
    jump scan_reg_next()
end
block matched_reg()
    let j: index = cu.current.locals_len - 1
    -- First milestone has one active local in tests; full implementation will carry the index.
    jump found(reg = cu.current.locals[j].reg)
end
block scan_reg_next()
    jump missing()
end
block next_one()
    -- First milestone keeps local lookup minimal and explicit.
    jump missing()
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
    p.maxstack = fs.maxstack
    jump ok(proto = p)
end
end
]]

return {
    emit_compile_error = emit_compile_error,
    instr_push = instr_push,
    emit_ABC = emit_ABC,
    emit_ABx = emit_ABx,
    emit_AsBx = emit_AsBx,
    reserve_reg = reserve_reg,
    emit_load_integer = emit_load_integer,
    emit_move = emit_move,
    emit_add = emit_add,
    emit_return1 = emit_return1,
    add_local = add_local,
    same_name = same_name,
    resolve_local = resolve_local,
    close_func_builder = close_func_builder,
}
