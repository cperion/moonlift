local asdl = require("lalin.asdl")

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.reduction_algebra ~= nil then return T._lalin_api_cache.reduction_algebra end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Back = T.LalinBack

    local api = {}

    local function type_info(ty)
        if ty == Code.CodeTyBool8 then return { class = "bool", bits = 8, signed = false, scalar = Back.BackBool } end
        if ty == Code.CodeTyIndex then return { class = "index", bits = 64, signed = false, scalar = Back.BackIndex } end
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then
            local signed = ty.signedness == Code.CodeSigned
            local scalar
            if ty.bits == 8 then scalar = signed and Back.BackI8 or Back.BackU8
            elseif ty.bits == 16 then scalar = signed and Back.BackI16 or Back.BackU16
            elseif ty.bits == 32 then scalar = signed and Back.BackI32 or Back.BackU32
            elseif ty.bits == 64 then scalar = signed and Back.BackI64 or Back.BackU64 end
            return { class = "int", bits = ty.bits, signed = signed, scalar = scalar }
        elseif cls == Code.CodeTyFloat then
            local scalar = ty.bits == 32 and Back.BackF32 or (ty.bits == 64 and Back.BackF64 or nil)
            return { class = "float", bits = ty.bits, signed = true, scalar = scalar }
        end
        return { class = "unsupported", reason = "unsupported reduction type " .. class_name(ty) }
    end

    local function max_unsigned(bits)
        if bits == 64 then return "18446744073709551615" end
        return tostring((2 ^ bits) - 1)
    end

    local function max_signed(bits)
        if bits == 64 then return "9223372036854775807" end
        return tostring((2 ^ (bits - 1)) - 1)
    end

    local function min_signed(bits)
        if bits == 64 then return "-9223372036854775808" end
        return tostring(-(2 ^ (bits - 1)))
    end

    local function reduction_name(op)
        if op == Value.ReductionAdd then return "add" end
        if op == Value.ReductionMul then return "mul" end
        if op == Value.ReductionAnd then return "and" end
        if op == Value.ReductionOr then return "or" end
        if op == Value.ReductionXor then return "xor" end
        if op == Value.ReductionMin then return "min" end
        if op == Value.ReductionMax then return "max" end
        return nil
    end

    local vector_int_bin = {
        add = Back.BackVecIntAdd,
        mul = Back.BackVecIntMul,
        ["and"] = Back.BackVecBitAnd,
        ["or"] = Back.BackVecBitOr,
        xor = Back.BackVecBitXor,
    }

    local scalar_int_bin = {
        add = Back.BackIntAdd,
        mul = Back.BackIntMul,
    }

    local scalar_bit_bin = {
        ["and"] = Back.BackBitAnd,
        ["or"] = Back.BackBitOr,
        xor = Back.BackBitXor,
    }

    local function identity_raw(name, info)
        if name == "add" or name == "or" or name == "xor" then return "0" end
        if name == "mul" then return "1" end
        if name == "and" then return "-1" end
        if name == "min" then
            if info.class == "float" then return "inf" end
            if info.signed then return max_signed(info.bits) end
            return max_unsigned(info.bits)
        end
        if name == "max" then
            if info.class == "float" then return "-inf" end
            if info.signed then return min_signed(info.bits) end
            return "0"
        end
        return nil
    end

    local function minmax_compare(name, info)
        if info.class == "float" then
            return name == "min" and Back.BackFCmpLe or Back.BackFCmpGe
        end
        if info.signed then
            return name == "min" and Back.BackSIcmpLe or Back.BackSIcmpGe
        end
        return name == "min" and Back.BackUIcmpLe or Back.BackUIcmpGe
    end

    local function minmax_vec_compare(name, info)
        if info.class == "float" then return nil, "Back has no vector float compare for reductions" end
        if info.signed then
            return name == "min" and Back.BackVecSIcmpLe or Back.BackVecSIcmpGe
        end
        return name == "min" and Back.BackVecUIcmpLe or Back.BackVecUIcmpGe
    end

    local function entry(op, ty)
        local name = reduction_name(op)
        if name == nil then return nil, "unknown reduction op " .. class_name(op) end
        local info = type_info(ty)
        if info.class == "unsupported" or info.scalar == nil then return nil, info.reason or "unsupported reduction type" end

        local e = {
            op = op,
            name = name,
            ty = ty,
            type = info,
            scalar = info.scalar,
            identity_raw = identity_raw(name, info),
            scalar_int_op = scalar_int_bin[name],
            scalar_bit_op = scalar_bit_bin[name],
            vector_op = vector_int_bin[name],
        }

        if name == "add" or name == "mul" then
            if info.class == "float" then return nil, "float vector " .. name .. " reduction requires Back vector float ops" end
            if info.class ~= "int" and info.class ~= "index" and info.class ~= "bool" then return nil, "non-integer " .. name .. " reduction is unsupported" end
        elseif name == "and" or name == "or" or name == "xor" then
            if info.class == "float" then return nil, "float bitwise reduction is invalid" end
        elseif name == "min" or name == "max" then
            e.scalar_compare = minmax_compare(name, info)
            local vc, why = minmax_vec_compare(name, info)
            if vc == nil then return nil, why end
            e.vector_compare = vc
        end

        if e.identity_raw == nil then return nil, "no identity for reduction " .. name end
        return e
    end

    function api.type_info(ty) return type_info(ty) end
    function api.reduction_name(op) return reduction_name(op) end
    function api.entry(op, ty) return entry(op, ty) end

    function api.identity_expr(op, ty)
        local name = reduction_name(op)
        if name == nil then return nil, "unknown reduction op " .. class_name(op) end
        local info = type_info(ty)
        if info.class == "unsupported" then return nil, info.reason or "unsupported reduction type" end
        local raw = identity_raw(name, info)
        if raw == nil then return nil, "no identity for reduction " .. name end
        local literal
        if info.class == "float" then literal = Core.LitFloat(raw)
        else literal = Core.LitInt(raw) end
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, literal)), nil, { op = op, name = name, ty = ty, type = info, identity_raw = raw }
    end

    function api.literal_identity_raw(expr)
        if asdl.classof(expr) ~= Value.ValueExprConst then return nil end
        local k = expr.const or expr.value
        if asdl.classof(k) ~= Code.CodeConstLiteral then return nil end
        local lit = k.literal or k.value
        if asdl.classof(lit) == Core.LitInt or asdl.classof(lit) == Core.LitFloat then return tostring(lit.raw or lit.text) end
        if asdl.classof(lit) == Core.LitBool then return lit.value and "1" or "0" end
        return nil
    end

    function api.identity_matches(expr, op, ty)
        local _, why, e = api.identity_expr(op, ty)
        if e == nil then return false, why end
        return api.literal_identity_raw(expr) == tostring(e.identity_raw), "expected identity " .. tostring(e.identity_raw)
    end

    function api.binary_reduction_op(op, is_float)
        if op == Core.BinAdd then return Value.ReductionAdd end
        if op == Core.BinMul then return Value.ReductionMul end
        if not is_float then
            if op == Core.BinBitAnd then return Value.ReductionAnd end
            if op == Core.BinBitOr then return Value.ReductionOr end
            if op == Core.BinBitXor then return Value.ReductionXor end
        end
        return nil
    end

    function api.select_minmax_op(cmp_op, true_value_is_lhs)
        if cmp_op == Core.CmpLt or cmp_op == Core.CmpLe then return true_value_is_lhs and Value.ReductionMin or Value.ReductionMax end
        if cmp_op == Core.CmpGt or cmp_op == Core.CmpGe then return true_value_is_lhs and Value.ReductionMax or Value.ReductionMin end
        return nil
    end

    function api.vector_support(reduction, elem_ty)
        local e, why = entry(reduction.op, elem_ty or reduction.ty)
        if e == nil then return false, why end
        return true, nil, e
    end

    T._lalin_api_cache.reduction_algebra = api
    return api
end

return bind_context
