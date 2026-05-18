-- BackProgram Flatline wire format encoder.
--
-- Encodes MoonBack.BackProgram into the Flatline binary format.
-- One tag per Cranelift IR operation. No sub-tag dispatch.

local ffi = require("ffi")
local bit = require("bit")

local M = {}

-- Flat tags (matches wire_tags.rs)
local T = {
    -- Structural
    CreateBlock      = 1,
    SwitchToBlock    = 2,
    AppendBlockParam = 3,
    CreateStackSlot  = 4,
    Alias            = 190,
    BoolNot          = 191,
    -- Constants
    ConstI32 = 10,  ConstI64 = 11,  ConstF32 = 12,  ConstF64 = 13,
    ConstBool= 14,  ConstNull= 15,  ConstInt = 16,
    -- Integer
    Iadd = 20,  Isub = 21,  Imul = 22,  Sdiv = 23,  Udiv = 24,
    Srem = 25,  Urem = 26,  Ineg = 27,
    -- Float
    Fadd = 30,  Fsub = 31,  Fmul = 32,  Fdiv = 33,  Fneg = 34,
    Fabs = 35,  Fma  = 36,  Sqrt = 37,  Floor = 38, Ceil = 39,
    Trunc = 40, Nearest = 41,
    -- Bitwise
    Band = 50,  Bor = 51,  Bxor = 52,  Bnot = 53,
    -- Shift / Rotate
    Ishl = 60,  Ushr = 61,  Sshr = 62,
    Rotl = 63,  Rotr = 64,
    -- Compare
    Icmp = 70,  Fcmp = 71,
    -- Cast
    Bitcast = 80,  Ireduce = 81, Sextend = 82, Uextend = 83,
    Fpromote = 84, Fdemote = 85,
    FcvtFromSint = 86, FcvtFromUint = 87, FcvtToSint = 88, FcvtToUint= 89,
    -- Intrinsics
    Popcnt = 90, Clz = 91, Ctz = 92, Bswap = 93, Iabs = 94,
    -- Address
    StackAddr = 100, GlobalValue = 101, FuncAddr = 102, ExternAddr = 103,
    -- Memory
    Load = 110, Store = 111,
    AtomicLoad = 112, AtomicStore = 113, AtomicRmw = 114, AtomicCas = 115,
    Fence = 116,
    Memcpy = 117, Memset = 118,
    -- Pointer
    PtrAdd = 120, PtrOffset = 121,
    -- Vector
    Splat = 130, InsertLane = 131, ExtractLane = 132,
    VecIadd = 133, VecIsub = 134, VecImul = 135,
    VecBand = 136, VecBor = 137, VecBxor = 138,
    VecIcmpEq = 139, VecIcmpNe = 140,
    VecSIcmpLt = 141, VecSIcmpLe = 142,
    VecSIcmpGt = 143, VecSIcmpGe = 144,
    VecUIcmpLt = 145, VecUIcmpLe = 146,
    VecUIcmpGt = 147, VecUIcmpGe = 148,
    VecSelect = 149,
    VecMaskNot = 150, VecMaskAnd = 151, VecMaskOr = 152,
    VecLoad = 153, VecStore = 154,
    -- Select
    Select = 160,
    -- Control
    Jump = 170, Brif = 171, SwitchInt = 172,
    ReturnVoid = 173, ReturnValue = 174, Trap = 175,
    -- Call
    CallDirect = 180, CallExtern = 181, CallIndirect = 182,
}

local function id(node) return type(node) == "string" and node or node.text end

-- Scalar tags 1-13
local S = { BackBool=1, BackI8=2, BackI16=3, BackI32=4, BackI64=5,
    BackU8=6, BackU16=7, BackU32=8, BackU64=9, BackF32=10,
    BackF64=11, BackPtr=12, BackIndex=13 }

local function st(s)
    if s.kind == "BackShapeScalar" then
        return assert(S[s.scalar.kind], "bad scalar "..tostring(s.scalar.kind))
    elseif s.kind == "BackShapeVec" then
        return assert(S[s.vec.elem.kind], "bad vec elem "..tostring(s.vec.elem.kind))
    end
    return assert(S[s.kind], "bad scalar "..tostring(s.kind))
end

-- Helper: write 4 bytes LE
local function w4(buf, v)
    buf[#buf+1] = string.char(
        bit.band(v, 0xff), bit.band(bit.rshift(v, 8), 0xff),
        bit.band(bit.rshift(v, 16), 0xff), bit.band(bit.rshift(v, 24), 0xff))
end

-- MemFlags: bit0=notrap, bit1=aligned, bit2=can_move
local function memflags(m)
    local bits = 0
    if m.trap.kind == "BackNonTrapping" or m.trap.kind == "BackChecked" then
        bits = bit.bor(bits, 1)
    end
    if (m.alignment.kind == "BackAlignKnown" or m.alignment.kind == "BackAlignAtLeast")
       and m.alignment.bytes >= 4 then
        bits = bit.bor(bits, 2)
    end
    if m.motion.kind == "BackCanMove" then
        bits = bit.bor(bits, 4)
    end
    return bits
end

-- Text ID → numeric.  Assigns fresh u32s.
local function renumber(bodies)
    for _, b in ipairs(bodies) do
        local nid = 0
        local map = {}
        b.map = map
        b.nid = function(self, x)
            if type(x) == "number" then return x end
            local s = type(x) == "string" and x or x.text
            if map[s] == nil then map[s] = nid; nid = nid + 1 end
            return map[s]
        end
    end
end

local function u64_split(raw)
    local r = raw % 4294967296.0
    local lo = bit.band(r < 0 and r + 4294967296 or r, 0xFFFFFFFF)
    local hi = math.floor(raw / 4294967296.0)
    return lo, hi
end
local function emit_ids(buf, list, b)
    w4(buf, #list)
    for _, x in ipairs(list) do w4(buf, b:nid(x)) end
end

-- Encode one function body into a byte buffer
local function encode_body(cmds, b)
    local buf = {}
    local addr_counter = 0
    local function fresh_id()
        local s = "__a" .. tostring(addr_counter)
        addr_counter = addr_counter + 1
        return s
    end
    for _, cmd in ipairs(cmds) do
        local k = cmd.kind

        -- Structural: keep as-is
        if k == "CmdCreateBlock" then
            w4(buf, T.CreateBlock); w4(buf, b:nid(cmd.block))
        elseif k == "CmdSwitchToBlock" then
            w4(buf, T.SwitchToBlock); w4(buf, b:nid(cmd.block))
        elseif k == "CmdAppendBlockParam" then
            w4(buf, T.AppendBlockParam); w4(buf, b:nid(cmd.block)); w4(buf, st(cmd.ty))
        elseif k == "CmdCreateStackSlot" then
            w4(buf, T.CreateStackSlot); w4(buf, b:nid(cmd.slot)); w4(buf, cmd.size); w4(buf, cmd.align or 0)
        elseif k == "CmdSealBlock" or k == "CmdBindEntryParams" then
            -- BindEntryParams: emit AppendBlockParam for each param
            if k == "CmdBindEntryParams" and b.sig then
                for idx, p in ipairs(b.sig.params) do
                    local val = cmd.values[idx]
                    w4(buf, T.AppendBlockParam)
                    w4(buf, b:nid(cmd.block))
                    w4(buf, st(p))
                    w4(buf, b:nid(val))
                end
            end
        elseif k == "CmdAlias" then
            -- Emit as Alias tag (decoder just does HashMap insert)
            w4(buf, T.Alias); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.src))

        -- Address commands
        elseif k == "CmdStackAddr" then
            w4(buf, T.StackAddr); w4(buf, b:nid(cmd.dst)); w4(buf, 12); w4(buf, b:nid(cmd.slot))
        elseif k == "CmdDataAddr" then
            w4(buf, T.GlobalValue); w4(buf, b:nid(cmd.dst)); w4(buf, 12); w4(buf, (b.data_map or {})[id(cmd.data)] or 0)
        elseif k == "CmdFuncAddr" then
            w4(buf, T.FuncAddr); w4(buf, b:nid(cmd.dst)); w4(buf, 12); w4(buf, (b.func_map or {})[id(cmd.func)] or 0)
        elseif k == "CmdExternAddr" then
            w4(buf, T.ExternAddr); w4(buf, b:nid(cmd.dst)); w4(buf, 12); w4(buf, (b.extern_map or {})[id(cmd.func)] or 0)

        -- Constants
        elseif k == "CmdConst" then
            local v = cmd.value
            if v.kind == "BackLitNull" then
                w4(buf, T.ConstNull); w4(buf, b:nid(cmd.dst))
            elseif v.kind == "BackLitBool" then
                w4(buf, T.ConstBool); w4(buf, b:nid(cmd.dst)); w4(buf, v.value and 1 or 0)
            elseif v.kind == "BackLitInt" then
                local raw = tonumber(v.raw) or 0
                local ty = st(cmd.ty)
                if ty == 4 then -- I32
                    w4(buf, T.ConstI32); w4(buf, b:nid(cmd.dst)); w4(buf, bit.band(raw, 0xFFFFFFFF))
                elseif ty == 5 then -- I64
                    local lo, hi = u64_split(raw)
                w4(buf, T.ConstI64); w4(buf, b:nid(cmd.dst))
                w4(buf, lo); w4(buf, hi)
                else
                w4(buf, T.ConstInt); w4(buf, b:nid(cmd.dst)); w4(buf, ty)
                    local lo, hi = u64_split(raw)
                    w4(buf, lo); w4(buf, hi)
                end
            elseif v.kind == "BackLitFloat" then
                local bits = ffi.new("union { double d; uint32_t w[2]; }")
                bits.d = tonumber(v.raw) or 0.0
                if tonumber(bits.w[1]) == 0 then
                    w4(buf, T.ConstF32); w4(buf, b:nid(cmd.dst)); w4(buf, tonumber(bits.w[0]))
                else
                    w4(buf, T.ConstF64); w4(buf, b:nid(cmd.dst))
                    w4(buf, tonumber(bits.w[0])); w4(buf, tonumber(bits.w[1]))
                end
            end

        -- Integer binary
        elseif k == "CmdIntBinary" then
            local op = cmd.op
            local ok = op.kind or op  -- might be a string or table
            if ok == "BackIntAdd" then w4(buf, T.Iadd)
            elseif ok == "BackIntSub" then w4(buf, T.Isub)
            elseif ok == "BackIntMul" then w4(buf, T.Imul)
            elseif ok == "BackIntSDiv" then w4(buf, T.Sdiv)
            elseif ok == "BackIntUDiv" then w4(buf, T.Udiv)
            elseif ok == "BackIntSRem" then w4(buf, T.Srem)
            elseif ok == "BackIntURem" then w4(buf, T.Urem)
            else w4(buf, T.Iadd) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Float binary
        elseif k == "CmdFloatBinary" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackFloatAdd" then w4(buf, T.Fadd)
            elseif ok == "BackFloatSub" then w4(buf, T.Fsub)
            elseif ok == "BackFloatMul" then w4(buf, T.Fmul)
            elseif ok == "BackFloatDiv" then w4(buf, T.Fdiv)
            else w4(buf, T.Fadd) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Bit binary
        elseif k == "CmdBitBinary" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackBitAnd" then w4(buf, T.Band)
            elseif ok == "BackBitOr" then w4(buf, T.Bor)
            elseif ok == "BackBitXor" then w4(buf, T.Bxor)
            else w4(buf, T.Band) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- BitNot
        elseif k == "CmdBitNot" then
            w4(buf, T.Bnot); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.value))

        -- Shift
        elseif k == "CmdShift" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackShiftLeft" then w4(buf, T.Ishl)
            elseif ok == "BackShiftLogicalRight" then w4(buf, T.Ushr)
            elseif ok == "BackShiftArithmeticRight" then w4(buf, T.Sshr)
            else w4(buf, T.Ishl) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Compare
        elseif k == "CmdCompare" then
            local ok = cmd.op.kind or cmd.op
            local is_float = ok:match("^BackFCmp")
            if is_float then w4(buf, T.Fcmp) else w4(buf, T.Icmp) end
            w4(buf, b:nid(cmd.dst))
            local cc = 0
            if ok == "BackIcmpEq" then cc = 1 elseif ok == "BackIcmpNe" then cc = 2
            elseif ok == "BackSIcmpLt" then cc = 3 elseif ok == "BackSIcmpLe" then cc = 4
            elseif ok == "BackSIcmpGt" then cc = 5 elseif ok == "BackSIcmpGe" then cc = 6
            elseif ok == "BackUIcmpLt" then cc = 7 elseif ok == "BackUIcmpLe" then cc = 8
            elseif ok == "BackUIcmpGt" then cc = 9 elseif ok == "BackUIcmpGe" then cc = 10
            elseif ok == "BackFCmpEq" then cc = 1 elseif ok == "BackFCmpNe" then cc = 2
            elseif ok == "BackFCmpLt" then cc = 3 elseif ok == "BackFCmpLe" then cc = 4
            elseif ok == "BackFCmpGt" then cc = 5 elseif ok == "BackFCmpGe" then cc = 6 end
            w4(buf, cc); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Cast
        elseif k == "CmdCast" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackBitcast" then w4(buf, T.Bitcast)
            elseif ok == "BackIreduce" then w4(buf, T.Ireduce)
            elseif ok == "BackSextend" then w4(buf, T.Sextend)
            elseif ok == "BackUextend" then w4(buf, T.Uextend)
            elseif ok == "BackFpromote" then w4(buf, T.Fpromote)
            elseif ok == "BackFdemote" then w4(buf, T.Fdemote)
            elseif ok == "BackSToF" then w4(buf, T.FcvtFromSint)
            elseif ok == "BackUToF" then w4(buf, T.FcvtFromUint)
            elseif ok == "BackFToS" then w4(buf, T.FcvtToSint)
            elseif ok == "BackFToU" then w4(buf, T.FcvtToUint)
            else w4(buf, T.Bitcast) end
            w4(buf, b:nid(cmd.dst)); w4(buf, st(cmd.ty)); w4(buf, b:nid(cmd.value))

        -- Memory
        elseif k == "CmdLoadInfo" then
            local base = cmd.addr.base
            local is_vec = cmd.ty.kind ~= "BackShapeScalar"
            local elem_st, lanes, mem
            if is_vec then
                elem_st = st(cmd.ty.vec.elem)
                lanes = cmd.ty.vec.lanes
                mem = memflags(cmd.memory)
            else
                elem_st = st(cmd.ty.scalar)
                lanes = 0
                mem = memflags(cmd.memory)
            end
            -- Emit address computation for non-value bases
            local addr_id
            if base.kind == "BackAddrValue" then
                addr_id = base.value
            elseif base.kind == "BackAddrStack" then
                local at = fresh_id()
                w4(buf, T.StackAddr); w4(buf, b:nid(at)); w4(buf, 12); w4(buf, b:nid(base.slot))
                addr_id = at
            else
                local at = fresh_id()
                w4(buf, T.GlobalValue); w4(buf, b:nid(at)); w4(buf, 12); w4(buf, b:nid(base.data))
                addr_id = at
            end
            if is_vec then
                w4(buf, T.VecLoad); w4(buf, b:nid(cmd.dst))
                w4(buf, elem_st); w4(buf, lanes); w4(buf, mem); w4(buf, b:nid(addr_id))
            else
                w4(buf, T.Load); w4(buf, b:nid(cmd.dst))
                w4(buf, elem_st); w4(buf, mem); w4(buf, b:nid(addr_id))
            end
        elseif k == "CmdStoreInfo" then
            local is_vec = cmd.ty.kind ~= "BackShapeScalar"
            local base = cmd.addr.base
            -- Emit address computation for non-value bases
            local addr_id
            if base.kind == "BackAddrValue" then
                addr_id = base.value
            elseif base.kind == "BackAddrStack" then
                local at = fresh_id()
                w4(buf, T.StackAddr); w4(buf, b:nid(at)); w4(buf, 12); w4(buf, b:nid(base.slot))
                addr_id = at
            else
                local at = fresh_id()
                w4(buf, T.GlobalValue); w4(buf, b:nid(at)); w4(buf, 12); w4(buf, b:nid(base.data))
                addr_id = at
            end
            if is_vec then
                w4(buf, T.VecStore); w4(buf, st(cmd.ty.vec.elem)); w4(buf, cmd.ty.vec.lanes)
                w4(buf, memflags(cmd.memory)); w4(buf, b:nid(addr_id)); w4(buf, b:nid(cmd.value))
            else
                w4(buf, T.Store); w4(buf, st(cmd.ty.scalar)); w4(buf, memflags(cmd.memory))
                w4(buf, b:nid(addr_id)); w4(buf, b:nid(cmd.value))
            end

        -- Unary
        elseif k == "CmdUnary" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackUnaryIneg" then w4(buf, T.Ineg)
            elseif ok == "BackUnaryFneg" then w4(buf, T.Fneg)
            elseif ok == "BackUnaryBnot" then w4(buf, T.Bnot)
            elseif ok == "BackUnaryBoolNot" then w4(buf, T.BoolNot) -- composite: icmp + bfc
            else w4(buf, T.Ineg) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.value))

        -- Intrinsic
        elseif k == "CmdIntrinsic" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackIntrinsicPopcnt" then w4(buf, T.Popcnt)
            elseif ok == "BackIntrinsicClz" then w4(buf, T.Clz)
            elseif ok == "BackIntrinsicCtz" then w4(buf, T.Ctz)
            elseif ok == "BackIntrinsicBswap" then w4(buf, T.Bswap)
            elseif ok == "BackIntrinsicSqrt" then w4(buf, T.Sqrt)
            elseif ok == "BackIntrinsicAbs" then w4(buf, T.Iabs)
            elseif ok == "BackIntrinsicFloor" then w4(buf, T.Floor)
            elseif ok == "BackIntrinsicCeil" then w4(buf, T.Ceil)
            elseif ok == "BackIntrinsicTruncFloat" then w4(buf, T.Trunc)
            elseif ok == "BackIntrinsicRound" then w4(buf, T.Nearest)
            else w4(buf, T.Popcnt) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.args[1]))

        -- Memory intrinsic
        elseif k == "CmdMemcpy" then
            w4(buf, T.Memcpy); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.src)); w4(buf, b:nid(cmd.len))
        elseif k == "CmdMemset" then
            w4(buf, T.Memset); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.byte)); w4(buf, b:nid(cmd.len))

        -- Control flow
        elseif k == "CmdReturnVoid" then
            w4(buf, T.ReturnVoid)
        elseif k == "CmdReturnValue" then
            w4(buf, T.ReturnValue); w4(buf, b:nid(cmd.value))
        elseif k == "CmdTrap" then
            w4(buf, T.Trap)
        elseif k == "CmdJump" then
            w4(buf, T.Jump); w4(buf, b:nid(cmd.dest))
            emit_ids(buf, cmd.args, b)
        elseif k == "CmdBrIf" then
            w4(buf, T.Brif); w4(buf, b:nid(cmd.cond)); w4(buf, b:nid(cmd.then_block))
            emit_ids(buf, cmd.then_args, b)
            w4(buf, b:nid(cmd.else_block))
            emit_ids(buf, cmd.else_args, b)
        elseif k == "CmdSwitchInt" then
            w4(buf, T.SwitchInt); w4(buf, b:nid(cmd.value)); w4(buf, st(cmd.ty)); w4(buf, #cmd.cases)
            w4(buf, b:nid(cmd.default_dest))
            for _, c in ipairs(cmd.cases) do
                local raw = tonumber(c.raw) or 0
                local lo, hi = u64_split(raw)
                w4(buf, lo); w4(buf, hi)
                w4(buf, b:nid(c.dest))
            end

        -- Select / FMA
        elseif k == "CmdSelect" then
            w4(buf, T.Select)
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.cond))
            w4(buf, b:nid(cmd.then_value)); w4(buf, b:nid(cmd.else_value))
        elseif k == "CmdFma" then
            w4(buf, T.Fma); w4(buf, b:nid(cmd.dst))
            w4(buf, b:nid(cmd.a)); w4(buf, b:nid(cmd.b)); w4(buf, b:nid(cmd.c))

        -- Vector splat
        elseif k == "CmdVecSplat" then
            w4(buf, T.Splat); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty.elem)); w4(buf, cmd.ty.lanes); w4(buf, b:nid(cmd.value))

        -- Vector insert lane
        elseif k == "CmdVecInsertLane" then
            w4(buf, T.InsertLane); w4(buf, b:nid(cmd.dst))
            w4(buf, b:nid(cmd.value)); w4(buf, b:nid(cmd.lane_value)); w4(buf, cmd.lane)

        -- Vector extract lane
        elseif k == "CmdVecExtractLane" then
            w4(buf, T.ExtractLane); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, b:nid(cmd.value)); w4(buf, cmd.lane)

        -- Vector binary (check op.kind or string)
        elseif k == "CmdVecBinary" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackVecIntAdd" then w4(buf, T.VecIadd)
            elseif ok == "BackVecIntSub" then w4(buf, T.VecIsub)
            elseif ok == "BackVecIntMul" then w4(buf, T.VecImul)
            elseif ok == "BackVecBitAnd" then w4(buf, T.VecBand)
            elseif ok == "BackVecBitOr" then w4(buf, T.VecBor)
            elseif ok == "BackVecBitXor" then w4(buf, T.VecBxor)
            else w4(buf, T.VecIadd) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Vector compare
        elseif k == "CmdVecCompare" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackVecIcmpEq" then w4(buf, T.VecIcmpEq)
            elseif ok == "BackVecIcmpNe" then w4(buf, T.VecIcmpNe)
            elseif ok == "BackVecSIcmpLt" then w4(buf, T.VecSIcmpLt)
            elseif ok == "BackVecSIcmpLe" then w4(buf, T.VecSIcmpLe)
            elseif ok == "BackVecSIcmpGt" then w4(buf, T.VecSIcmpGt)
            elseif ok == "BackVecSIcmpGe" then w4(buf, T.VecSIcmpGe)
            elseif ok == "BackVecUIcmpLt" then w4(buf, T.VecUIcmpLt)
            elseif ok == "BackVecUIcmpLe" then w4(buf, T.VecUIcmpLe)
            elseif ok == "BackVecUIcmpGt" then w4(buf, T.VecUIcmpGt)
            elseif ok == "BackVecUIcmpGe" then w4(buf, T.VecUIcmpGe)
            else w4(buf, T.VecIadd) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))

        -- Vector select
        elseif k == "CmdVecSelect" then
            w4(buf, T.VecSelect); w4(buf, b:nid(cmd.dst))
            w4(buf, b:nid(cmd.mask)); w4(buf, b:nid(cmd.then_value)); w4(buf, b:nid(cmd.else_value))

        -- Vector load
        elseif k == "CmdVecLoadInfo" then
            w4(buf, T.VecLoad); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty.elem)); w4(buf, cmd.ty.lanes)
            w4(buf, memflags(cmd.memory))
            local base = cmd.addr.base
            if base.kind == "BackAddrValue" then w4(buf, 0); w4(buf, b:nid(base.value))
            elseif base.kind == "BackAddrStack" then w4(buf, 1); w4(buf, b:nid(base.slot))
            else w4(buf, 2); w4(buf, b:nid(base.data)) end
            w4(buf, b:nid(cmd.addr.byte_offset))

        -- Vector store
        elseif k == "CmdVecStoreInfo" then
            w4(buf, T.VecStore); w4(buf, b:nid(cmd.value))
            w4(buf, st(cmd.ty.elem)); w4(buf, cmd.ty.lanes)
            w4(buf, memflags(cmd.memory))
            local base = cmd.addr.base
            if base.kind == "BackAddrValue" then w4(buf, 0); w4(buf, b:nid(base.value))
            elseif base.kind == "BackAddrStack" then w4(buf, 1); w4(buf, b:nid(base.slot))
            else w4(buf, 2); w4(buf, b:nid(base.data)) end
            w4(buf, b:nid(cmd.addr.byte_offset))

        -- Call
        elseif k == "CmdCall" then
            local res = cmd.result
            local rt = res.kind == "BackCallValue" and 1 or 0
            local tgt = cmd.target
            local tag, target_id
            if tgt.kind == "BackCallDirect" then
                tag = T.CallDirect
                target_id = b.func_map[id(tgt.func)] or 0
            elseif tgt.kind == "BackCallExtern" then
                tag = T.CallExtern
                target_id = b.func_map[id(tgt.func)] or 0
            else
                tag = T.CallIndirect
                target_id = b:nid(tgt.callee)
            end
            -- tag + 5 fixed slots: [result_tag, dst, scalar_type, target_id, sig_id]
            w4(buf, tag)
            w4(buf, rt)
            if rt == 1 then
                w4(buf, b:nid(res.dst))
                w4(buf, st(res.ty))
            else
                w4(buf, 0xFFFFFFFF)
                w4(buf, 0)
            end
            w4(buf, target_id)
            w4(buf, 0) -- sig_id placeholder
            emit_ids(buf, cmd.args, b)
        end
    end
    return table.concat(buf)
end

function M.encode(program)
    -- Collect: sigs, funcs, datas, inits, externs, body cmds per function
    local sigs = {}
    local funcs = {}
    local datas = {}
    local inits = {}
    local externs = {}
    local bodies = {}
    local current = { cmds = {}, func_id = nil, sig = nil }
    local current_sig_id = nil
    local sig_map = {}  -- func_id -> { params = [{kind}], results = [{kind}] }
    local func_sig_map = {} -- func text -> sig

    local function flush()
        if #current.cmds > 0 then
            if current.func_id then
                current.sig = func_sig_map[current.func_id]
            end
            bodies[#bodies + 1] = current
            current = { cmds = {}, func_id = nil, sig = nil }
        end
    end

    for _, cmd in ipairs(program.cmds) do
        local k = cmd.kind
        if k == "CmdCreateSig" then
            flush()
            local sid = id(cmd.sig)
            local params = {}
            for i, p in ipairs(cmd.params) do params[i] = p end
            local results = {}
            for i, r in ipairs(cmd.results) do results[i] = r end
            sig_map[sid] = { params = params, results = results }
            sigs[#sigs + 1] = cmd
        elseif k == "CmdDeclareFunc" or k == "CmdDeclareFuncExport" or k == "CmdDeclareFuncLocal" then
            flush()
            local fid = id(cmd.func)
            local sid = id(cmd.sig)
            func_sig_map[fid] = sig_map[sid]
            funcs[#funcs + 1] = cmd
        elseif k == "CmdDeclareFuncExtern" or k == "CmdDeclareExtern" then
            flush()
            externs[#externs + 1] = cmd
        elseif k == "CmdDeclareData" then
            flush()
            datas[#datas + 1] = cmd
        elseif k == "CmdDataInit" or k == "CmdDataInitZero" then
            flush()
            inits[#inits + 1] = cmd
        elseif k == "CmdBeginFunc" then
            flush()
            current.func_id = id(cmd.func)
        elseif k == "CmdFinishFunc" then
            flush()
        elseif k == "CmdFinalizeModule" then
            flush()
        elseif k == "CmdTargetModel" or k == "CmdAliasFact" then
            -- skip, no-op in Rust decoder
        else
            current.cmds[#current.cmds + 1] = cmd
        end
    end
    flush()

    renumber(bodies)

    -- Build data_id mapping (text -> wire_id)
    local data_map = {}
    for i, cmd in ipairs(datas) do
        data_map[id(cmd.data)] = i - 1
    end

    -- Build sig_id mapping (text -> index)
    local sig_idx = {}
    for i, cmd in ipairs(sigs) do
        sig_idx[id(cmd.sig)] = i - 1
    end

    -- Build func_id mapping (text -> wire_id)
    local func_map = {}
    for i, cmd in ipairs(funcs) do
        func_map[id(cmd.func)] = i - 1
    end

    -- Build extern_id mapping (text -> wire_id)
    local extern_map = {}
    for i, cmd in ipairs(externs) do
        extern_map[id(cmd.func)] = i - 1
    end

    -- Encode each body to compute lengths
    local body_data = {}
    local total_body = 0
    for i, b in ipairs(bodies) do
        b.func_map = func_map
        b.data_map = data_map
        b.extern_map = extern_map
        local bytes = encode_body(b.cmds, b)
        body_data[i] = { bytes = bytes, offset = total_body }
        total_body = total_body + #bytes
    end

    -- Build layout
    local header_size = 28  -- 7 u32
    local decl_size = 0

    -- Estimate decl size: sigs + funcs + datas + inits + externs
    decl_size = decl_size + 4 -- sig count
    for _ in ipairs(sigs) do
        decl_size = decl_size + 4 -- sig_id
        -- We'll write params inline
        decl_size = decl_size + 4 + 4 -- n_params + n_results
        -- plus param types + result types (estimate per sig)
    end

    -- We need to compute precisely. Let's build the decl section first.
    local dbuf = {}
    -- Sigs
    w4(dbuf, #sigs)
    for i, cmd in ipairs(sigs) do
        w4(dbuf, i - 1) -- sig_id
        local params = cmd.params
        w4(dbuf, #params)
        for _, p in ipairs(params) do w4(dbuf, st(p)) end
        local results = cmd.results
        w4(dbuf, #results)
        for _, r in ipairs(results) do w4(dbuf, st(r)) end
    end
    -- Build func_id mapping (text -> wire_id)
    local func_map = {}
    for i, cmd in ipairs(funcs) do
        func_map[id(cmd.func)] = i - 1
    end

    -- Funcs
    w4(dbuf, #funcs)
    for i, cmd in ipairs(funcs) do
        w4(dbuf, i - 1); w4(dbuf, sig_idx[id(cmd.sig)] or 0); -- func_id, sig_id
        local v = cmd.visibility
        local vis = (type(v) == "table" and v.kind == "VisibilityExport") and 1 or 0
        w4(dbuf, vis)
        local name = id(cmd.func)
        w4(dbuf, #name)
        -- write name as raw bytes
        dbuf[#dbuf+1] = name
        local pad = (4 - (#name % 4)) % 4
        if pad > 0 then dbuf[#dbuf+1] = ("\0"):rep(pad) end
    end
    -- Datas
    w4(dbuf, #datas)
    for _, cmd in ipairs(datas) do
        w4(dbuf, 0); w4(dbuf, cmd.size); w4(dbuf, cmd.align or 0)
    end
    -- Inits
    w4(dbuf, #inits)
    for _, cmd in ipairs(inits) do
        w4(dbuf, 0) -- data_id placeholder
        if cmd.kind == "CmdDataInitZero" then
            w4(dbuf, cmd.offset); w4(dbuf, 0); w4(dbuf, cmd.size); w4(dbuf, 0)
        else
            w4(dbuf, cmd.offset)
            local v = cmd.value
            if v.kind == "BackLitNull" then w4(dbuf, 0); w4(dbuf, 0); w4(dbuf, 0)
            elseif v.kind == "BackLitBool" then w4(dbuf, 1); w4(dbuf, v.value and 1 or 0); w4(dbuf, 0)
            elseif v.kind == "BackLitInt" then
                local raw = tonumber(v.raw) or 0
                lo, hi = u64_split(raw)
                w4(dbuf, 2); w4(dbuf, lo); w4(dbuf, hi)
            elseif v.kind == "BackLitFloat" then
                local bits = ffi.new("union { double d; uint32_t w[2]; }")
                bits.d = tonumber(v.raw) or 0.0
                w4(dbuf, 3); w4(dbuf, tonumber(bits.w[0])); w4(dbuf, tonumber(bits.w[1]))
            else w4(dbuf, 0); w4(dbuf, 0); w4(dbuf, 0) end
        end
    end
    -- Externs
    w4(dbuf, #externs)
    for i, cmd in ipairs(externs) do
        w4(dbuf, i - 1); w4(dbuf, 0); -- extern_id, sig_id (placeholders)
        local name = cmd.symbol
        w4(dbuf, #name)
        dbuf[#dbuf+1] = name
        local pad = (4 - (#name % 4)) % 4
        if pad > 0 then dbuf[#dbuf+1] = ("\0"):rep(pad) end
    end

    local decl_bytes = table.concat(dbuf)
    local body_tbl_size = #body_data * 12
    local body_start = header_size + #decl_bytes + body_tbl_size

    -- Build full buffer
    local buf = {}
    -- Header
    w4(buf, 0x4D4C); w4(buf, 4); w4(buf, #body_data)
    w4(buf, header_size); w4(buf, #decl_bytes)
    w4(buf, header_size + #decl_bytes); w4(buf, body_tbl_size)

    -- Declarations
    buf[#buf+1] = decl_bytes

    -- Body table
    for i, bd in ipairs(body_data) do
        local bid = func_map[bodies[i].func_id] or 0
        w4(buf, bid); w4(buf, body_start + bd.offset); w4(buf, #bd.bytes)
    end

    -- Body streams
    for _, bd in ipairs(body_data) do
        buf[#buf+1] = bd.bytes
    end

    return table.concat(buf)
end

function M.Define(T)
    local function encode(program)
        return M.encode(program)
    end
    return { encode = encode }
end

return M
