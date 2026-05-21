-- Lua Interpreter VM — Opcode handler regions
-- All 38 Lua 5.1 opcode handler bodies.
-- Uses shared values table `ALL` so every @{} splice is available everywhere.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

-- Build shared values table with ALL constants
local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end
-- Shared values table: every constant available in every region
local ALL = {}
for k, v in pairs(I) do ALL[k] = v end

-- Helper: create a region with shared values.
-- Use host.region directly. Regions that don't use @{} splices
-- call host.region(src). Regions that use splices pass ALL explicitly.
-- This helper handles the case where src has @{} references.
-- ALL unused extra keys are simply ignored.
-- The signature closure pattern (ALL)(src) parses src as a body,
-- so we DON'T use that. We use host.region(src) which parses a full
-- region declaration. For splices, we wrap the region call.
local function R(src)
    -- Check if src uses @{} splices
    if src:match("@%{") then
        -- Use values binder: create a fresh call for this region
        local sig = host.region(ALL)
        return sig(src)
    else
        -- Use host.region directly without values table
        return host.region(src)
    end
end

-- op_move: copy register R(A) = R(B)
local op_move = R [[
region op_move(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

-- op_loadk: load constant R(A) = K(Bx)
local op_loadk = R [[
region op_loadk(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    L.stack[base + as(index, a)] = cl.proto.constants[bx]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

-- op_loadbool: load boolean R(A) = (B != 0), skip next if C != 0
local op_loadbool = R [[
region op_loadbool(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    var val: Value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    if b ~= 0 then
        val = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    else
        val = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    end
    L.stack[base + as(index, a)] = val
    if c ~= 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

-- op_loadnil: set R(A) through R(B) to nil
local op_loadnil = R [[
region op_loadnil(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let nv: Value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    let first: index = base + as(index, a)
    let last: index = base + as(index, b)
    var i: index = first
    jump loop()
end
block loop()
    if i > last then jump next(frame = frame, pc = pc + 1, base = base, top = top) end
    L.stack[i] = nv
    i = i + 1
    jump loop()
end
end
]]

-- op_getupval: R(A) = UpValue[B]
local op_getupval = R [[
region op_getupval(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    L.stack[base + as(index, a)] = *uv.v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

-- op_getglobal: R(A) = G[K(Bx)]
local op_getglobal = R [[
region op_getglobal(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                    enter_lua: cont(child: ptr(Frame)),
                    enter_native: cont(cl: ptr(CClosure)),
                    yielded: cont(nres: i32),
                    error: cont(code: i32),
                    oom: cont())
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let env: ptr(Table) = cl.env
    let key: Value = cl.proto.constants[bx]
    let env_val: Value = { tag = @{TAG_TABLE}, aux = 0, bits = as(u64, env) }
    frame.pc = pc
    L.top = top
    emit table_get(L, env_val, key;
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
block do_mm(mm: Value, self: Value, key: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    emit prepare_call(L, base, 2, 1, @{RESUME_GETTABLE_MM};
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
block out_of_mem()
    jump oom()
end
end
]]

-- Remaining opcodes follow the same pattern. Using shared ALL table.

local op_gettable = R [[
region op_gettable(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   enter_lua: cont(child: ptr(Frame)),
                   enter_native: cont(cl: ptr(CClosure)),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
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
block do_mm(mm: Value, self: Value, key: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    emit prepare_call(L, base, 2, 1, @{RESUME_GETTABLE_MM};
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
block out_of_mem()
    jump oom()
end
end
]]

local op_setglobal = R [[
region op_setglobal(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                    enter_lua: cont(child: ptr(Frame)),
                    enter_native: cont(cl: ptr(CClosure)),
                    yielded: cont(nres: i32),
                    error: cont(code: i32),
                    oom: cont())
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let env_val: Value = { tag = @{TAG_TABLE}, aux = 0, bits = as(u64, cl.env) }
    let key: Value = cl.proto.constants[bx]
    let val: Value = L.stack[base + as(index, a)]
    frame.pc = pc
    L.top = top
    emit table_set(L, env_val, key, val;
        stored = did_store,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block did_store()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value, self: Value, key: Value, value: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    L.stack[base + 3] = value
    emit prepare_call(L, base, 3, 0, @{RESUME_SETTABLE_MM};
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
block call_err(code: i32)
    jump error(code = code)
end
block type_err()
    jump error(code = @{ERR_INDEX})
end
block loop_err()
    jump error(code = @{ERR_LOOP})
end
block out_of_mem()
    jump oom()
end
end
]]

local op_setupval = R [[
region op_setupval(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    let p: ptr(Value) = uv.v
    p[0] = L.stack[base + as(index, a)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

local op_settable = R [[
region op_settable(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   enter_lua: cont(child: ptr(Frame)),
                   enter_native: cont(cl: ptr(CClosure)),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
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
block do_mm(mm: Value, self: Value, key: Value, value: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    L.stack[base + 3] = value
    emit prepare_call(L, base, 3, 0, @{RESUME_SETTABLE_MM};
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
block out_of_mem()
    jump oom()
end
end
]]

local op_newtable = R [[
region op_newtable(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   oom: cont())
entry start()
    jump oom()
end
end
]]

local op_self = R [[
region op_self(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
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
block do_mm(mm: Value, self: Value, key: Value)
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    emit prepare_call(L, base, 2, 1, @{RESUME_GETTABLE_MM};
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
block out_of_mem()
    jump oom()
end
end
]]

-- Arithmetic opcodes
local op_add = R [[
region op_add(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) + as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_sub = R [[
region op_sub(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) - as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_mul = R [[
region op_mul(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) * as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_div = R [[
region op_div(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) / as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_mod = R [[
region op_mod(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        let x: f64 = as(f64, lhs.bits) % as(f64, rhs.bits)
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_pow = R [[
region op_pow(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    -- Numeric power needs a math intrinsic/runtime helper that is not in this experiment.
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_unm = R [[
region op_unm(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              enter_lua: cont(child: ptr(Frame)),
              enter_native: cont(cl: ptr(CClosure)),
              yielded: cont(nres: i32),
              error: cont(code: i32))
entry start()
    let val: Value = L.stack[base + as(index, b)]
    if val.tag == @{TAG_NUM} then
        let x: f64 = -(as(f64, val.bits))
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, x) }
        jump next(frame = frame, pc = pc + 1, base = base, top = top)
    end
    jump error(code = @{ERR_ARITH})
end
end
]]

local op_not = R [[
region op_not(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
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
]]

local op_len = R [[
region op_len(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
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

local op_concat = R [[
region op_concat(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                 next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
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

local op_jmp = R [[
region op_jmp(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
              do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]]

local op_eq = R [[
region op_eq(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
             next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             enter_lua: cont(child: ptr(Frame)),
             enter_native: cont(cl: ptr(CClosure)),
             yielded: cont(nres: i32),
             error: cont(code: i32),
             oom: cont())
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
]]

local op_lt = R [[
region op_lt(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
             next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             enter_lua: cont(child: ptr(Frame)),
             enter_native: cont(cl: ptr(CClosure)),
             yielded: cont(nres: i32),
             error: cont(code: i32),
             oom: cont())
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
]]

local op_le = R [[
region op_le(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
             next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
             enter_lua: cont(child: ptr(Frame)),
             enter_native: cont(cl: ptr(CClosure)),
             yielded: cont(nres: i32),
             error: cont(code: i32),
             oom: cont())
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
]]

local op_test = R [[
region op_test(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, a)]
    var is_true: bool = false
    if val.tag == @{TAG_NIL} or val.tag == @{TAG_FALSE} then
        is_true = false
    else
        is_true = true
    end
    if is_true ~= (c == 0) then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

local op_testset = R [[
region op_testset(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let val: Value = L.stack[base + as(index, b)]
    var is_true: bool = false
    if val.tag == @{TAG_NIL} or val.tag == @{TAG_FALSE} then
        is_true = false
    else
        is_true = true
    end
    if is_true ~= (c == 0) then
        L.stack[base + as(index, a)] = val
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]

local op_call = R [[
region op_call(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
               enter_lua: cont(child: ptr(Frame)),
               enter_native: cont(cl: ptr(CClosure)),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
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
    emit prepare_call(L, func_slot, nargs, wanted, @{RESUME_NORMAL};
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
    let dst: index = base + as(index, a)
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
block out_of_mem()
    jump oom()
end
end
]]

local op_tailcall = R [[
region op_tailcall(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   enter_lua: cont(child: ptr(Frame)),
                   enter_native: cont(cl: ptr(CClosure)),
                   yielded: cont(nres: i32),
                   error: cont(code: i32),
                   oom: cont())
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
    emit prepare_call(L, func_slot, nargs, frame.wanted, @{RESUME_TAILCALL};
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
]]

local op_return = R [[
region op_return(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                 resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
                 finished: cont(nres: i32),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    let first: index = base + as(index, a)
    var nres: i32 = 0
    if b == 1 then
        nres = 0
    else
        if b == 0 then
            nres = as(i32, top - first)
        else
            nres = as(i32, b - 1)
        end
    end
    emit return_from_lua(L, frame, first, nres;
        resume_parent = do_resume,
        finished = all_done,
        yielded = did_yield,
        error = run_err,
        oom = out_of_mem)
end
block do_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump resume_parent(parent = parent, pc = pc, base = base, top = top)
end
block all_done(nres: i32)
    jump finished(nres = nres)
end
block did_yield(nres: i32)
    jump finished(nres = nres)
end
block run_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
]]

local op_forloop = R [[
region op_forloop(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
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
]]

local op_forprep = R [[
region op_forprep(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                  do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32))
entry start()
    let init_slot: index = base + as(index, a)
    let limit_slot: index = base + as(index, a + 1)
    let step_slot: index = base + as(index, a + 2)
    let init_val: Value = L.stack[init_slot]
    let limit_val: Value = L.stack[limit_slot]
    let step_val: Value = L.stack[step_slot]
    if init_val.tag ~= @{TAG_NUM} or limit_val.tag ~= @{TAG_NUM} or step_val.tag ~= @{TAG_NUM} then
        jump error(code = @{ERR_RUNTIME})
    end
    let prepared: f64 = as(f64, init_val.bits) - as(f64, step_val.bits)
    L.stack[init_slot] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, prepared) }
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]]

local op_tforloop = R [[
region op_tforloop(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                   do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
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

local op_setlist = R [[
region op_setlist(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  oom: cont())
entry start()
    jump oom()
end
end
]]

local op_close = R [[
region op_close(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
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
]]

local op_closure = R [[
region op_closure(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

local op_vararg = R [[
region op_vararg(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                 next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

return {
    op_move = op_move,
    op_loadk = op_loadk,
    op_loadbool = op_loadbool,
    op_loadnil = op_loadnil,
    op_getupval = op_getupval,
    op_getglobal = op_getglobal,
    op_gettable = op_gettable,
    op_setglobal = op_setglobal,
    op_setupval = op_setupval,
    op_settable = op_settable,
    op_newtable = op_newtable,
    op_self = op_self,
    op_add = op_add,
    op_sub = op_sub,
    op_mul = op_mul,
    op_div = op_div,
    op_mod = op_mod,
    op_pow = op_pow,
    op_unm = op_unm,
    op_not = op_not,
    op_len = op_len,
    op_concat = op_concat,
    op_jmp = op_jmp,
    op_eq = op_eq,
    op_lt = op_lt,
    op_le = op_le,
    op_test = op_test,
    op_testset = op_testset,
    op_call = op_call,
    op_tailcall = op_tailcall,
    op_return = op_return,
    op_forloop = op_forloop,
    op_forprep = op_forprep,
    op_tforloop = op_tforloop,
    op_vararg = op_vararg,
    op_setlist = op_setlist,
    op_close = op_close,
    op_closure = op_closure,
    op_vararg = op_vararg,
}
