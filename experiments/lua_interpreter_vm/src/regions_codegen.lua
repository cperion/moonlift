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
V.SIZE_STRING = moon.int(40)

local emit_compile_error = host.region(V) [[
region emit_compile_error(cu: ptr(CompileUnit), code: i32, token: u16;
                          error(err: CompileError))
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

local emit_compile_error_at_span = host.region(V) [[
region emit_compile_error_at_span(cu: ptr(CompileUnit), code: i32, token: u16, span: SourceSpan;
                                  error(err: CompileError))
entry start()
    let e: CompileError = {
        code = code,
        pos = { offset = span.start, line = span.line, col = span.col },
        token = token
    }
    jump error(err = e)
end
end
]]

local instr_push = host.region(V) [[
region instr_push(v: ptr(InstrVec), inst: Instr;
                  ok(pc: index) | oom)
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
                emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                  emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                 emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                   reg(r: u16) | limit_error(err: CompileError))
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
                        ok | limit_error(err: CompileError))
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

local mark_regs = host.region(V) [[
region mark_regs(cu: ptr(CompileUnit); mark(r: u16))

entry start()
    jump mark(r = cu.current.freereg)
end
end
]]

local release_regs_to = host.region(V) [[
region release_regs_to(cu: ptr(CompileUnit), mark: u16; ok)

entry start()
    cu.current.freereg = mark
    jump ok()
end
end
]]

local arena_alloc_bytes = host.region(V) [[
region arena_alloc_bytes(cu: ptr(CompileUnit), size: index, align: u32;
                         ok(ptr: ptr(u8)) | oom)
entry start()
    var pos: index = cu.arena.pos
    let mask: index = as(index, align) - 1
    if mask ~= 0 then
        if (pos & mask) ~= 0 then pos = (pos + mask) & (as(index, 0) - as(index, align)) end
    end
    let end_pos: index = pos + size
    if end_pos > cu.arena.cap then
        cu.arena.overflowed = 1
        jump oom()
    end
    let ptr: ptr(u8) = cu.arena.base + pos
    cu.arena.pos = end_pos
    jump ok(ptr = ptr)
end
end
]]

local constant_push = host.region(V) [[
region constant_push(cu: ptr(CompileUnit), value: Value;
                     ok(idx: index) | oom)
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.constants.data == nil then jump oom() end
    if fs.constants.len >= fs.constants.cap then jump oom() end
    let idx: index = fs.constants.len
    fs.constants.data[idx] = value
    fs.constants.len = idx + 1
    jump ok(idx = idx)
end
end
]]

local upvaldesc_push = host.region(V) [[
region upvaldesc_push(cu: ptr(CompileUnit), desc: UpValDesc;
                      ok(idx: index) | oom)
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.upvals.data == nil then jump oom() end
    if fs.upvals.len >= fs.upvals.cap then jump oom() end
    let idx: index = fs.upvals.len
    fs.upvals.data[idx] = desc
    fs.upvals.len = idx + 1
    jump ok(idx = idx)
end
end
]]

local proto_ptr_push = host.region(V) [[
region proto_ptr_push(cu: ptr(CompileUnit), proto: ptr(Proto);
                      ok(idx: index) | oom)
entry start()
    let fs: ptr(FuncBuilder) = cu.current
    if fs.children.data == nil then jump oom() end
    if fs.children.len >= fs.children.cap then jump oom() end
    let idx: index = fs.children.len
    fs.children.data[idx] = proto
    fs.children.len = idx + 1
    jump ok(idx = idx)
end
end
]]

local ensure_env_upvalue = host.region(V) [[
region ensure_env_upvalue(cu: ptr(CompileUnit); ok | oom)

entry start()
    if cu.current.upvals.len > 0 then jump ok() end
    let desc: UpValDesc = { name = nil, instack = 1, index = 0 }
    emit upvaldesc_push(cu, desc; ok = made, oom = out_of_mem)
end
block made(idx: index) jump ok() end
block out_of_mem() jump oom() end
end
]]

local workspace_string_from_source = host.region(V) [[
region workspace_string_from_source(cu: ptr(CompileUnit), start: index, len: index;
                                    ok(str: ptr(String)) | oom)
entry start()
    emit arena_alloc_bytes(cu, as(index, @{SIZE_STRING}) + len + 1, as(u32, 8);
        ok = allocated,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let s: ptr(String) = as(ptr(String), ptr)
    s.gc.next = nil
    s.gc.tt = as(u8, @{TAG_STR})
    s.gc.marked = 0
    s.reserved = 0
    s.hash = as(u32, len)
    s.len = len
    s.bytes = ptr + as(index, @{SIZE_STRING})
    jump copy_loop(s = s, i = as(index, 0), h = as(u32, 5381))
end
block copy_loop(s: ptr(String), i: index, h: u32)
    if i >= s.len then jump copied(s = s, h = h) end
    let b: u8 = cu.lexer.src.bytes[start + i]
    s.bytes[i] = b
    jump copy_loop(s = s, i = i + 1, h = h * 33 + as(u32, b))
end
block copied(s: ptr(String), h: u32)
    s.bytes[s.len] = 0
    s.hash = h
    jump ok(str = s)
end
block out_of_mem() jump oom() end
end
]]

local get_string_constant = host.region(V) [[
region get_string_constant(cu: ptr(CompileUnit), start: index, len: index;
                           ok(idx: index) | oom)
entry start()
    if cu.current.constants.len == 0 then jump missing() end
    jump scan(i = as(index, 0))
end
block scan(i: index)
    if i >= cu.current.constants.len then jump missing() end
    let v: Value = cu.current.constants.data[i]
    if v.tag == @{TAG_STR} then
        let s: ptr(String) = as(ptr(String), v.bits)
        if s.len == len then jump compare(idx = i, s = s, off = as(index, 0)) end
    end
    jump scan(i = i + 1)
end
block compare(idx: index, s: ptr(String), off: index)
    if off >= len then jump ok(idx = idx) end
    if s.bytes[off] ~= cu.lexer.src.bytes[start + off] then jump scan(i = idx + 1) end
    jump compare(idx = idx, s = s, off = off + 1)
end
block missing()
    emit workspace_string_from_source(cu, start, len; ok = made_string, oom = out_of_mem)
end
block made_string(str: ptr(String))
    let v: Value = { tag = @{TAG_STR}, aux = 0, bits = as(u64, str) }
    emit constant_push(cu, v; ok = pushed, oom = out_of_mem)
end
block pushed(idx: index) jump ok(idx = idx) end
block out_of_mem() jump oom() end
end
]]

local emit_loadk = host.region(V) [[
region emit_loadk(cu: ptr(CompileUnit), dst: u16, const_idx: index;
                  ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABx(cu, as(u16, @{OP_LOADK}), dst, as(u32, const_idx);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_getupval = host.region(V) [[
region emit_getupval(cu: ptr(CompileUnit), dst: u16, upidx: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_GETUPVAL}), dst, upidx, as(u16, 0), as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_setupval = host.region(V) [[
region emit_setupval(cu: ptr(CompileUnit), src: u16, upidx: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_SETUPVAL}), src, upidx, as(u16, 0), as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_gettabup = host.region(V) [[
region emit_gettabup(cu: ptr(CompileUnit), dst: u16, upidx: u16, key_idx: index;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_GETTABUP}), dst, upidx, as(u16, key_idx), as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_settabup = host.region(V) [[
region emit_settabup(cu: ptr(CompileUnit), upidx: u16, key_idx: index, src: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_SETTABUP}), upidx, as(u16, key_idx), src, as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_gettable = host.region(V) [[
region emit_gettable(cu: ptr(CompileUnit), dst: u16, table_reg: u16, key_reg: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_GETTABLE}), dst, table_reg, key_reg, as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_settable = host.region(V) [[
region emit_settable(cu: ptr(CompileUnit), value_reg: u16, table_reg: u16, key_reg: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_SETTABLE}), value_reg, table_reg, key_reg, as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_getfield = host.region(V) [[
region emit_getfield(cu: ptr(CompileUnit), dst: u16, table_reg: u16, key_idx: index;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_GETFIELD}), dst, table_reg, as(u16, key_idx), as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_setfield = host.region(V) [[
region emit_setfield(cu: ptr(CompileUnit), table_reg: u16, key_idx: index, value_reg: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_SETFIELD}), table_reg, as(u16, key_idx), value_reg, as(u8, 0);
        emitted = done_pc,
        limit_error = too_big,
        oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_load_integer = host.region(V) [[
region emit_load_integer(cu: ptr(CompileUnit), dst: u16, n: i64;
                         ok | limit_error(err: CompileError) | oom)
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
                 ok | limit_error(err: CompileError) | oom)
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
                       ok | limit_error(err: CompileError) | oom)
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
                      ok | limit_error(err: CompileError) | oom)
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
                     ok | limit_error(err: CompileError) | oom)
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
                      ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                 ok | limit_error(err: CompileError) | oom)
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
               ok | limit_error(err: CompileError) | oom)
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
                 ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                 ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                        ok | limit_error(err: CompileError) | oom)
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
                 ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABC(cu, as(u16, @{OP_NOT}), dst, src, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_closure = host.region(V) [[
region emit_closure(cu: ptr(CompileUnit), dst: u16, child_idx: index;
                    ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_ABx(cu, as(u16, @{OP_CLOSURE}), dst, as(u32, child_idx);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_call = host.region(V) [[
region emit_call(cu: ptr(CompileUnit), func_reg: u16, nargs: u16, wanted: u16;
                 ok | limit_error(err: CompileError) | oom)
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
                ok | limit_error(err: CompileError) | oom)
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
                     ok | limit_error(err: CompileError) | oom)
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
                    ok | limit_error(err: CompileError) | oom)
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
                    ok | limit_error(err: CompileError) | oom)
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
                   ok | limit_error(err: CompileError) | oom)
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
                            emitted(jmp_pc: index) | limit_error(err: CompileError) | oom)
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
                                emitted(jmp_pc: index) | limit_error(err: CompileError) | oom)
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
                         ok | limit_error(err: CompileError) | oom)
entry start()
    emit emit_compare_jump_false(cu, op, expect, lhs, rhs;
        emitted = got_false_jump, limit_error = too_big, oom = out_of_mem)
end
block got_false_jump(jmp_pc: index)
    cu.durable_mark = jmp_pc
    emit emit_load_true(cu, dst; ok = true_loaded, limit_error = too_big, oom = out_of_mem)
end
block true_loaded()
    emit emit_jump_placeholder(cu; emitted = got_after_jump, limit_error = too_big, oom = out_of_mem)
end
block got_after_jump(pc: index)
    cu.parse_mark = pc
    emit patch_jump_to_current(cu, cu.durable_mark; ok = false_target_ready)
end
block false_target_ready()
    emit emit_load_false(cu, dst; ok = false_loaded, limit_error = too_big, oom = out_of_mem)
end
block false_loaded()
    emit patch_jump_to_current(cu, cu.parse_mark; ok = patched_end)
end
block patched_end() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local emit_jump_placeholder = host.region(V) [[
region emit_jump_placeholder(cu: ptr(CompileUnit);
                             emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                             ok)
entry start()
    let target: index = cu.current.code.len
    let sj: i32 = as(i32, target) - as(i32, jmp_pc)
    cu.current.code.data[jmp_pc].word = as(u32, @{OP_JMP}) | (as(u32, sj + 16777215) << 7)
    jump ok()
end
end
]]

local patch_jump_to_pc = host.region(V) [[
region patch_jump_to_pc(cu: ptr(CompileUnit), jmp_pc: index, target: index;
                        ok)
entry start()
    let sj: i32 = as(i32, target) - as(i32, jmp_pc)
    cu.current.code.data[jmp_pc].word = as(u32, @{OP_JMP}) | (as(u32, sj + 16777215) << 7)
    jump ok()
end
end
]]

local emit_jump_to_pc = host.region(V) [[
region emit_jump_to_pc(cu: ptr(CompileUnit), target: index;
                       ok | limit_error(err: CompileError) | oom)
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
                                emitted(pc: index) | limit_error(err: CompileError) | oom)
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
                          ok | limit_error(err: CompileError) | oom)
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
                    ok | limit_error(err: CompileError) | oom)
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

local emit_return_n = host.region(V) [[
region emit_return_n(cu: ptr(CompileUnit), first: u16, count: u16;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    if count == 0 then emit emit_return0(cu; ok = done, limit_error = too_big, oom = out_of_mem) end
    if count == 1 then emit emit_return1(cu, first; ok = done, limit_error = too_big, oom = out_of_mem) end
    emit emit_ABC(cu, as(u16, @{OP_RETURN}), first, count + 1, as(u16, 0), as(u8, 0);
        emitted = done_pc, limit_error = too_big, oom = out_of_mem)
end
block done_pc(pc: index) jump ok() end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local add_local = host.region(V) [[
region add_local(cu: ptr(CompileUnit), tok: Token, reg: u16;
                 ok | limit_error(err: CompileError))
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
                 yes | no)
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
                     found(reg: u16) | missing)
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
                          ok(proto: ptr(Proto)) | oom)
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
    emit_compile_error_at_span = emit_compile_error_at_span,
    instr_push = instr_push,
    emit_ABC = emit_ABC,
    emit_AvBCk = emit_AvBCk,
    emit_ABx = emit_ABx,
    emit_AsBx = emit_AsBx,
    reserve_reg = reserve_reg,
    ensure_stack_reg = ensure_stack_reg,
    mark_regs = mark_regs,
    release_regs_to = release_regs_to,
    arena_alloc_bytes = arena_alloc_bytes,
    constant_push = constant_push,
    upvaldesc_push = upvaldesc_push,
    proto_ptr_push = proto_ptr_push,
    ensure_env_upvalue = ensure_env_upvalue,
    workspace_string_from_source = workspace_string_from_source,
    get_string_constant = get_string_constant,
    emit_loadk = emit_loadk,
    emit_getupval = emit_getupval,
    emit_setupval = emit_setupval,
    emit_gettabup = emit_gettabup,
    emit_settabup = emit_settabup,
    emit_gettable = emit_gettable,
    emit_settable = emit_settable,
    emit_getfield = emit_getfield,
    emit_setfield = emit_setfield,
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
    emit_closure = emit_closure,
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
    patch_jump_to_pc = patch_jump_to_pc,
    emit_jump_to_pc = emit_jump_to_pc,
    emit_forprep_placeholder = emit_forprep_placeholder,
    emit_forloop_patch = emit_forloop_patch,
    emit_return1 = emit_return1,
    emit_return_n = emit_return_n,
    add_local = add_local,
    same_name = same_name,
    resolve_local = resolve_local,
    close_func_builder = close_func_builder,
}
