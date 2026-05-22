-- Moonlift VM — Arithmetic, bitwise, unary, MMBIN, and NOT opcode handlers.
--
-- This module is intentionally explicit.  Earlier versions generated these
-- handlers by substituting expression strings into Moonlift source templates;
-- that hid opcode semantics and kept hot Value accesses in aggregate-copy form.
-- The handlers below read/write Value fields through pointers in the hot path.

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_add = R([[
region op_add(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    let lt: u32 = lhs.tag
    let rt: u32 = rhs.tag
    let lb: u64 = lhs.bits
    let rb: u64 = rhs.bits
    let dst: index = base + as(index, a)
    if lt == @{TAG_INTEGER} and rt == @{TAG_INTEGER} then
        L.stack[dst].tag = @{TAG_INTEGER}
        L.stack[dst].aux = 0
        L.stack[dst].bits = as(u64, as(i64, lb) + as(i64, rb))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lt == @{TAG_NUM} and rt == @{TAG_NUM} then
        L.stack[dst].tag = @{TAG_NUM}
        L.stack[dst].aux = 0
        L.stack[dst].bits = bitcast(u64, bitcast(f64, lb) + bitcast(f64, rb))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_sub = R([[
region op_sub(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) - as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) - bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_mul = R([[
region op_mul(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) * as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) * bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_div = R([[
region op_div(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) / bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_mod = R([[
region op_mod(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_idiv = R([[
region op_idiv(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_pow = R([[
region op_pow(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_band = R([[
region op_band(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) & as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_bor = R([[
region op_bor(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) | as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_bxor = R([[
region op_bxor(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        let x: i64 = as(i64, lhs.bits)
        let y: i64 = as(i64, rhs.bits)
        let r: i64 = x ~ y
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_shl = R([[
region op_shl(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) << as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_shr = R([[
region op_shr(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = L.stack + (base + as(index, c))
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) >> as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_addi = R([[
region op_addi(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    if lhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) + as(i64, as(i32, c))) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) + as(f64, as(i64, as(i32, c)))) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_shli = R([[
region op_shli(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    if lhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, as(i32, c)) << as(i64, lhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_shri = R([[
region op_shri(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    if lhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) >> as(i64, as(i32, c))) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_addk = R([[
region op_addk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) + as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) + bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_subk = R([[
region op_subk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) - as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) - bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_mulk = R([[
region op_mulk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) * as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) * bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_divk = R([[
region op_divk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, bitcast(f64, lhs.bits) / bitcast(f64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_modk = R([[
region op_modk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_powk = R([[
region op_powk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_idivk = R([[
region op_idivk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    jump error(code = @{ERR_ARITH})
end
end
]])

local op_bandk = R([[
region op_bandk(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) & as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_bork = R([[
region op_bork(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, lhs.bits) | as(i64, rhs.bits)) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_bxork = R([[
region op_bxork(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let lhs: ptr(Value) = L.stack + (base + as(index, b))
    let rhs: ptr(Value) = cl.proto.constants + as(index, c)
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        let x: i64 = as(i64, lhs.bits)
        let y: i64 = as(i64, rhs.bits)
        let r: i64 = x ~ y
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_unm = R([[
region op_unm(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let src: ptr(Value) = L.stack + (base + as(index, b))
    if src.tag == @{TAG_INTEGER} then
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, -(as(i64, src.bits))) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if src.tag == @{TAG_NUM} then
        L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = bitcast(u64, -(bitcast(f64, src.bits))) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_bnot = R([[
region op_bnot(]] .. H .. [[;]] .. B.ARITH_CONT .. [[)
entry start()
    let src: ptr(Value) = L.stack + (base + as(index, b))
    if src.tag == @{TAG_INTEGER} then
        let x: i64 = as(i64, src.bits)
        let r: i64 = ~x
        L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, r) }
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_not = R([[
region op_not(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let src: ptr(Value) = L.stack + (base + as(index, b))
    if src.tag == @{TAG_NIL} or src.tag == @{TAG_FALSE} then
        L.stack[base + as(index, a)] = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    else
        L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_mmbin = R([[
region op_mmbin(]] .. H .. [[;
                ]] .. B.MMBIN_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_mmbini = R([[
region op_mmbini(]] .. H .. [[;
                 ]] .. B.MMBIN_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_mmbink = R([[
region op_mmbink(]] .. H .. [[;
                 ]] .. B.MMBIN_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

return {
    op_add = op_add, op_sub = op_sub, op_mul = op_mul,
    op_mod = op_mod, op_idiv = op_idiv, op_pow = op_pow, op_div = op_div,
    op_band = op_band, op_bor = op_bor, op_bxor = op_bxor, op_shl = op_shl, op_shr = op_shr,
    op_addi = op_addi, op_shli = op_shli, op_shri = op_shri,
    op_addk = op_addk, op_subk = op_subk, op_mulk = op_mulk, op_modk = op_modk,
    op_powk = op_powk, op_divk = op_divk, op_idivk = op_idivk,
    op_bandk = op_bandk, op_bork = op_bork, op_bxork = op_bxork,
    op_unm = op_unm, op_bnot = op_bnot, op_not = op_not,
    op_mmbin = op_mmbin, op_mmbini = op_mmbini, op_mmbink = op_mmbink,
}
