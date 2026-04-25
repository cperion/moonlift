package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack

    local type_mem_size
    local type_is_signed_integral
    local cast_to_integral_op
    local cast_to_float_op
    local cast_op
    local cast_cmd

    local function one_type_mem_size(node)
        return pvm.one(type_mem_size(node))
    end

    local function one_type_is_signed_integral(node)
        return pvm.one(type_is_signed_integral(node))
    end

    local function int_to_int_cast_op(src_ty, dest_ty)
        local src_size = one_type_mem_size(src_ty)
        local dst_size = one_type_mem_size(dest_ty)
        if dst_size < src_size then
            return Sem.SemCastIreduce
        end
        if dst_size > src_size then
            if one_type_is_signed_integral(src_ty) then
                return Sem.SemCastSextend
            end
            return Sem.SemCastUextend
        end
        return Sem.SemCastIdentity
    end

    local function float_to_float_cast_op(src_ty, dest_ty)
        local src_size = one_type_mem_size(src_ty)
        local dst_size = one_type_mem_size(dest_ty)
        if dst_size < src_size then
            return Sem.SemCastFdemote
        end
        if dst_size > src_size then
            return Sem.SemCastFpromote
        end
        return Sem.SemCastIdentity
    end

    type_mem_size = pvm.phase("sem_to_back_cast_type_mem_size", {
        [Sem.SemTBool] = function() return pvm.once(1) end,
        [Sem.SemTI8] = function() return pvm.once(1) end,
        [Sem.SemTU8] = function() return pvm.once(1) end,
        [Sem.SemTI16] = function() return pvm.once(2) end,
        [Sem.SemTU16] = function() return pvm.once(2) end,
        [Sem.SemTI32] = function() return pvm.once(4) end,
        [Sem.SemTU32] = function() return pvm.once(4) end,
        [Sem.SemTF32] = function() return pvm.once(4) end,
        [Sem.SemTI64] = function() return pvm.once(8) end,
        [Sem.SemTU64] = function() return pvm.once(8) end,
        [Sem.SemTF64] = function() return pvm.once(8) end,
        [Sem.SemTIndex] = function() return pvm.once(8) end,
        [Sem.SemTRawPtr] = function() return pvm.once(8) end,
        [Sem.SemTPtrTo] = function() return pvm.once(8) end,
        [Sem.SemTVoid] = function() error("sem_to_back_cast: void has no scalar runtime size") end,
        [Sem.SemTArray] = function() error("sem_to_back_cast: array size is not a scalar cast size") end,
        [Sem.SemTSlice] = function() error("sem_to_back_cast: slice size is not a scalar cast size") end,
        [Sem.SemTView] = function() error("sem_to_back_cast: view size is not a scalar cast size") end,
        [Sem.SemTNamed] = function() error("sem_to_back_cast: named aggregate size is not a scalar cast size") end,
    })

    type_is_signed_integral = pvm.phase("sem_to_back_cast_type_is_signed_integral", {
        [Sem.SemTI8] = function() return pvm.once(true) end,
        [Sem.SemTI16] = function() return pvm.once(true) end,
        [Sem.SemTI32] = function() return pvm.once(true) end,
        [Sem.SemTI64] = function() return pvm.once(true) end,
        [Sem.SemTVoid] = function() return pvm.once(false) end,
        [Sem.SemTBool] = function() return pvm.once(false) end,
        [Sem.SemTU8] = function() return pvm.once(false) end,
        [Sem.SemTU16] = function() return pvm.once(false) end,
        [Sem.SemTU32] = function() return pvm.once(false) end,
        [Sem.SemTU64] = function() return pvm.once(false) end,
        [Sem.SemTF32] = function() return pvm.once(false) end,
        [Sem.SemTF64] = function() return pvm.once(false) end,
        [Sem.SemTRawPtr] = function() return pvm.once(false) end,
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    cast_to_integral_op = pvm.phase("sem_to_back_cast_to_integral_op", {
        [Sem.SemTBool] = function() return pvm.once(Sem.SemCastUextend) end,
        [Sem.SemTI8] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTI16] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTI32] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTI64] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTU8] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTU16] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTU32] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTU64] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTIndex] = function(self, dest_ty) return pvm.once(int_to_int_cast_op(self, dest_ty)) end,
        [Sem.SemTF32] = function(_, dest_ty)
            if one_type_is_signed_integral(dest_ty) then return pvm.once(Sem.SemCastFToS) end
            return pvm.once(Sem.SemCastFToU)
        end,
        [Sem.SemTF64] = function(_, dest_ty)
            if one_type_is_signed_integral(dest_ty) then return pvm.once(Sem.SemCastFToS) end
            return pvm.once(Sem.SemCastFToU)
        end,
        [Sem.SemTVoid] = function() error("sem_to_back_cast: cannot cast void to an integer type") end,
        [Sem.SemTRawPtr] = function() error("sem_to_back_cast: pointer-to-integer cast is not implemented yet") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_cast: pointer-to-integer cast is not implemented yet") end,
        [Sem.SemTArray] = function() error("sem_to_back_cast: cannot cast array values to an integer type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_cast: cannot cast slice values to an integer type") end,
        [Sem.SemTView] = function() error("sem_to_back_cast: cannot cast view values to an integer type") end,
        [Sem.SemTNamed] = function() error("sem_to_back_cast: cannot cast named aggregate values to an integer type") end,
    })

    cast_to_float_op = pvm.phase("sem_to_back_cast_to_float_op", {
        [Sem.SemTI8] = function() return pvm.once(Sem.SemCastSToF) end,
        [Sem.SemTI16] = function() return pvm.once(Sem.SemCastSToF) end,
        [Sem.SemTI32] = function() return pvm.once(Sem.SemCastSToF) end,
        [Sem.SemTI64] = function() return pvm.once(Sem.SemCastSToF) end,
        [Sem.SemTU8] = function() return pvm.once(Sem.SemCastUToF) end,
        [Sem.SemTU16] = function() return pvm.once(Sem.SemCastUToF) end,
        [Sem.SemTU32] = function() return pvm.once(Sem.SemCastUToF) end,
        [Sem.SemTU64] = function() return pvm.once(Sem.SemCastUToF) end,
        [Sem.SemTIndex] = function() return pvm.once(Sem.SemCastUToF) end,
        [Sem.SemTF32] = function(self, dest_ty) return pvm.once(float_to_float_cast_op(self, dest_ty)) end,
        [Sem.SemTF64] = function(self, dest_ty) return pvm.once(float_to_float_cast_op(self, dest_ty)) end,
        [Sem.SemTVoid] = function() error("sem_to_back_cast: cannot cast void to a float type") end,
        [Sem.SemTBool] = function() error("sem_to_back_cast: bool-to-float cast is not implemented yet") end,
        [Sem.SemTRawPtr] = function() error("sem_to_back_cast: pointer-to-float cast is not implemented yet") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_cast: pointer-to-float cast is not implemented yet") end,
        [Sem.SemTArray] = function() error("sem_to_back_cast: cannot cast array values to a float type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_cast: cannot cast slice values to a float type") end,
        [Sem.SemTView] = function() error("sem_to_back_cast: cannot cast view values to a float type") end,
        [Sem.SemTNamed] = function() error("sem_to_back_cast: cannot cast named aggregate values to a float type") end,
    })

    cast_op = pvm.phase("sem_to_back_cast_op", {
        [Sem.SemTI8] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTI16] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTI32] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTI64] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTU8] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTU16] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTU32] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTU64] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTIndex] = function(self, src_ty) return cast_to_integral_op(src_ty, self) end,
        [Sem.SemTF32] = function(self, src_ty) return cast_to_float_op(src_ty, self) end,
        [Sem.SemTF64] = function(self, src_ty) return cast_to_float_op(src_ty, self) end,
        [Sem.SemTBool] = function() error("sem_to_back_cast: cast-to-bool is not implemented yet") end,
        [Sem.SemTVoid] = function() error("sem_to_back_cast: cannot cast to void") end,
        [Sem.SemTRawPtr] = function() error("sem_to_back_cast: cast-to-pointer is not implemented yet") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_cast: cast-to-pointer is not implemented yet") end,
        [Sem.SemTArray] = function() error("sem_to_back_cast: cannot cast to array type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_cast: cannot cast to slice type") end,
        [Sem.SemTView] = function() error("sem_to_back_cast: cannot cast to view type") end,
        [Sem.SemTNamed] = function() error("sem_to_back_cast: cannot cast to named aggregate type") end,
    })

    cast_cmd = pvm.phase("sem_to_back_cast_cmd", {
        [Sem.SemCastIdentity] = function(_, dst, ty, value) return pvm.once(Back.BackCmdAlias(dst, value)) end,
        [Sem.SemCastBitcast] = function(_, dst, ty, value) return pvm.once(Back.BackCmdBitcast(dst, ty, value)) end,
        [Sem.SemCastIreduce] = function(_, dst, ty, value) return pvm.once(Back.BackCmdIreduce(dst, ty, value)) end,
        [Sem.SemCastSextend] = function(_, dst, ty, value) return pvm.once(Back.BackCmdSextend(dst, ty, value)) end,
        [Sem.SemCastUextend] = function(_, dst, ty, value) return pvm.once(Back.BackCmdUextend(dst, ty, value)) end,
        [Sem.SemCastFpromote] = function(_, dst, ty, value) return pvm.once(Back.BackCmdFpromote(dst, ty, value)) end,
        [Sem.SemCastFdemote] = function(_, dst, ty, value) return pvm.once(Back.BackCmdFdemote(dst, ty, value)) end,
        [Sem.SemCastSToF] = function(_, dst, ty, value) return pvm.once(Back.BackCmdSToF(dst, ty, value)) end,
        [Sem.SemCastUToF] = function(_, dst, ty, value) return pvm.once(Back.BackCmdUToF(dst, ty, value)) end,
        [Sem.SemCastFToS] = function(_, dst, ty, value) return pvm.once(Back.BackCmdFToS(dst, ty, value)) end,
        [Sem.SemCastFToU] = function(_, dst, ty, value) return pvm.once(Back.BackCmdFToU(dst, ty, value)) end,
    })

    return {
        lower_cast_op = cast_op,
        lower_cast_cmd = cast_cmd,
    }
end

return M
