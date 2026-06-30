local asdl = require("lalin.asdl")

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.c_helpers ~= nil then return T._lalin_api_cache.c_helpers end

    local Core = T.LalinCore
    local C = T.LalinC

    local function node_key(x, seen)
        local tx = type(x)
        if tx ~= "table" then return tostring(x) end
        seen = seen or {}
        if seen[x] then return "<cycle>" end
        seen[x] = true
        local cls = asdl.classof(x)
        local parts = { class_name(x) }
        local fields = cls and asdl.fields(cls)
        if fields then
            for i = 1, #fields do
                local name = fields[i].name
                parts[#parts + 1] = name .. "=" .. node_key(x[name], seen)
            end
        else
            local keys = {}
            for k in pairs(x) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for i = 1, #keys do
                parts[#parts + 1] = tostring(keys[i]) .. "=" .. node_key(x[keys[i]], seen)
            end
        end
        seen[x] = nil
        return table.concat(parts, "{") .. "}"
    end

    local function scalar_suffix(s)
        if s == Core.ScalarBool then return "bool8" end
        if s == Core.ScalarI8 then return "i8" end
        if s == Core.ScalarI16 then return "i16" end
        if s == Core.ScalarI32 then return "i32" end
        if s == Core.ScalarI64 then return "i64" end
        if s == Core.ScalarU8 then return "u8" end
        if s == Core.ScalarU16 then return "u16" end
        if s == Core.ScalarU32 then return "u32" end
        if s == Core.ScalarU64 then return "u64" end
        if s == Core.ScalarF32 then return "f32" end
        if s == Core.ScalarF64 then return "f64" end
        if s == Core.ScalarRawPtr then return "ptr" end
        if s == Core.ScalarIndex then return "index" end
        if s == Core.ScalarVoid then return "void" end
        return "scalar"
    end

    local function type_suffix(ty)
        local cls = asdl.classof(ty)
        if ty == C.CBackendVoid or cls == C.CBackendVoid then return "void" end
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return "bool8" end
        if cls == C.CBackendScalar then return scalar_suffix(ty.scalar) end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "index" end
        if cls == C.CBackendDataPtr then return "ptr" end
        if cls == C.CBackendCodePtr then return "codeptr_" .. ty.sig.text:gsub("[^%w_]", "_") end
        if cls == C.CBackendNamed then return (ty.id.module_name .. "_" .. ty.id.spelling):gsub("[^%w_]", "_") end
        if cls == C.CBackendArray then return "arr" .. tostring(ty.count) .. "_" .. type_suffix(ty.elem) end
        if cls == C.CBackendSliceDescriptor then return "slice_" .. type_suffix(ty.elem) end
        if cls == C.CBackendByteSpanDescriptor or ty == C.CBackendByteSpanDescriptor then return "bytespan" end
        if cls == C.CBackendViewDescriptor then return "view_" .. type_suffix(ty.elem) end
        if cls == C.CBackendClosureDescriptor then return "closure_" .. ty.sig.text:gsub("[^%w_]", "_") end
        if cls == C.CBackendAbiHiddenOutPtr then return "out_" .. type_suffix(ty.result) end
        if cls == C.CBackendImportedCodePtr then return "c_codeptr_" .. ty.sig.text:gsub("[^%w_]", "_") end
        if cls == C.CBackendVector then return type_suffix(ty.elem) .. "x" .. tostring(ty.lanes) end
        return class_name(ty):gsub("[^%w_]", "_")
    end

    local function op_suffix(op)
        if op == Core.BinAdd then return "add" end
        if op == Core.BinSub then return "sub" end
        if op == Core.BinMul then return "mul" end
        if op == Core.BinDiv then return "div" end
        if op == Core.BinRem then return "rem" end
        if op == Core.BinBitAnd then return "and" end
        if op == Core.BinBitOr then return "or" end
        if op == Core.BinBitXor then return "xor" end
        if op == Core.BinShl then return "shl" end
        if op == Core.BinLShr then return "lshr" end
        if op == Core.BinAShr then return "ashr" end
        return class_name(op):gsub("^LalinCore%.Bin", ""):lower()
    end

    local function mode_suffix(x)
        local n = class_name(x):gsub("^LalinC%.CBackend", ""):gsub("^LalinCore%.Intrinsic", "")
        return n:gsub("[^%w_]", "_"):lower()
    end

    local function helper_key(spec)
        return node_key(spec)
    end

    local function helper_id(spec)
        local cls = asdl.classof(spec)
        if cls == C.CBackendHelperUnary then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. mode_suffix(spec.op))
        elseif cls == C.CBackendHelperBoolNormalize then
            return C.CBackendHelperId("ml_bool_normalize_" .. type_suffix(spec.ty))
        elseif cls == C.CBackendHelperCast then
            return C.CBackendHelperId("ml_cast_" .. mode_suffix(spec.op) .. "_" .. type_suffix(spec.from) .. "_to_" .. type_suffix(spec.to))
        elseif cls == C.CBackendHelperPtrOffset then
            return C.CBackendHelperId("ml_ptroff_" .. type_suffix(spec.pointee) .. "_" .. tostring(spec.elem_size) .. (spec.checked and "_checked" or ""))
        elseif cls == C.CBackendHelperIntBinary then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. op_suffix(spec.op) .. "_" .. mode_suffix(spec.overflow))
        elseif cls == C.CBackendHelperFloatBinary then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. op_suffix(spec.op))
        elseif cls == C.CBackendHelperDivRem then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. op_suffix(spec.op) .. "_" .. mode_suffix(spec.mode))
        elseif cls == C.CBackendHelperShift then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. op_suffix(spec.op) .. "_" .. mode_suffix(spec.mode))
        elseif cls == C.CBackendHelperIntrinsic then
            return C.CBackendHelperId("ml_" .. type_suffix(spec.ty) .. "_" .. mode_suffix(spec.intrinsic))
        elseif cls == C.CBackendHelperLoad then
            return C.CBackendHelperId("ml_load_" .. type_suffix(spec.access.ty) .. "_a" .. tostring(spec.access.align))
        elseif cls == C.CBackendHelperStore then
            return C.CBackendHelperId("ml_store_" .. type_suffix(spec.access.ty) .. "_a" .. tostring(spec.access.align))
        elseif cls == C.CBackendHelperAtomicLoad then
            return C.CBackendHelperId("ml_atomic_load_" .. type_suffix(spec.access.ty))
        elseif cls == C.CBackendHelperAtomicStore then
            return C.CBackendHelperId("ml_atomic_store_" .. type_suffix(spec.access.ty))
        elseif cls == C.CBackendHelperAtomicRmw then
            return C.CBackendHelperId("ml_atomic_" .. mode_suffix(spec.op) .. "_" .. type_suffix(spec.access.ty))
        elseif cls == C.CBackendHelperAtomicCas then
            return C.CBackendHelperId("ml_atomic_cas_" .. type_suffix(spec.access.ty))
        elseif cls == C.CBackendHelperAtomicFence then
            return C.CBackendHelperId("ml_atomic_fence_" .. mode_suffix(spec.ordering))
        elseif spec == C.CBackendHelperMemcpy then
            return C.CBackendHelperId("ml_memcpy")
        elseif cls == C.CBackendHelperTypedMemcpy then
            return C.CBackendHelperId("ml_memcpy_" .. type_suffix(spec.ty) .. "_" .. tostring(spec.size) .. "_a" .. tostring(spec.align))
        elseif spec == C.CBackendHelperMemset then
            return C.CBackendHelperId("ml_memset")
        elseif cls == C.CBackendHelperTypedMemset then
            return C.CBackendHelperId("ml_memset_" .. type_suffix(spec.ty) .. "_" .. tostring(spec.size) .. "_a" .. tostring(spec.align))
        elseif spec == C.CBackendHelperMemcmp then
            return C.CBackendHelperId("ml_memcmp")
        elseif cls == C.CBackendHelperLayoutAssert then
            return C.CBackendHelperId("ml_layout_assert_" .. type_suffix(C.CBackendNamed(spec.assertion.id)))
        elseif cls == C.CBackendHelperRequireFeature then
            return C.CBackendHelperId("ml_require_" .. mode_suffix(spec.feature))
        elseif spec == C.CBackendHelperTrap then
            return C.CBackendHelperId("ml_trap")
        end
        return C.CBackendHelperId("ml_helper_" .. helper_key(spec):gsub("[^%w_]", "_"))
    end

    local function register(ctx, spec)
        local id = helper_id(spec)
        if ctx then
            ctx.helpers_by_id = ctx.helpers_by_id or {}
            ctx.helper_order = ctx.helper_order or {}
            if ctx.helpers_by_id[id.text] == nil then
                local use = C.CBackendHelperUse(id, spec)
                ctx.helpers_by_id[id.text] = use
                ctx.helper_order[#ctx.helper_order + 1] = use
                if type(ctx.helpers) == "table" then ctx.helpers[id.text] = use end
            end
        end
        return id
    end

    local function helper_signature(use)
        local spec = (asdl.classof(use) == C.CBackendHelperUse) and use.spec or use
        local cls = asdl.classof(spec)
        local void = C.CBackendVoid
        local ptr = C.CBackendDataPtr(nil)
        local index = C.CBackendIndex
        if cls == C.CBackendHelperUnary then
            return { params = { spec.ty }, result = spec.ty }
        elseif cls == C.CBackendHelperBoolNormalize then
            return { params = { spec.ty }, result = C.CBackendBool8 }
        elseif cls == C.CBackendHelperCast then
            return { params = { spec.from }, result = spec.to }
        elseif cls == C.CBackendHelperPtrOffset then
            return { params = { ptr, index }, result = ptr }
        elseif cls == C.CBackendHelperIntBinary or cls == C.CBackendHelperFloatBinary or cls == C.CBackendHelperDivRem or cls == C.CBackendHelperShift then
            return { params = { spec.ty, spec.ty }, result = spec.ty }
        elseif cls == C.CBackendHelperIntrinsic then
            if spec.intrinsic == Core.IntrinsicTrap then return { params = {}, result = void } end
            if spec.intrinsic == Core.IntrinsicAssume then return { params = { C.CBackendBool8 }, result = void } end
            if spec.intrinsic == Core.IntrinsicFma then return { params = { spec.ty, spec.ty, spec.ty }, result = spec.ty } end
            if spec.intrinsic == Core.IntrinsicRotl or spec.intrinsic == Core.IntrinsicRotr then return { params = { spec.ty, spec.ty }, result = spec.ty } end
            return { params = { spec.ty }, result = spec.ty }
        elseif cls == C.CBackendHelperLoad then
            return { params = { ptr }, result = spec.access.ty }
        elseif cls == C.CBackendHelperStore then
            return { params = { ptr, spec.access.ty }, result = void }
        elseif cls == C.CBackendHelperAtomicLoad then
            return { params = { C.CBackendDataPtr(spec.access.ty) }, result = spec.access.ty }
        elseif cls == C.CBackendHelperAtomicStore then
            return { params = { C.CBackendDataPtr(spec.access.ty), spec.access.ty }, result = void }
        elseif cls == C.CBackendHelperAtomicRmw then
            return { params = { C.CBackendDataPtr(spec.access.ty), spec.access.ty }, result = spec.access.ty }
        elseif cls == C.CBackendHelperAtomicCas then
            return { params = { C.CBackendDataPtr(spec.access.ty), C.CBackendDataPtr(spec.access.ty), spec.access.ty }, result = spec.access.ty }
        elseif cls == C.CBackendHelperAtomicFence then
            return { params = {}, result = void }
        elseif spec == C.CBackendHelperMemcpy then
            return { params = { ptr, ptr, index }, result = void }
        elseif cls == C.CBackendHelperTypedMemcpy then
            return { params = { ptr, ptr }, result = void }
        elseif spec == C.CBackendHelperMemset then
            return { params = { ptr, C.CBackendScalar(Core.ScalarI32), index }, result = void }
        elseif cls == C.CBackendHelperTypedMemset then
            return { params = { ptr, C.CBackendScalar(Core.ScalarI32) }, result = void }
        elseif spec == C.CBackendHelperMemcmp then
            return { params = { ptr, ptr, index }, result = C.CBackendScalar(Core.ScalarI32) }
        elseif cls == C.CBackendHelperLayoutAssert or cls == C.CBackendHelperRequireFeature then
            return { params = {}, result = void }
        elseif spec == C.CBackendHelperTrap then
            return { params = {}, result = void }
        end
        error("c_helpers: unsupported helper spec " .. class_name(spec), 2)
    end

    local function scalar_c_name(s)
        if s == Core.ScalarBool then return "uint8_t" end
        if s == Core.ScalarI8 then return "int8_t" end
        if s == Core.ScalarI16 then return "int16_t" end
        if s == Core.ScalarI32 then return "int32_t" end
        if s == Core.ScalarI64 then return "int64_t" end
        if s == Core.ScalarU8 then return "uint8_t" end
        if s == Core.ScalarU16 then return "uint16_t" end
        if s == Core.ScalarU32 then return "uint32_t" end
        if s == Core.ScalarU64 then return "uint64_t" end
        if s == Core.ScalarF32 then return "float" end
        if s == Core.ScalarF64 then return "double" end
        if s == Core.ScalarRawPtr then return "void*" end
        if s == Core.ScalarIndex then return "intptr_t" end
        if s == Core.ScalarVoid then return "void" end
        return "intptr_t"
    end

    local function unsigned_c_name_for_type(ty)
        local cls = asdl.classof(ty)
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "uintptr_t" end
        if cls == C.CBackendScalar then
            local s = ty.scalar
            if s == Core.ScalarBool or s == Core.ScalarI8 or s == Core.ScalarU8 then return "uint8_t" end
            if s == Core.ScalarI16 or s == Core.ScalarU16 then return "uint16_t" end
            if s == Core.ScalarI32 or s == Core.ScalarU32 then return "uint32_t" end
            if s == Core.ScalarI64 or s == Core.ScalarU64 or s == Core.ScalarIndex or s == Core.ScalarRawPtr then return "uint64_t" end
        end
        return "uint64_t"
    end

    local function cbackend_scalar_is_signed(ty)
        return asdl.classof(ty) == C.CBackendScalar and (ty.scalar == Core.ScalarI8 or ty.scalar == Core.ScalarI16 or ty.scalar == Core.ScalarI32 or ty.scalar == Core.ScalarI64 or ty.scalar == Core.ScalarIndex)
    end

    local function fallback_emit_type(ty)
        local cls = asdl.classof(ty)
        if ty == C.CBackendVoid or cls == C.CBackendVoid then return "void" end
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return "uint8_t" end
        if cls == C.CBackendScalar then return scalar_c_name(ty.scalar) end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "intptr_t" end
        if cls == C.CBackendDataPtr then return "void*" end
        if cls == C.CBackendCodePtr then return "void (*)(void)" end
        if cls == C.CBackendNamed then return (ty.id.module_name .. "_" .. ty.id.spelling):gsub("[^%w_]", "_") end
        if cls == C.CBackendArray then return fallback_emit_type(ty.elem) end
        if cls == C.CBackendSliceDescriptor or cls == C.CBackendByteSpanDescriptor or cls == C.CBackendViewDescriptor or cls == C.CBackendClosureDescriptor then return "void*" end
        if cls == C.CBackendAbiHiddenOutPtr then return fallback_emit_type(C.CBackendDataPtr(ty.result)) end
        if cls == C.CBackendImportedCodePtr then return "void (*)(void)" end
        return "intptr_t"
    end

    local function binary_expr(op)
        if op == Core.BinAdd then return "a + b" end
        if op == Core.BinSub then return "a - b" end
        if op == Core.BinMul then return "a * b" end
        if op == Core.BinDiv then return "a / b" end
        if op == Core.BinRem then return "a % b" end
        if op == Core.BinBitAnd then return "a & b" end
        if op == Core.BinBitOr then return "a | b" end
        if op == Core.BinBitXor then return "a ^ b" end
        if op == Core.BinShl then return "a << b" end
        if op == Core.BinLShr or op == Core.BinAShr then return "a >> b" end
        return "a + b"
    end

    local function emit_helper(use, emit_type)
        emit_type = emit_type or fallback_emit_type
        local spec = (asdl.classof(use) == C.CBackendHelperUse) and use.spec or use
        local id = (asdl.classof(use) == C.CBackendHelperUse) and use.id or helper_id(spec)
        local sig = helper_signature(use)
        local ret = emit_type(sig.result)
        local params = {}
        for i, ty in ipairs(sig.params) do params[i] = emit_type(ty) .. " a" .. tostring(i) end
        local lines = { "static inline " .. ret .. " " .. id.text .. "(" .. table.concat(params, ", ") .. ") {" }
        local cls = asdl.classof(spec)
        local uret = unsigned_c_name_for_type((sig.result ~= C.CBackendVoid and sig.result) or (sig.params and sig.params[1]))
        if cls == C.CBackendHelperUnary then
            if spec.op == Core.UnaryNot then lines[#lines + 1] = "    return (" .. ret .. ")(!a1);"
            elseif spec.op == Core.UnaryBitNot then lines[#lines + 1] = "    return (" .. ret .. ")(~(" .. uret .. ")a1);"
            else lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1);" end
        elseif cls == C.CBackendHelperBoolNormalize then
            lines[#lines + 1] = "    return a1 ? 1u : 0u;"
        elseif cls == C.CBackendHelperCast then
            if spec.op == Core.MachineCastBitcast then
                lines[#lines + 1] = "    " .. ret .. " out;"
                lines[#lines + 1] = "    memset(&out, 0, sizeof(out));"
                lines[#lines + 1] = "    memcpy(&out, &a1, sizeof(out) < sizeof(a1) ? sizeof(out) : sizeof(a1));"
                lines[#lines + 1] = "    return out;"
            else
                lines[#lines + 1] = "    return (" .. ret .. ")a1;"
            end
        elseif cls == C.CBackendHelperPtrOffset then
            lines[#lines + 1] = "    return (void*)((unsigned char*)a1 + ((intptr_t)a2 * (intptr_t)" .. tostring(spec.elem_size) .. "));"
        elseif cls == C.CBackendHelperLoad then
            lines[#lines + 1] = "    " .. emit_type(spec.access.ty) .. " v;"
            lines[#lines + 1] = "    memcpy(&v, a1, sizeof(v));"
            lines[#lines + 1] = "    return v;"
        elseif cls == C.CBackendHelperStore then
            lines[#lines + 1] = "    memcpy(a1, &a2, sizeof(a2));"
        elseif cls == C.CBackendHelperAtomicLoad then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(spec.access.ty) .. ")* p = (_Atomic(" .. emit_type(spec.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    return atomic_load_explicit(p, memory_order_seq_cst);"
        elseif cls == C.CBackendHelperAtomicStore then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(spec.access.ty) .. ")* p = (_Atomic(" .. emit_type(spec.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    atomic_store_explicit(p, a2, memory_order_seq_cst);"
        elseif cls == C.CBackendHelperAtomicRmw then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(spec.access.ty) .. ")* p = (_Atomic(" .. emit_type(spec.access.ty) .. ")*)a1;"
            if spec.op == Core.AtomicRmwAdd then lines[#lines + 1] = "    return atomic_fetch_add_explicit(p, a2, memory_order_seq_cst);"
            elseif spec.op == Core.AtomicRmwSub then lines[#lines + 1] = "    return atomic_fetch_sub_explicit(p, a2, memory_order_seq_cst);"
            elseif spec.op == Core.AtomicRmwAnd then lines[#lines + 1] = "    return atomic_fetch_and_explicit(p, a2, memory_order_seq_cst);"
            elseif spec.op == Core.AtomicRmwOr then lines[#lines + 1] = "    return atomic_fetch_or_explicit(p, a2, memory_order_seq_cst);"
            elseif spec.op == Core.AtomicRmwXor then lines[#lines + 1] = "    return atomic_fetch_xor_explicit(p, a2, memory_order_seq_cst);"
            else lines[#lines + 1] = "    return atomic_exchange_explicit(p, a2, memory_order_seq_cst);" end
        elseif cls == C.CBackendHelperAtomicCas then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(spec.access.ty) .. ")* p = (_Atomic(" .. emit_type(spec.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    " .. emit_type(spec.access.ty) .. " old = *(" .. emit_type(spec.access.ty) .. "*)a2;"
            lines[#lines + 1] = "    atomic_compare_exchange_strong_explicit(p, (" .. emit_type(spec.access.ty) .. "*)a2, a3, memory_order_seq_cst, memory_order_seq_cst);"
            lines[#lines + 1] = "    return old;"
        elseif cls == C.CBackendHelperAtomicFence then
            lines[#lines + 1] = "    atomic_thread_fence(memory_order_seq_cst);"
        elseif spec == C.CBackendHelperMemcpy then
            lines[#lines + 1] = "    memcpy(a1, a2, (size_t)a3);"
        elseif cls == C.CBackendHelperTypedMemcpy then
            lines[#lines + 1] = "    memcpy(a1, a2, (size_t)" .. tostring(spec.size) .. ");"
        elseif spec == C.CBackendHelperMemset then
            lines[#lines + 1] = "    memset(a1, a2, (size_t)a3);"
        elseif cls == C.CBackendHelperTypedMemset then
            lines[#lines + 1] = "    memset(a1, a2, (size_t)" .. tostring(spec.size) .. ");"
        elseif spec == C.CBackendHelperMemcmp then
            lines[#lines + 1] = "    return memcmp(a1, a2, (size_t)a3);"
        elseif spec == C.CBackendHelperTrap or (cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicTrap) then
            lines[#lines + 1] = "    abort();"
        elseif cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicAssume then
            lines[#lines + 1] = "    if (!a1) abort();"
        elseif cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicSqrt then
            lines[#lines + 1] = "    return (" .. ret .. ")sqrt((double)a1);"
        elseif cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicAbs then
            lines[#lines + 1] = "    return a1 < 0 ? (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1) : a1;"
        elseif cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicFma then
            lines[#lines + 1] = "    return (" .. ret .. ")fma((double)a1, (double)a2, (double)a3);"
        elseif cls == C.CBackendHelperIntrinsic and (spec.intrinsic == Core.IntrinsicRotl or spec.intrinsic == Core.IntrinsicRotr) then
            lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & ((unsigned int)(sizeof(a1) * 8u - 1u));"
            if spec.intrinsic == Core.IntrinsicRotl then lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 << s) | ((" .. uret .. ")a1 >> ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));"
            else lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 >> s) | ((" .. uret .. ")a1 << ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));" end
        elseif cls == C.CBackendHelperIntrinsic and (spec.intrinsic == Core.IntrinsicPopcount or spec.intrinsic == Core.IntrinsicClz or spec.intrinsic == Core.IntrinsicCtz) then
            lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1; unsigned int n = 0;"
            if spec.intrinsic == Core.IntrinsicPopcount then lines[#lines + 1] = "    while (x) { n += (unsigned int)(x & 1u); x >>= 1; } return (" .. ret .. ")n;"
            elseif spec.intrinsic == Core.IntrinsicClz then lines[#lines + 1] = "    for (int i = (int)(sizeof(a1)*8u)-1; i >= 0; --i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;"
            else lines[#lines + 1] = "    for (unsigned int i = 0; i < sizeof(a1)*8u; ++i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;" end
        elseif cls == C.CBackendHelperIntrinsic and spec.intrinsic == Core.IntrinsicBswap then
            lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1, y = 0; for (unsigned int i = 0; i < sizeof(a1); ++i) { y = (y << 8) | (x & 255u); x >>= 8; } return (" .. ret .. ")y;"
        elseif cls == C.CBackendHelperIntrinsic and (spec.intrinsic == Core.IntrinsicFloor or spec.intrinsic == Core.IntrinsicCeil or spec.intrinsic == Core.IntrinsicTruncFloat or spec.intrinsic == Core.IntrinsicRound) then
            local fn = (spec.intrinsic == Core.IntrinsicFloor and "floor") or (spec.intrinsic == Core.IntrinsicCeil and "ceil") or (spec.intrinsic == Core.IntrinsicRound and "round") or "trunc"
            lines[#lines + 1] = "    return (" .. ret .. ")" .. fn .. "((double)a1);"
        elseif cls == C.CBackendHelperIntrinsic then
            lines[#lines + 1] = "    return a1;"
        elseif cls == C.CBackendHelperDivRem then
            lines[#lines + 1] = "    if (a2 == 0) abort();"
            if cbackend_scalar_is_signed(spec.ty) then
                lines[#lines + 1] = "    if (a2 == (" .. ret .. ")-1 && a1 == (" .. ret .. ")(((" .. uret .. ")1) << (sizeof(a1) * 8u - 1u))) abort();"
            end
            lines[#lines + 1] = "    return (" .. ret .. ")(" .. binary_expr(spec.op):gsub("a", "a1"):gsub("b", "a2") .. ");"
        elseif cls == C.CBackendHelperShift then
            lines[#lines + 1] = "    unsigned int width = (unsigned int)(sizeof(a1) * 8u);"
            lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & (width - 1u);"
            if spec.op == Core.BinShl then
                lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 << s);"
            elseif spec.op == Core.BinAShr and cbackend_scalar_is_signed(spec.ty) then
                lines[#lines + 1] = "    " .. uret .. " mask = (" .. uret .. ")~(" .. uret .. ")0;"
                lines[#lines + 1] = "    " .. uret .. " x = ((" .. uret .. ")a1) & mask;"
                lines[#lines + 1] = "    if (s != 0u && a1 < 0) x = (x >> s) | (mask << (width - s)); else x >>= s;"
                lines[#lines + 1] = "    return (" .. ret .. ")(x & mask);"
            else
                lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 >> s);"
            end
        elseif cls == C.CBackendHelperLayoutAssert then
            lines[#lines + 1] = "    typedef char ml_size_assert[(sizeof(" .. fallback_emit_type(C.CBackendNamed(spec.assertion.id)) .. ") == " .. tostring(spec.assertion.size) .. ") ? 1 : -1]; (void)sizeof(ml_size_assert);"
        elseif cls == C.CBackendHelperRequireFeature then
            lines[#lines + 1] = "    /* required target feature: " .. mode_suffix(spec.feature) .. " - " .. tostring(spec.reason):gsub("[\r\n]", " ") .. " */"
        elseif cls == C.CBackendHelperIntBinary then
            if spec.op == Core.BinAdd then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 + (" .. uret .. ")a2);"
            elseif spec.op == Core.BinSub then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 - (" .. uret .. ")a2);"
            elseif spec.op == Core.BinMul then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 * (" .. uret .. ")a2);"
            else lines[#lines + 1] = "    return (" .. ret .. ")(" .. binary_expr(spec.op):gsub("a", "a1"):gsub("b", "a2") .. ");" end
        elseif cls == C.CBackendHelperFloatBinary then
            if spec.op == Core.BinAdd then lines[#lines + 1] = "    return (" .. ret .. ")(a1 + a2);"
            elseif spec.op == Core.BinSub then lines[#lines + 1] = "    return (" .. ret .. ")(a1 - a2);"
            elseif spec.op == Core.BinMul then lines[#lines + 1] = "    return (" .. ret .. ")(a1 * a2);"
            elseif spec.op == Core.BinDiv then lines[#lines + 1] = "    return (" .. ret .. ")(a1 / a2);"
            else lines[#lines + 1] = "    return (" .. ret .. ")(a1 + a2);" end
        else
            lines[#lines + 1] = "    /* helper spec has no side effects */"
        end
        lines[#lines + 1] = "}"
        return lines
    end

    local api = {
        helper_key = helper_key,
        helper_id = helper_id,
        register = register,
        helper_signature = helper_signature,
        emit_helper = emit_helper,
        type_suffix = type_suffix,
    }
    T._lalin_api_cache.c_helpers = api
    return api
end

return bind_context
