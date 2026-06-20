-- ir_lower.lua — Moonlift → LuaJIT IR lowering (hack v1, fixed buffer)

local pvm = require("moonlift.pvm")
local M = {}

-- LuaJIT IR opcodes
local IROP = {
    BASE=13, LOOP=17, PHI=19,
    KINT=23, KNUM=28, KINT64=29,
    BAND=33, BOR=34, BXOR=35, BSHL=36, BSHR=37, BSAR=38,
    ADD=39, SUB=40, MUL=41, NEG=45,
    LT=0, GE=1, LE=2, GT=3, EQ=8, NE=9,
    SLOAD=69, XLOAD=68, XSTORE=74, FLOAD=67, FSTORE=73,
    CONV=78, CALLN=82,
}

-- IR types (mirrors lj_ir.h IRTDEF)
local IRT = {
    NIL=0, PTR=0, INT=19, U32=20, I64=21, U64=22,
    NUM=14, FLOAT=13,
    I8=15, U8=16, I16=17, U16=18,
    STR=4, TAB=11, FUNC=8,
    -- 64-bit native
}
-- Default to I64 for pointer on 64-bit platforms
IRT.PTR = IRT.I64

-- ── IR buffer ──────────────────────────────────────────────────────────────
-- The IR buffer is a plain Lua array (1-indexed). Constants go first and
-- grow up from index 1. Instructions follow. REF_BIAS separates them.
-- In LuaJIT, REF_BIAS = 0x8000 and constants have refs < REF_BIAS while
-- instructions have refs >= REF_BIAS. Here we just track sequential indices
-- and bias at dump time.

local function buf_new()
    return {
        a    = {},    -- flat array: [consts...][instructions...]
        nk   = 0,     -- number of constants emitted
        ni   = 0,     -- number of instructions emitted
        ks   = {},    -- constants { o, t, op1, op2, i }
        is_   = {},   -- instructions { o, t, op1, op2, i }
    }
end

local function make_ir(o, t, op1, op2, aux)
    return { o = o, t = t, op1 = op1 or 0, op2 = op2 or 0, i = aux or 0 }
end

-- Emit a constant, return its local index (biased for SSA refs)
local function emit_k(buf, o, t, val)
    buf.nk = buf.nk + 1
    local ins = make_ir(o, t, 0, 0, val)
    buf.ks[buf.nk] = ins
    return buf.nk - 1  -- 0-based constant index
end

local function emit_kint(buf, val)
    return emit_k(buf, IROP.KINT, IRT.INT, val)
end

-- Emit an instruction, return its SSA ref (biased: > buf.nk so constants < instructions)
local function emit_i(buf, o, t, op1, op2, aux)
    buf.ni = buf.ni + 1
    local ins = make_ir(o, t, op1, op2, aux)
    buf.is_[buf.ni] = ins
    return buf.nk + buf.ni - 1  -- 0-based index (constants + insns)
end

-- ── Type helpers ──────────────────────────────────────────────────────────

local function scalar_to_irt(s)
    local sn = tostring(s)
    if sn:find("I8$")  then return IRT.I8  end
    if sn:find("U8$")  then return IRT.U8  end
    if sn:find("I16$") then return IRT.I16 end
    if sn:find("U16$") then return IRT.U16 end
    if sn:find("I32$") then return IRT.INT end
    if sn:find("U32$") then return IRT.U32 end
    if sn:find("I64$") then return IRT.I64 end
    if sn:find("U64$") then return IRT.U64 end
    if sn:find("F32$") then return IRT.FLOAT end
    if sn:find("F64$") then return IRT.NUM end
    if sn:find("Bool$") then return IRT.INT end
    if sn:find("Index$") or sn:find("RawPtr$") then return IRT.PTR end
    return IRT.PTR
end

local function moon_type_to_irt(T, ty)
    local Ty = T.MoonType; local cls = pvm.classof(ty)
    if cls == Ty.TScalar then return scalar_to_irt(ty.scalar) end
    if cls == Ty.TPtr or cls == Ty.TView then return IRT.PTR end
    if cls == Ty.TAccess then return moon_type_to_irt(T, ty.base) end
    return IRT.PTR
end

-- ── Op mappings ────────────────────────────────────────────────────────────

local function binop_to_ir(op_node)
    local nm = tostring(pvm.classof(op_node))
    if nm:find("BinAdd") then return IROP.ADD end
    if nm:find("BinSub") then return IROP.SUB end
    if nm:find("BinMul") then return IROP.MUL end
    if nm:find("BinBitAnd") then return IROP.BAND end
    if nm:find("BinBitOr")  then return IROP.BOR  end
    if nm:find("BinBitXor") then return IROP.BXOR end
    if nm:find("BinShl")    then return IROP.BSHL end
    if nm:find("BinLShr")   then return IROP.BSHR end
    if nm:find("BinAShr")   then return IROP.BSAR end
end

local function cmp_to_ir(op_node)
    local nm = tostring(pvm.classof(op_node))
    if nm:find("CmpEq") then return IROP.EQ end
    if nm:find("CmpNe") then return IROP.NE end
    if nm:find("CmpLt") then return IROP.LT end
    if nm:find("CmpLe") then return IROP.LE end
    if nm:find("CmpGt") then return IROP.GT end
    if nm:find("CmpGe") then return IROP.GE end
end

-- ── Expression lowering ───────────────────────────────────────────────────

local function lower_expr(buf, expr, ctx, T)
    local Tr = T.MoonTree; local B = T.MoonBind; local cls = pvm.classof(expr)

    if cls == Tr.ExprLit then
        local lit = expr.lit
        if lit then
            local lcls = pvm.classof(lit); local lk = lcls and lcls.kind
            if lk == "LitInt" then
                local v = tonumber(lit.raw or "0") or 0
                return emit_kint(buf, v), IRT.INT
            elseif lk == "LitBool" then
                return emit_kint(buf, lit.value and 1 or 0), IRT.INT
            elseif lk == "LitFloat" then
                return emit_kint(buf, 0), IRT.NUM
            elseif lk == "LitNil" then
                return emit_kint(buf, 0), IRT.NIL
            end
        end
        return emit_kint(buf, 0), IRT.INT
    end

    if cls == Tr.ExprRef then
        local ref = expr.ref
        if ref then
            local rcls = pvm.classof(ref)
            if rcls == B.ValueRefName then
                local r = ctx.refs[ref.name]
                if r then return r, IRT.INT end
            elseif rcls == B.ValueRefBinding then
                local nm = ref.binding and ref.binding.name
                if nm then local r = ctx.refs[nm]; if r then return r, IRT.INT end end
            end
        end
        return emit_kint(buf, 0), IRT.INT
    end

    if cls == Tr.ExprBinary then
        local lref, lirt = lower_expr(buf, expr.lhs, ctx, T)
        local rref, rirt = lower_expr(buf, expr.rhs, ctx, T)
        local op = binop_to_ir(expr.op)
        if op then
            local ref = emit_i(buf, op, lirt, lref, rref, 0)
            return ref, lirt
        end
        return lref, lirt
    end

    if cls == Tr.ExprCompare then
        local lref, lirt = lower_expr(buf, expr.lhs, ctx, T)
        local rref, rirt = lower_expr(buf, expr.rhs, ctx, T)
        local op = cmp_to_ir(expr.op)
        if op then
            local ref = emit_i(buf, op, lirt, lref, rref, 0)
            return ref, lirt
        end
        return lref, lirt
    end

    if cls == Tr.ExprUnary then
        local vref, virt = lower_expr(buf, expr.value, ctx, T)
        local ref = emit_i(buf, IROP.NEG, virt, vref, 0, 0)
        return ref, virt
    end

    if cls == Tr.ExprCast then
        local vref, _ = lower_expr(buf, expr.value, ctx, T)
        local tgt = moon_type_to_irt(T, expr.ty)
        local ref = emit_i(buf, IROP.CONV, tgt, vref, 0, 0)
        return ref, tgt
    end

    return emit_kint(buf, 0), IRT.INT
end

-- ── Statement lowering ────────────────────────────────────────────────────

local function lower_stmt(buf, stmt, ctx, T)
    local Tr = T.MoonTree; local cls = pvm.classof(stmt)

    if cls == Tr.StmtLet then
        local nm = stmt.binding and stmt.binding.name
        local ref, _ = lower_expr(buf, stmt.init, ctx, T)
        if nm then ctx.refs[nm] = ref end
        return
    end
    if cls == Tr.StmtVar then
        local nm = stmt.binding and stmt.binding.name
        local ref, _ = lower_expr(buf, stmt.init, ctx, T)
        if nm then ctx.refs[nm] = ref end
        return
    end
    if cls == Tr.StmtReturnValue then
        local ref, _ = lower_expr(buf, stmt.value, ctx, T)
        return { kind = "return", ref = ref }
    end
    if cls == Tr.StmtReturnVoid then
        return { kind = "return_void" }
    end
    if cls == Tr.StmtExpr then
        lower_expr(buf, stmt.expr, ctx, T)
        return
    end
    if cls == Tr.StmtIf then
        local cref, _ = lower_expr(buf, stmt.cond, ctx, T)
        -- NE cond, 0 → guard
        local kzero = emit_kint(buf, 0)
        local guard = emit_i(buf, IROP.NE, IRT.INT, cref, kzero, 0)
        -- then-body
        for _, s in ipairs(stmt.then_body) do lower_stmt(buf, s, ctx, T) end
        -- else body — TODO: as side trace
        for _, s in ipairs(stmt.else_body or {}) do lower_stmt(buf, s, ctx, T) end
        return
    end
end

-- ── Function lowering ─────────────────────────────────────────────────────

function M.lower_func(T, func)
    local buf = buf_new()
    local ctx = { refs = {} }

    -- BASE
    local parent = emit_kint(buf, 0)
    local fsize  = emit_kint(buf, 0)
    emit_i(buf, IROP.BASE, IRT.PTR, parent, fsize, 0)

    -- Parameters as SLOAD
    for i, param in ipairs(func.params) do
        local irt = moon_type_to_irt(T, param.ty)
        local slot  = emit_kint(buf, i - 1)
        local flags = emit_kint(buf, 0x1c)  -- TYPECHECK | CONVERT | READONLY
        local sload = emit_i(buf, IROP.SLOAD, irt, slot, flags, 0)
        ctx.refs[param.name] = sload
    end

    -- Lower body
    for _, stmt in ipairs(func.body) do
        lower_stmt(buf, stmt, ctx, T)
    end

    -- LOOP terminator
    emit_i(buf, IROP.LOOP, IRT.NIL, 0, 0, 0)

    return buf
end

-- ── Dump ──────────────────────────────────────────────────────────────────

local IROP_NAMES = {}; for k,v in pairs(IROP) do IROP_NAMES[v] = k end
local IRT_NAMES  = {}; for k,v in pairs(IRT)  do IRT_NAMES[v]  = k end

function M.dump(buf)
    local l = { "---- TRACE ----" }
    local fmt = "%04x %-3s %-6s %-4s  %04x  %04x  ; %d"
    for i = 1, buf.nk do
        local ins = buf.ks[i]
        local op = IROP_NAMES[ins.o] or ("?%d"):format(ins.o)
        local tp = IRT_NAMES[ins.t]  or ("?%d"):format(ins.t)
        l[#l+1] = fmt:format(i-1, "K", op, tp, ins.op1, ins.op2, ins.i)
    end
    for i = 1, buf.ni do
        local ins = buf.is_[i]
        local op = IROP_NAMES[ins.o] or ("?%d"):format(ins.o)
        local tp = IRT_NAMES[ins.t]  or ("?%d"):format(ins.t)
        local idx = buf.nk + i - 1
        l[#l+1] = fmt:format(idx, " ", op, tp, ins.op1, ins.op2, ins.i)
    end
    return table.concat(l, "\n")
end

return M
