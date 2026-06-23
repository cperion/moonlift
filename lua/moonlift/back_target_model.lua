local pvm = require("moonlift.pvm")

local function bind_context(T)
    local Back = T.MoonBack
    local Host = T.MoonHost
    assert(Back and Host, "moonlift.back_target_model(T) expects MoonBack/MoonHost in the context")

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
            -- Cranelift vector lowering is capped here to 128-bit shapes.
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

    return api
end

return bind_context