local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Back = T.MoonBack or T.MoonBack
    local Vec = T.MoonVec or T.MoonVec
    local Host = T.MoonHost or T.MoonHost
    assert(Back and Vec and Host, "moonlift.back_target_model.Define expects MoonBack/MoonVec/MoonHost in the context")

    local api = {}

    local function shape_scalar(s) return Back.BackShapeScalar(s) end
    local function shape_vec(elem, lanes) return Back.BackShapeVec(Back.BackVec(elem, lanes)) end

    function api.default_native()
        return Back.BackTargetModel(Back.BackTargetCraneliftJit, {
            Back.BackTargetPointerBits(64),
            Back.BackTargetIndexBits(64),
            Back.BackTargetEndian(Back.BackEndianLittle),
            Back.BackTargetCacheLineBytes(64),
            Back.BackTargetFeature(Back.BackFeatureSSE2),
            Back.BackTargetFeature(Back.BackFeaturePOPCNT),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackI32)),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackI64)),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackU32)),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackU64)),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackF32)),
            Back.BackTargetSupportsShape(shape_scalar(Back.BackF64)),
            Back.BackTargetSupportsShape(shape_vec(Back.BackI32, 4)),
            Back.BackTargetSupportsShape(shape_vec(Back.BackU32, 4)),
            Back.BackTargetSupportsShape(shape_vec(Back.BackI64, 2)),
            Back.BackTargetSupportsShape(shape_vec(Back.BackU64, 2)),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI32, 4), "int_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU32, 4), "int_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI64, 2), "int_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU64, 2), "int_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI32, 4), "bit_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU32, 4), "bit_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI64, 2), "bit_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU64, 2), "bit_binary"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI32, 4), "compare_select"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU32, 4), "compare_select"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI64, 2), "compare_select"),
            Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackU64, 2), "compare_select"),
            Back.BackTargetPrefersUnroll(shape_vec(Back.BackI32, 4), 1, 50),
            Back.BackTargetPrefersUnroll(shape_vec(Back.BackU32, 4), 1, 50),
            Back.BackTargetPrefersUnroll(shape_vec(Back.BackI64, 2), 1, 50),
            Back.BackTargetPrefersUnroll(shape_vec(Back.BackU64, 2), 1, 50),
        })
    end

    local function first_fact(model, cls)
        for i = 1, #model.facts do
            if pvm.classof(model.facts[i]) == cls then return model.facts[i] end
        end
        return nil
    end

    function api.host_target(model)
        local pointer = first_fact(model, Back.BackTargetPointerBits)
        local index = first_fact(model, Back.BackTargetIndexBits)
        local endian = first_fact(model, Back.BackTargetEndian)
        local host_endian = Host.HostEndianLittle
        if endian ~= nil and endian.endian == Back.BackEndianBig then host_endian = Host.HostEndianBig end
        return Host.HostTargetModel(pointer and pointer.bits or 64, index and index.bits or 64, host_endian)
    end

    local function vec_elem(scalar)
        local k = scalar.kind
        if k == "BackBool" then return Vec.VecElemBool end
        if k == "BackI8" then return Vec.VecElemI8 end
        if k == "BackI16" then return Vec.VecElemI16 end
        if k == "BackI32" then return Vec.VecElemI32 end
        if k == "BackI64" then return Vec.VecElemI64 end
        if k == "BackU8" then return Vec.VecElemU8 end
        if k == "BackU16" then return Vec.VecElemU16 end
        if k == "BackU32" then return Vec.VecElemU32 end
        if k == "BackU64" then return Vec.VecElemU64 end
        if k == "BackF32" then return Vec.VecElemF32 end
        if k == "BackF64" then return Vec.VecElemF64 end
        if k == "BackPtr" then return Vec.VecElemPtr end
        if k == "BackIndex" then return Vec.VecElemIndex end
        return nil
    end

    local function vec_shape(shape)
        if pvm.classof(shape) == Back.BackShapeScalar then
            local elem = vec_elem(shape.scalar)
            return elem and Vec.VecScalarShape(elem) or nil
        end
        if pvm.classof(shape) == Back.BackShapeVec then
            local elem = vec_elem(shape.vec.elem)
            return elem and Vec.VecVectorShape(elem, shape.vec.lanes) or nil
        end
        return nil
    end

    local function append_supported_ops(out, shape)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecAdd)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecSub)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecMul)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecBitAnd)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecBitOr)
        out[#out + 1] = Vec.VecTargetSupportsBinOp(shape, Vec.VecBitXor)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpEq)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpNe)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpSLt)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpSLe)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpSGt)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpSGe)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpULt)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpULe)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpUGt)
        out[#out + 1] = Vec.VecTargetSupportsCmpOp(shape, Vec.VecCmpUGe)
        out[#out + 1] = Vec.VecTargetSupportsSelect(shape)
        out[#out + 1] = Vec.VecTargetSupportsMaskOp(shape, Vec.VecMaskNot)
        out[#out + 1] = Vec.VecTargetSupportsMaskOp(shape, Vec.VecMaskAnd)
        out[#out + 1] = Vec.VecTargetSupportsMaskOp(shape, Vec.VecMaskOr)
    end

    function api.vec_target(model)
        local facts = {}
        for i = 1, #model.facts do
            local fact = model.facts[i]
            local cls = pvm.classof(fact)
            if cls == Back.BackTargetSupportsShape then
                local shape = vec_shape(fact.shape)
                if shape ~= nil then
                    facts[#facts + 1] = Vec.VecTargetSupportsShape(shape)
                    if pvm.classof(shape) == Vec.VecVectorShape then append_supported_ops(facts, shape) end
                end
            elseif cls == Back.BackTargetPrefersUnroll then
                local shape = vec_shape(fact.shape)
                if shape ~= nil then facts[#facts + 1] = Vec.VecTargetPrefersUnroll(shape, fact.unroll, fact.rank) end
            elseif cls == Back.BackTargetSupportsMaskedTail then
                facts[#facts + 1] = Vec.VecTargetSupportsMaskedTail
            end
        end
        facts[#facts + 1] = Vec.VecTargetPrefersScalarTail
        facts[#facts + 1] = Vec.VecTargetVectorBits(128)
        return Vec.VecTargetModel(Vec.VecTargetCraneliftJit, facts)
    end

    return api
end

return M
