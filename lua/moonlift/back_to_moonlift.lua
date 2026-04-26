local pvm = require("moonlift.pvm")

local M = {}

local function map_array(phase, values)
    local out = {}
    for i = 1, #values do
        out[i] = pvm.one(phase(values[i]))
    end
    return out
end

function M.Define(T)
    local C2 = T.Moon2Core
    local B2 = T.Moon2Back
    local B1 = T.MoonliftBack
    if B1 == nil then
        error("moonlift.back_to_moonlift: define moonlift.asdl in the context before calling Define", 2)
    end

    local scalar
    local scalar_size
    local shape_append_param
    local shape_load_cmd
    local shape_store_cmd
    local literal_const
    local data_init
    local declare_func
    local unary_cmd
    local intrinsic_cmd
    local binary_cmd
    local compare_cmd
    local vec_compare_cmd
    local vec_mask_cmd
    local cast_cmd
    local call_direct_result
    local call_extern_result
    local call_indirect_result
    local call_cmd
    local cmd
    local program

    local function sig_id(id) return B1.BackSigId(id.text) end
    local function func_id(id) return B1.BackFuncId(id.text) end
    local function extern_id(id) return B1.BackExternId(id.text) end
    local function data_id(id) return B1.BackDataId(id.text) end
    local function block_id(id) return B1.BackBlockId(id.text) end
    local function val_id(id) return B1.BackValId(id.text) end
    local function slot_id(id) return B1.BackStackSlotId(id.text) end
    local function back_vec(vec) return B1.BackVec(pvm.one(scalar(vec.elem)), vec.lanes) end

    local function scalars(values)
        return map_array(scalar, values)
    end
    local function val_ids(values)
        local out = {}
        for i = 1, #values do
            out[i] = val_id(values[i])
        end
        return out
    end

    scalar_size = pvm.phase("moon2_back_scalar_size", {
        [B2.BackBool] = function() return pvm.once(1) end,
        [B2.BackI8] = function() return pvm.once(1) end,
        [B2.BackU8] = function() return pvm.once(1) end,
        [B2.BackI16] = function() return pvm.once(2) end,
        [B2.BackU16] = function() return pvm.once(2) end,
        [B2.BackI32] = function() return pvm.once(4) end,
        [B2.BackU32] = function() return pvm.once(4) end,
        [B2.BackF32] = function() return pvm.once(4) end,
        [B2.BackI64] = function() return pvm.once(8) end,
        [B2.BackU64] = function() return pvm.once(8) end,
        [B2.BackF64] = function() return pvm.once(8) end,
        [B2.BackPtr] = function() return pvm.once(8) end,
        [B2.BackIndex] = function() return pvm.once(8) end,
        [B2.BackVoid] = function()
            error("moonlift.back_to_moonlift: BackVoid has no data byte size")
        end,
    })

    scalar = pvm.phase("moon2_back_to_moonlift_scalar", {
        [B2.BackVoid] = function() return pvm.once(B1.BackVoid) end,
        [B2.BackBool] = function() return pvm.once(B1.BackBool) end,
        [B2.BackI8] = function() return pvm.once(B1.BackI8) end,
        [B2.BackI16] = function() return pvm.once(B1.BackI16) end,
        [B2.BackI32] = function() return pvm.once(B1.BackI32) end,
        [B2.BackI64] = function() return pvm.once(B1.BackI64) end,
        [B2.BackU8] = function() return pvm.once(B1.BackU8) end,
        [B2.BackU16] = function() return pvm.once(B1.BackU16) end,
        [B2.BackU32] = function() return pvm.once(B1.BackU32) end,
        [B2.BackU64] = function() return pvm.once(B1.BackU64) end,
        [B2.BackF32] = function() return pvm.once(B1.BackF32) end,
        [B2.BackF64] = function() return pvm.once(B1.BackF64) end,
        [B2.BackPtr] = function() return pvm.once(B1.BackPtr) end,
        [B2.BackIndex] = function() return pvm.once(B1.BackIndex) end,
    })

    shape_append_param = pvm.phase("moon2_back_to_moonlift_shape_append_param", {
        [B2.BackShapeScalar] = function(self, src)
            return pvm.once(B1.BackCmdAppendBlockParam(block_id(src.block), val_id(src.value), pvm.one(scalar(self.scalar))))
        end,
        [B2.BackShapeVec] = function(self, src)
            return pvm.once(B1.BackCmdAppendVecBlockParam(block_id(src.block), val_id(src.value), back_vec(self.vec)))
        end,
    })

    shape_load_cmd = pvm.phase("moon2_back_to_moonlift_shape_load_cmd", {
        [B2.BackShapeScalar] = function(self, src)
            return pvm.once(B1.BackCmdLoad(val_id(src.dst), pvm.one(scalar(self.scalar)), val_id(src.addr)))
        end,
        [B2.BackShapeVec] = function(self, src)
            return pvm.once(B1.BackCmdVecLoad(val_id(src.dst), back_vec(self.vec), val_id(src.addr)))
        end,
    })

    shape_store_cmd = pvm.phase("moon2_back_to_moonlift_shape_store_cmd", {
        [B2.BackShapeScalar] = function(self, src)
            return pvm.once(B1.BackCmdStore(pvm.one(scalar(self.scalar)), val_id(src.addr), val_id(src.value)))
        end,
        [B2.BackShapeVec] = function(self, src)
            return pvm.once(B1.BackCmdVecStore(back_vec(self.vec), val_id(src.addr), val_id(src.value)))
        end,
    })

    literal_const = pvm.phase("moon2_back_to_moonlift_literal_const", {
        [B2.BackLitInt] = function(self, src)
            return pvm.once(B1.BackCmdConstInt(val_id(src.dst), pvm.one(scalar(src.ty)), self.raw))
        end,
        [B2.BackLitFloat] = function(self, src)
            return pvm.once(B1.BackCmdConstFloat(val_id(src.dst), pvm.one(scalar(src.ty)), self.raw))
        end,
        [B2.BackLitBool] = function(self, src)
            return pvm.once(B1.BackCmdConstBool(val_id(src.dst), self.value))
        end,
        [B2.BackLitNull] = function(_, src)
            return pvm.once(B1.BackCmdConstNull(val_id(src.dst)))
        end,
    })

    data_init = pvm.phase("moon2_back_to_moonlift_data_init", {
        [B2.BackLitInt] = function(self, src)
            return pvm.once(B1.BackCmdDataInitInt(data_id(src.data), src.offset, pvm.one(scalar(src.ty)), self.raw))
        end,
        [B2.BackLitFloat] = function(self, src)
            return pvm.once(B1.BackCmdDataInitFloat(data_id(src.data), src.offset, pvm.one(scalar(src.ty)), self.raw))
        end,
        [B2.BackLitBool] = function(self, src)
            return pvm.once(B1.BackCmdDataInitBool(data_id(src.data), src.offset, self.value))
        end,
        [B2.BackLitNull] = function(_, src)
            return pvm.once(B1.BackCmdDataInitZero(data_id(src.data), src.offset, pvm.one(scalar_size(src.ty))))
        end,
    })

    declare_func = pvm.phase("moon2_back_to_moonlift_declare_func", {
        [C2.VisibilityLocal] = function(_, src)
            return pvm.once(B1.BackCmdDeclareFuncLocal(func_id(src.func), sig_id(src.sig)))
        end,
        [C2.VisibilityExport] = function(_, src)
            return pvm.once(B1.BackCmdDeclareFuncExport(func_id(src.func), sig_id(src.sig)))
        end,
    })

    unary_cmd = pvm.phase("moon2_back_to_moonlift_unary_cmd", {
        [B2.BackUnaryIneg] = function(_, src) return pvm.once(B1.BackCmdIneg(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.value))) end,
        [B2.BackUnaryFneg] = function(_, src) return pvm.once(B1.BackCmdFneg(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.value))) end,
        [B2.BackUnaryBnot] = function(_, src) return pvm.once(B1.BackCmdBnot(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.value))) end,
        [B2.BackUnaryBoolNot] = function(_, src) return pvm.once(B1.BackCmdBoolNot(val_id(src.dst), val_id(src.value))) end,
    })

    intrinsic_cmd = pvm.phase("moon2_back_to_moonlift_intrinsic_cmd", {
        [B2.BackIntrinsicPopcount] = function(_, src) return pvm.once(B1.BackCmdPopcount(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicClz] = function(_, src) return pvm.once(B1.BackCmdClz(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicCtz] = function(_, src) return pvm.once(B1.BackCmdCtz(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicBswap] = function(_, src) return pvm.once(B1.BackCmdBswap(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicSqrt] = function(_, src) return pvm.once(B1.BackCmdSqrt(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicAbs] = function(_, src) return pvm.once(B1.BackCmdAbs(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicFloor] = function(_, src) return pvm.once(B1.BackCmdFloor(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicCeil] = function(_, src) return pvm.once(B1.BackCmdCeil(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicTruncFloat] = function(_, src) return pvm.once(B1.BackCmdTruncFloat(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
        [B2.BackIntrinsicRound] = function(_, src) return pvm.once(B1.BackCmdRound(val_id(src.dst), pvm.one(scalar(src.ty.scalar)), val_id(src.args[1]))) end,
    })

    binary_cmd = pvm.phase("moon2_back_to_moonlift_binary_cmd", {
        [B2.BackIadd] = function(_, s) return pvm.once(B1.BackCmdIadd(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackIsub] = function(_, s) return pvm.once(B1.BackCmdIsub(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackImul] = function(_, s) return pvm.once(B1.BackCmdImul(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFadd] = function(_, s) return pvm.once(B1.BackCmdFadd(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFsub] = function(_, s) return pvm.once(B1.BackCmdFsub(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFmul] = function(_, s) return pvm.once(B1.BackCmdFmul(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSdiv] = function(_, s) return pvm.once(B1.BackCmdSdiv(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUdiv] = function(_, s) return pvm.once(B1.BackCmdUdiv(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFdiv] = function(_, s) return pvm.once(B1.BackCmdFdiv(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSrem] = function(_, s) return pvm.once(B1.BackCmdSrem(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUrem] = function(_, s) return pvm.once(B1.BackCmdUrem(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackBand] = function(_, s) return pvm.once(B1.BackCmdBand(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackBor] = function(_, s) return pvm.once(B1.BackCmdBor(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackBxor] = function(_, s) return pvm.once(B1.BackCmdBxor(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackIshl] = function(_, s) return pvm.once(B1.BackCmdIshl(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUshr] = function(_, s) return pvm.once(B1.BackCmdUshr(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSshr] = function(_, s) return pvm.once(B1.BackCmdSshr(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackRotl] = function(_, s) return pvm.once(B1.BackCmdRotl(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackRotr] = function(_, s) return pvm.once(B1.BackCmdRotr(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecIadd] = function(_, s) return pvm.once(B1.BackCmdVecIadd(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecIsub] = function(_, s) return pvm.once(B1.BackCmdVecIsub(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecImul] = function(_, s) return pvm.once(B1.BackCmdVecImul(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecBand] = function(_, s) return pvm.once(B1.BackCmdVecBand(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecBor] = function(_, s) return pvm.once(B1.BackCmdVecBor(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecBxor] = function(_, s) return pvm.once(B1.BackCmdVecBxor(val_id(s.dst), back_vec(s.ty.vec), val_id(s.lhs), val_id(s.rhs))) end,
    })

    compare_cmd = pvm.phase("moon2_back_to_moonlift_compare_cmd", {
        [B2.BackIcmpEq] = function(_, s) return pvm.once(B1.BackCmdIcmpEq(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackIcmpNe] = function(_, s) return pvm.once(B1.BackCmdIcmpNe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSIcmpLt] = function(_, s) return pvm.once(B1.BackCmdSIcmpLt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSIcmpLe] = function(_, s) return pvm.once(B1.BackCmdSIcmpLe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSIcmpGt] = function(_, s) return pvm.once(B1.BackCmdSIcmpGt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackSIcmpGe] = function(_, s) return pvm.once(B1.BackCmdSIcmpGe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUIcmpLt] = function(_, s) return pvm.once(B1.BackCmdUIcmpLt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUIcmpLe] = function(_, s) return pvm.once(B1.BackCmdUIcmpLe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUIcmpGt] = function(_, s) return pvm.once(B1.BackCmdUIcmpGt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackUIcmpGe] = function(_, s) return pvm.once(B1.BackCmdUIcmpGe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpEq] = function(_, s) return pvm.once(B1.BackCmdFCmpEq(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpNe] = function(_, s) return pvm.once(B1.BackCmdFCmpNe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpLt] = function(_, s) return pvm.once(B1.BackCmdFCmpLt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpLe] = function(_, s) return pvm.once(B1.BackCmdFCmpLe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpGt] = function(_, s) return pvm.once(B1.BackCmdFCmpGt(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackFCmpGe] = function(_, s) return pvm.once(B1.BackCmdFCmpGe(val_id(s.dst), pvm.one(scalar(s.ty.scalar)), val_id(s.lhs), val_id(s.rhs))) end,
    })

    vec_compare_cmd = pvm.phase("moon2_back_to_moonlift_vec_compare_cmd", {
        [B2.BackVecIcmpEq] = function(_, s) return pvm.once(B1.BackCmdVecIcmpEq(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecIcmpNe] = function(_, s) return pvm.once(B1.BackCmdVecIcmpNe(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecSIcmpLt] = function(_, s) return pvm.once(B1.BackCmdVecSIcmpLt(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecSIcmpLe] = function(_, s) return pvm.once(B1.BackCmdVecSIcmpLe(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecSIcmpGt] = function(_, s) return pvm.once(B1.BackCmdVecSIcmpGt(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecSIcmpGe] = function(_, s) return pvm.once(B1.BackCmdVecSIcmpGe(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecUIcmpLt] = function(_, s) return pvm.once(B1.BackCmdVecUIcmpLt(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecUIcmpLe] = function(_, s) return pvm.once(B1.BackCmdVecUIcmpLe(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecUIcmpGt] = function(_, s) return pvm.once(B1.BackCmdVecUIcmpGt(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
        [B2.BackVecUIcmpGe] = function(_, s) return pvm.once(B1.BackCmdVecUIcmpGe(val_id(s.dst), back_vec(s.ty), val_id(s.lhs), val_id(s.rhs))) end,
    })

    vec_mask_cmd = pvm.phase("moon2_back_to_moonlift_vec_mask_cmd", {
        [B2.BackVecMaskNot] = function(_, s) return pvm.once(B1.BackCmdVecMaskNot(val_id(s.dst), back_vec(s.ty), val_id(s.args[1]))) end,
        [B2.BackVecMaskAnd] = function(_, s) return pvm.once(B1.BackCmdVecMaskAnd(val_id(s.dst), back_vec(s.ty), val_id(s.args[1]), val_id(s.args[2]))) end,
        [B2.BackVecMaskOr] = function(_, s) return pvm.once(B1.BackCmdVecMaskOr(val_id(s.dst), back_vec(s.ty), val_id(s.args[1]), val_id(s.args[2]))) end,
    })

    cast_cmd = pvm.phase("moon2_back_to_moonlift_cast_cmd", {
        [B2.BackBitcast] = function(_, s) return pvm.once(B1.BackCmdBitcast(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackIreduce] = function(_, s) return pvm.once(B1.BackCmdIreduce(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackSextend] = function(_, s) return pvm.once(B1.BackCmdSextend(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackUextend] = function(_, s) return pvm.once(B1.BackCmdUextend(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackFpromote] = function(_, s) return pvm.once(B1.BackCmdFpromote(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackFdemote] = function(_, s) return pvm.once(B1.BackCmdFdemote(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackSToF] = function(_, s) return pvm.once(B1.BackCmdSToF(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackUToF] = function(_, s) return pvm.once(B1.BackCmdUToF(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackFToS] = function(_, s) return pvm.once(B1.BackCmdFToS(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
        [B2.BackFToU] = function(_, s) return pvm.once(B1.BackCmdFToU(val_id(s.dst), pvm.one(scalar(s.ty)), val_id(s.value))) end,
    })

    call_direct_result = pvm.phase("moon2_back_to_moonlift_call_direct_result", {
        [B2.BackCallStmt] = function(_, target, src)
            return pvm.once(B1.BackCmdCallStmtDirect(func_id(target.func), sig_id(src.sig), val_ids(src.args)))
        end,
        [B2.BackCallValue] = function(self, target, src)
            return pvm.once(B1.BackCmdCallValueDirect(val_id(self.dst), pvm.one(scalar(self.ty)), func_id(target.func), sig_id(src.sig), val_ids(src.args)))
        end,
    })

    call_extern_result = pvm.phase("moon2_back_to_moonlift_call_extern_result", {
        [B2.BackCallStmt] = function(_, target, src)
            return pvm.once(B1.BackCmdCallStmtExtern(extern_id(target.func), sig_id(src.sig), val_ids(src.args)))
        end,
        [B2.BackCallValue] = function(self, target, src)
            return pvm.once(B1.BackCmdCallValueExtern(val_id(self.dst), pvm.one(scalar(self.ty)), extern_id(target.func), sig_id(src.sig), val_ids(src.args)))
        end,
    })

    call_indirect_result = pvm.phase("moon2_back_to_moonlift_call_indirect_result", {
        [B2.BackCallStmt] = function(_, target, src)
            return pvm.once(B1.BackCmdCallStmtIndirect(val_id(target.callee), sig_id(src.sig), val_ids(src.args)))
        end,
        [B2.BackCallValue] = function(self, target, src)
            return pvm.once(B1.BackCmdCallValueIndirect(val_id(self.dst), pvm.one(scalar(self.ty)), val_id(target.callee), sig_id(src.sig), val_ids(src.args)))
        end,
    })

    call_cmd = pvm.phase("moon2_back_to_moonlift_call_cmd", {
        [B2.BackCallDirect] = function(self, src)
            return call_direct_result(src.result, self, src)
        end,
        [B2.BackCallExtern] = function(self, src)
            return call_extern_result(src.result, self, src)
        end,
        [B2.BackCallIndirect] = function(self, src)
            return call_indirect_result(src.result, self, src)
        end,
    })

    cmd = pvm.phase("moon2_back_to_moonlift_cmd", {
        [B2.CmdCreateSig] = function(self) return pvm.once(B1.BackCmdCreateSig(sig_id(self.sig), scalars(self.params), scalars(self.results))) end,
        [B2.CmdDeclareData] = function(self) return pvm.once(B1.BackCmdDeclareData(data_id(self.data), self.size, self.align)) end,
        [B2.CmdDataInitZero] = function(self) return pvm.once(B1.BackCmdDataInitZero(data_id(self.data), self.offset, self.size)) end,
        [B2.CmdDataInit] = function(self) return data_init(self.value, self) end,
        [B2.CmdDataAddr] = function(self) return pvm.once(B1.BackCmdDataAddr(val_id(self.dst), data_id(self.data))) end,
        [B2.CmdFuncAddr] = function(self) return pvm.once(B1.BackCmdFuncAddr(val_id(self.dst), func_id(self.func))) end,
        [B2.CmdExternAddr] = function(self) return pvm.once(B1.BackCmdExternAddr(val_id(self.dst), extern_id(self.func))) end,
        [B2.CmdDeclareFunc] = function(self) return declare_func(self.visibility, self) end,
        [B2.CmdDeclareExtern] = function(self) return pvm.once(B1.BackCmdDeclareFuncExtern(extern_id(self.func), self.symbol, sig_id(self.sig))) end,
        [B2.CmdBeginFunc] = function(self) return pvm.once(B1.BackCmdBeginFunc(func_id(self.func))) end,
        [B2.CmdCreateBlock] = function(self) return pvm.once(B1.BackCmdCreateBlock(block_id(self.block))) end,
        [B2.CmdSwitchToBlock] = function(self) return pvm.once(B1.BackCmdSwitchToBlock(block_id(self.block))) end,
        [B2.CmdSealBlock] = function(self) return pvm.once(B1.BackCmdSealBlock(block_id(self.block))) end,
        [B2.CmdBindEntryParams] = function(self) return pvm.once(B1.BackCmdBindEntryParams(block_id(self.block), val_ids(self.values))) end,
        [B2.CmdAppendBlockParam] = function(self) return shape_append_param(self.ty, self) end,
        [B2.CmdCreateStackSlot] = function(self) return pvm.once(B1.BackCmdCreateStackSlot(slot_id(self.slot), self.size, self.align)) end,
        [B2.CmdAlias] = function(self) return pvm.once(B1.BackCmdAlias(val_id(self.dst), val_id(self.src))) end,
        [B2.CmdStackAddr] = function(self) return pvm.once(B1.BackCmdStackAddr(val_id(self.dst), slot_id(self.slot))) end,
        [B2.CmdConst] = function(self) return literal_const(self.value, self) end,
        [B2.CmdUnary] = function(self) return unary_cmd(self.op, self) end,
        [B2.CmdIntrinsic] = function(self) return intrinsic_cmd(self.op, self) end,
        [B2.CmdBinary] = function(self) return binary_cmd(self.op, self) end,
        [B2.CmdCompare] = function(self) return compare_cmd(self.op, self) end,
        [B2.CmdCast] = function(self) return cast_cmd(self.op, self) end,
        [B2.CmdLoad] = function(self) return shape_load_cmd(self.ty, self) end,
        [B2.CmdStore] = function(self) return shape_store_cmd(self.ty, self) end,
        [B2.CmdMemcpy] = function(self) return pvm.once(B1.BackCmdMemcpy(val_id(self.dst), val_id(self.src), val_id(self.len))) end,
        [B2.CmdMemset] = function(self) return pvm.once(B1.BackCmdMemset(val_id(self.dst), val_id(self.byte), val_id(self.len))) end,
        [B2.CmdSelect] = function(self) return pvm.once(B1.BackCmdSelect(val_id(self.dst), pvm.one(scalar(self.ty.scalar)), val_id(self.cond), val_id(self.then_value), val_id(self.else_value))) end,
        [B2.CmdFma] = function(self) return pvm.once(B1.BackCmdFma(val_id(self.dst), pvm.one(scalar(self.ty)), val_id(self.a), val_id(self.b), val_id(self.c))) end,
        [B2.CmdVecSplat] = function(self) return pvm.once(B1.BackCmdVecSplat(val_id(self.dst), back_vec(self.ty), val_id(self.value))) end,
        [B2.CmdVecCompare] = function(self) return vec_compare_cmd(self.op, self) end,
        [B2.CmdVecSelect] = function(self) return pvm.once(B1.BackCmdVecSelect(val_id(self.dst), back_vec(self.ty), val_id(self.mask), val_id(self.then_value), val_id(self.else_value))) end,
        [B2.CmdVecMask] = function(self) return vec_mask_cmd(self.op, self) end,
        [B2.CmdVecInsertLane] = function(self) return pvm.once(B1.BackCmdVecInsertLane(val_id(self.dst), back_vec(self.ty), val_id(self.value), val_id(self.lane_value), self.lane)) end,
        [B2.CmdVecExtractLane] = function(self) return pvm.once(B1.BackCmdVecExtractLane(val_id(self.dst), pvm.one(scalar(self.ty)), val_id(self.value), self.lane)) end,
        [B2.CmdCall] = function(self) return call_cmd(self.target, self) end,
        [B2.CmdJump] = function(self) return pvm.once(B1.BackCmdJump(block_id(self.dest), val_ids(self.args))) end,
        [B2.CmdBrIf] = function(self) return pvm.once(B1.BackCmdBrIf(val_id(self.cond), block_id(self.then_block), val_ids(self.then_args), block_id(self.else_block), val_ids(self.else_args))) end,
        [B2.CmdSwitchInt] = function(self)
            local cases = {}
            for i = 1, #self.cases do
                cases[i] = B1.BackSwitchCase(self.cases[i].raw, block_id(self.cases[i].dest))
            end
            return pvm.once(B1.BackCmdSwitchInt(val_id(self.value), pvm.one(scalar(self.ty)), cases, block_id(self.default_dest)))
        end,
        [B2.CmdReturnVoid] = function() return pvm.once(B1.BackCmdReturnVoid) end,
        [B2.CmdReturnValue] = function(self) return pvm.once(B1.BackCmdReturnValue(val_id(self.value))) end,
        [B2.CmdTrap] = function() return pvm.once(B1.BackCmdTrap) end,
        [B2.CmdFinishFunc] = function(self) return pvm.once(B1.BackCmdFinishFunc(func_id(self.func))) end,
        [B2.CmdFinalizeModule] = function() return pvm.once(B1.BackCmdFinalizeModule) end,
    })

    program = pvm.phase("moon2_back_to_moonlift_program", function(src)
        local out = {}
        for i = 1, #src.cmds do
            out[#out + 1] = pvm.one(cmd(src.cmds[i]))
        end
        return B1.BackProgram(out)
    end)

    return {
        scalar = scalar,
        cmd = cmd,
        program = program,
        lower_program = function(src)
            return pvm.one(program(src))
        end,
    }
end

return M
