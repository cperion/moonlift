local pvm = require("moonlift.pvm")

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_helpers ~= nil then return T._moonlift_api_cache.c_helpers end

    local Core = T.MoonCore
    local C = T.MoonC

    local function node_key(x, seen)
        local tx = type(x)
        if tx ~= "table" then return tostring(x) end
        seen = seen or {}
        if seen[x] then return "<cycle>" end
        seen[x] = true
        local cls = pvm.classof(x)
        local parts = { class_name(x) }
        if cls and cls.__fields then
            for i = 1, #cls.__fields do
                local name = cls.__fields[i].name
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
        local cls = pvm.classof(ty)
        if ty == C.CBackendVoid or cls == C.CBackendVoid then return "void" end
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return "bool8" end
        if cls == C.CBackendScalar then return scalar_suffix(ty.scalar) end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "index" end
        if cls == C.CBackendDataPtr then return "ptr" end
        if cls == C.CBackendCodePtr then return "codeptr_" .. ty.sig.text:gsub("[^%w_]", "_") end
        if cls == C.CBackendNamed then return (ty.id.module_name .. "_" .. ty.id.spelling):gsub("[^%w_]", "_") end
        if cls == C.CBackendArray then return "arr" .. tostring(ty.count) .. "_" .. type_suffix(ty.elem) end
        if cls == C.CBackendSliceDescriptor then return "slice_" .. type_suffix(ty.elem) end
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
        return class_name(op):gsub("^MoonCore%.Bin", ""):lower()
    end

    local function mode_suffix(x)
        local n = class_name(x):gsub("^MoonC%.CBackend", ""):gsub("^MoonCore%.Intrinsic", "")
        return n:gsub("[^%w_]", "_"):lower()
    end

    local function helper_key(kind)
        return node_key(kind)
    end

    local function helper_id(kind)
        local cls = pvm.classof(kind)
        if cls == C.CBackendHelperUnary then
            return C.CBackendHelperId("ml_" .. type_suffix(kind.ty) .. "_" .. mode_suffix(kind.op))
        elseif cls == C.CBackendHelperBoolNormalize then
            return C.CBackendHelperId("ml_bool_normalize_" .. type_suffix(kind.ty))
        elseif cls == C.CBackendHelperCast then
            return C.CBackendHelperId("ml_cast_" .. mode_suffix(kind.op) .. "_" .. type_suffix(kind.from) .. "_to_" .. type_suffix(kind.to))
        elseif cls == C.CBackendHelperPtrOffset then
            return C.CBackendHelperId("ml_ptroff_" .. type_suffix(kind.pointee) .. "_" .. tostring(kind.elem_size) .. (kind.checked and "_checked" or ""))
        elseif cls == C.CBackendHelperIntBinary then
            return C.CBackendHelperId("ml_" .. type_suffix(kind.ty) .. "_" .. op_suffix(kind.op) .. "_" .. mode_suffix(kind.overflow))
        elseif cls == C.CBackendHelperDivRem then
            return C.CBackendHelperId("ml_" .. type_suffix(kind.ty) .. "_" .. op_suffix(kind.op) .. "_" .. mode_suffix(kind.mode))
        elseif cls == C.CBackendHelperShift then
            return C.CBackendHelperId("ml_" .. type_suffix(kind.ty) .. "_" .. op_suffix(kind.op) .. "_" .. mode_suffix(kind.mode))
        elseif cls == C.CBackendHelperIntrinsic then
            return C.CBackendHelperId("ml_" .. type_suffix(kind.ty) .. "_" .. mode_suffix(kind.intrinsic))
        elseif cls == C.CBackendHelperLoad then
            return C.CBackendHelperId("ml_load_" .. type_suffix(kind.access.ty) .. "_a" .. tostring(kind.access.align))
        elseif cls == C.CBackendHelperStore then
            return C.CBackendHelperId("ml_store_" .. type_suffix(kind.access.ty) .. "_a" .. tostring(kind.access.align))
        elseif cls == C.CBackendHelperAtomicLoad then
            return C.CBackendHelperId("ml_atomic_load_" .. type_suffix(kind.access.ty))
        elseif cls == C.CBackendHelperAtomicStore then
            return C.CBackendHelperId("ml_atomic_store_" .. type_suffix(kind.access.ty))
        elseif cls == C.CBackendHelperAtomicRmw then
            return C.CBackendHelperId("ml_atomic_" .. mode_suffix(kind.op) .. "_" .. type_suffix(kind.access.ty))
        elseif cls == C.CBackendHelperAtomicCas then
            return C.CBackendHelperId("ml_atomic_cas_" .. type_suffix(kind.access.ty))
        elseif cls == C.CBackendHelperAtomicFence then
            return C.CBackendHelperId("ml_atomic_fence_" .. mode_suffix(kind.ordering))
        elseif kind == C.CBackendHelperMemcpy then
            return C.CBackendHelperId("ml_memcpy")
        elseif cls == C.CBackendHelperTypedMemcpy then
            return C.CBackendHelperId("ml_memcpy_" .. type_suffix(kind.ty) .. "_" .. tostring(kind.size) .. "_a" .. tostring(kind.align))
        elseif kind == C.CBackendHelperMemset then
            return C.CBackendHelperId("ml_memset")
        elseif cls == C.CBackendHelperTypedMemset then
            return C.CBackendHelperId("ml_memset_" .. type_suffix(kind.ty) .. "_" .. tostring(kind.size) .. "_a" .. tostring(kind.align))
        elseif kind == C.CBackendHelperMemcmp then
            return C.CBackendHelperId("ml_memcmp")
        elseif cls == C.CBackendHelperLayoutAssert then
            return C.CBackendHelperId("ml_layout_assert_" .. type_suffix(C.CBackendNamed(kind.assertion.id)))
        elseif cls == C.CBackendHelperRequireFeature then
            return C.CBackendHelperId("ml_require_" .. mode_suffix(kind.feature))
        elseif kind == C.CBackendHelperTrap then
            return C.CBackendHelperId("ml_trap")
        end
        return C.CBackendHelperId("ml_helper_" .. helper_key(kind):gsub("[^%w_]", "_"))
    end

    local function register(ctx, kind)
        local id = helper_id(kind)
        if ctx then
            ctx.helpers_by_id = ctx.helpers_by_id or {}
            ctx.helper_order = ctx.helper_order or {}
            if ctx.helpers_by_id[id.text] == nil then
                local use = C.CBackendHelperUse(id, kind)
                ctx.helpers_by_id[id.text] = use
                ctx.helper_order[#ctx.helper_order + 1] = use
                if type(ctx.helpers) == "table" then ctx.helpers[id.text] = use end
            end
        end
        return id
    end

    local function helper_signature(use)
        local kind = (pvm.classof(use) == C.CBackendHelperUse) and use.kind or use
        local cls = pvm.classof(kind)
        local void = C.CBackendVoid
        local ptr = C.CBackendDataPtr(nil)
        local index = C.CBackendIndex
        if cls == C.CBackendHelperUnary then
            return { params = { kind.ty }, result = kind.ty }
        elseif cls == C.CBackendHelperBoolNormalize then
            return { params = { kind.ty }, result = C.CBackendBool8 }
        elseif cls == C.CBackendHelperCast then
            return { params = { kind.from }, result = kind.to }
        elseif cls == C.CBackendHelperPtrOffset then
            return { params = { ptr, index }, result = ptr }
        elseif cls == C.CBackendHelperIntBinary or cls == C.CBackendHelperDivRem or cls == C.CBackendHelperShift then
            return { params = { kind.ty, kind.ty }, result = kind.ty }
        elseif cls == C.CBackendHelperIntrinsic then
            if kind.intrinsic == Core.IntrinsicTrap then return { params = {}, result = void } end
            if kind.intrinsic == Core.IntrinsicAssume then return { params = { C.CBackendBool8 }, result = void } end
            if kind.intrinsic == Core.IntrinsicFma then return { params = { kind.ty, kind.ty, kind.ty }, result = kind.ty } end
            if kind.intrinsic == Core.IntrinsicRotl or kind.intrinsic == Core.IntrinsicRotr then return { params = { kind.ty, kind.ty }, result = kind.ty } end
            return { params = { kind.ty }, result = kind.ty }
        elseif cls == C.CBackendHelperLoad then
            return { params = { ptr }, result = kind.access.ty }
        elseif cls == C.CBackendHelperStore then
            return { params = { ptr, kind.access.ty }, result = void }
        elseif cls == C.CBackendHelperAtomicLoad then
            return { params = { C.CBackendDataPtr(kind.access.ty) }, result = kind.access.ty }
        elseif cls == C.CBackendHelperAtomicStore then
            return { params = { C.CBackendDataPtr(kind.access.ty), kind.access.ty }, result = void }
        elseif cls == C.CBackendHelperAtomicRmw then
            return { params = { C.CBackendDataPtr(kind.access.ty), kind.access.ty }, result = kind.access.ty }
        elseif cls == C.CBackendHelperAtomicCas then
            return { params = { C.CBackendDataPtr(kind.access.ty), C.CBackendDataPtr(kind.access.ty), kind.access.ty }, result = kind.access.ty }
        elseif cls == C.CBackendHelperAtomicFence then
            return { params = {}, result = void }
        elseif kind == C.CBackendHelperMemcpy then
            return { params = { ptr, ptr, index }, result = void }
        elseif cls == C.CBackendHelperTypedMemcpy then
            return { params = { ptr, ptr }, result = void }
        elseif kind == C.CBackendHelperMemset then
            return { params = { ptr, C.CBackendScalar(Core.ScalarI32), index }, result = void }
        elseif cls == C.CBackendHelperTypedMemset then
            return { params = { ptr, C.CBackendScalar(Core.ScalarI32) }, result = void }
        elseif kind == C.CBackendHelperMemcmp then
            return { params = { ptr, ptr, index }, result = C.CBackendScalar(Core.ScalarI32) }
        elseif cls == C.CBackendHelperLayoutAssert or cls == C.CBackendHelperRequireFeature then
            return { params = {}, result = void }
        elseif kind == C.CBackendHelperTrap then
            return { params = {}, result = void }
        end
        error("c_helpers: unsupported helper kind " .. class_name(kind), 2)
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
        local cls = pvm.classof(ty)
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
        return pvm.classof(ty) == C.CBackendScalar and (ty.scalar == Core.ScalarI8 or ty.scalar == Core.ScalarI16 or ty.scalar == Core.ScalarI32 or ty.scalar == Core.ScalarI64 or ty.scalar == Core.ScalarIndex)
    end

    local function fallback_emit_type(ty)
        local cls = pvm.classof(ty)
        if ty == C.CBackendVoid or cls == C.CBackendVoid then return "void" end
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return "uint8_t" end
        if cls == C.CBackendScalar then return scalar_c_name(ty.scalar) end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "intptr_t" end
        if cls == C.CBackendDataPtr then return "void*" end
        if cls == C.CBackendCodePtr then return "void (*)(void)" end
        if cls == C.CBackendNamed then return (ty.id.module_name .. "_" .. ty.id.spelling):gsub("[^%w_]", "_") end
        if cls == C.CBackendArray then return fallback_emit_type(ty.elem) end
        if cls == C.CBackendSliceDescriptor or cls == C.CBackendViewDescriptor or cls == C.CBackendClosureDescriptor then return "void*" end
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
        local kind = (pvm.classof(use) == C.CBackendHelperUse) and use.kind or use
        local id = (pvm.classof(use) == C.CBackendHelperUse) and use.id or helper_id(kind)
        local sig = helper_signature(use)
        local ret = emit_type(sig.result)
        local params = {}
        for i, ty in ipairs(sig.params) do params[i] = emit_type(ty) .. " a" .. tostring(i) end
        local lines = { "static inline " .. ret .. " " .. id.text .. "(" .. table.concat(params, ", ") .. ") {" }
        local cls = pvm.classof(kind)
        local uret = unsigned_c_name_for_type((sig.result ~= C.CBackendVoid and sig.result) or (sig.params and sig.params[1]))
        if cls == C.CBackendHelperUnary then
            if kind.op == Core.UnaryNot then lines[#lines + 1] = "    return (" .. ret .. ")(!a1);"
            elseif kind.op == Core.UnaryBitNot then lines[#lines + 1] = "    return (" .. ret .. ")(~(" .. uret .. ")a1);"
            else lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1);" end
        elseif cls == C.CBackendHelperBoolNormalize then
            lines[#lines + 1] = "    return a1 ? 1u : 0u;"
        elseif cls == C.CBackendHelperCast then
            if kind.op == Core.MachineCastBitcast then
                lines[#lines + 1] = "    " .. ret .. " out;"
                lines[#lines + 1] = "    memset(&out, 0, sizeof(out));"
                lines[#lines + 1] = "    memcpy(&out, &a1, sizeof(out) < sizeof(a1) ? sizeof(out) : sizeof(a1));"
                lines[#lines + 1] = "    return out;"
            else
                lines[#lines + 1] = "    return (" .. ret .. ")a1;"
            end
        elseif cls == C.CBackendHelperPtrOffset then
            lines[#lines + 1] = "    return (void*)((unsigned char*)a1 + ((intptr_t)a2 * (intptr_t)" .. tostring(kind.elem_size) .. "));"
        elseif cls == C.CBackendHelperLoad then
            lines[#lines + 1] = "    " .. emit_type(kind.access.ty) .. " v;"
            lines[#lines + 1] = "    memcpy(&v, a1, sizeof(v));"
            lines[#lines + 1] = "    return v;"
        elseif cls == C.CBackendHelperStore then
            lines[#lines + 1] = "    memcpy(a1, &a2, sizeof(a2));"
        elseif cls == C.CBackendHelperAtomicLoad then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(kind.access.ty) .. ")* p = (_Atomic(" .. emit_type(kind.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    return atomic_load_explicit(p, memory_order_seq_cst);"
        elseif cls == C.CBackendHelperAtomicStore then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(kind.access.ty) .. ")* p = (_Atomic(" .. emit_type(kind.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    atomic_store_explicit(p, a2, memory_order_seq_cst);"
        elseif cls == C.CBackendHelperAtomicRmw then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(kind.access.ty) .. ")* p = (_Atomic(" .. emit_type(kind.access.ty) .. ")*)a1;"
            if kind.op == Core.AtomicRmwAdd then lines[#lines + 1] = "    return atomic_fetch_add_explicit(p, a2, memory_order_seq_cst);"
            elseif kind.op == Core.AtomicRmwSub then lines[#lines + 1] = "    return atomic_fetch_sub_explicit(p, a2, memory_order_seq_cst);"
            elseif kind.op == Core.AtomicRmwAnd then lines[#lines + 1] = "    return atomic_fetch_and_explicit(p, a2, memory_order_seq_cst);"
            elseif kind.op == Core.AtomicRmwOr then lines[#lines + 1] = "    return atomic_fetch_or_explicit(p, a2, memory_order_seq_cst);"
            elseif kind.op == Core.AtomicRmwXor then lines[#lines + 1] = "    return atomic_fetch_xor_explicit(p, a2, memory_order_seq_cst);"
            else lines[#lines + 1] = "    return atomic_exchange_explicit(p, a2, memory_order_seq_cst);" end
        elseif cls == C.CBackendHelperAtomicCas then
            lines[#lines + 1] = "    _Atomic(" .. emit_type(kind.access.ty) .. ")* p = (_Atomic(" .. emit_type(kind.access.ty) .. ")*)a1;"
            lines[#lines + 1] = "    " .. emit_type(kind.access.ty) .. " old = *(" .. emit_type(kind.access.ty) .. "*)a2;"
            lines[#lines + 1] = "    atomic_compare_exchange_strong_explicit(p, (" .. emit_type(kind.access.ty) .. "*)a2, a3, memory_order_seq_cst, memory_order_seq_cst);"
            lines[#lines + 1] = "    return old;"
        elseif cls == C.CBackendHelperAtomicFence then
            lines[#lines + 1] = "    atomic_thread_fence(memory_order_seq_cst);"
        elseif kind == C.CBackendHelperMemcpy then
            lines[#lines + 1] = "    memcpy(a1, a2, (size_t)a3);"
        elseif cls == C.CBackendHelperTypedMemcpy then
            lines[#lines + 1] = "    memcpy(a1, a2, (size_t)" .. tostring(kind.size) .. ");"
        elseif kind == C.CBackendHelperMemset then
            lines[#lines + 1] = "    memset(a1, a2, (size_t)a3);"
        elseif cls == C.CBackendHelperTypedMemset then
            lines[#lines + 1] = "    memset(a1, a2, (size_t)" .. tostring(kind.size) .. ");"
        elseif kind == C.CBackendHelperMemcmp then
            lines[#lines + 1] = "    return memcmp(a1, a2, (size_t)a3);"
        elseif kind == C.CBackendHelperTrap or (cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicTrap) then
            lines[#lines + 1] = "    abort();"
        elseif cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicAssume then
            lines[#lines + 1] = "    if (!a1) abort();"
        elseif cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicSqrt then
            lines[#lines + 1] = "    return (" .. ret .. ")sqrt((double)a1);"
        elseif cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicAbs then
            lines[#lines + 1] = "    return a1 < 0 ? (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1) : a1;"
        elseif cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicFma then
            lines[#lines + 1] = "    return (" .. ret .. ")fma((double)a1, (double)a2, (double)a3);"
        elseif cls == C.CBackendHelperIntrinsic and (kind.intrinsic == Core.IntrinsicRotl or kind.intrinsic == Core.IntrinsicRotr) then
            lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & ((unsigned int)(sizeof(a1) * 8u - 1u));"
            if kind.intrinsic == Core.IntrinsicRotl then lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 << s) | ((" .. uret .. ")a1 >> ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));"
            else lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 >> s) | ((" .. uret .. ")a1 << ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));" end
        elseif cls == C.CBackendHelperIntrinsic and (kind.intrinsic == Core.IntrinsicPopcount or kind.intrinsic == Core.IntrinsicClz or kind.intrinsic == Core.IntrinsicCtz) then
            lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1; unsigned int n = 0;"
            if kind.intrinsic == Core.IntrinsicPopcount then lines[#lines + 1] = "    while (x) { n += (unsigned int)(x & 1u); x >>= 1; } return (" .. ret .. ")n;"
            elseif kind.intrinsic == Core.IntrinsicClz then lines[#lines + 1] = "    for (int i = (int)(sizeof(a1)*8u)-1; i >= 0; --i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;"
            else lines[#lines + 1] = "    for (unsigned int i = 0; i < sizeof(a1)*8u; ++i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;" end
        elseif cls == C.CBackendHelperIntrinsic and kind.intrinsic == Core.IntrinsicBswap then
            lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1, y = 0; for (unsigned int i = 0; i < sizeof(a1); ++i) { y = (y << 8) | (x & 255u); x >>= 8; } return (" .. ret .. ")y;"
        elseif cls == C.CBackendHelperIntrinsic and (kind.intrinsic == Core.IntrinsicFloor or kind.intrinsic == Core.IntrinsicCeil or kind.intrinsic == Core.IntrinsicTruncFloat or kind.intrinsic == Core.IntrinsicRound) then
            local fn = (kind.intrinsic == Core.IntrinsicFloor and "floor") or (kind.intrinsic == Core.IntrinsicCeil and "ceil") or (kind.intrinsic == Core.IntrinsicRound and "round") or "trunc"
            lines[#lines + 1] = "    return (" .. ret .. ")" .. fn .. "((double)a1);"
        elseif cls == C.CBackendHelperIntrinsic then
            lines[#lines + 1] = "    return a1;"
        elseif cls == C.CBackendHelperDivRem then
            lines[#lines + 1] = "    if (a2 == 0) abort();"
            if cbackend_scalar_is_signed(kind.ty) then
                lines[#lines + 1] = "    if (a2 == (" .. ret .. ")-1 && a1 == (" .. ret .. ")(((" .. uret .. ")1) << (sizeof(a1) * 8u - 1u))) abort();"
            end
            lines[#lines + 1] = "    return (" .. ret .. ")(" .. binary_expr(kind.op):gsub("a", "a1"):gsub("b", "a2") .. ");"
        elseif cls == C.CBackendHelperShift then
            lines[#lines + 1] = "    unsigned int width = (unsigned int)(sizeof(a1) * 8u);"
            lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & (width - 1u);"
            if kind.op == Core.BinShl then
                lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 << s);"
            elseif kind.op == Core.BinAShr and cbackend_scalar_is_signed(kind.ty) then
                lines[#lines + 1] = "    " .. uret .. " mask = (" .. uret .. ")~(" .. uret .. ")0;"
                lines[#lines + 1] = "    " .. uret .. " x = ((" .. uret .. ")a1) & mask;"
                lines[#lines + 1] = "    if (s != 0u && a1 < 0) x = (x >> s) | (mask << (width - s)); else x >>= s;"
                lines[#lines + 1] = "    return (" .. ret .. ")(x & mask);"
            else
                lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 >> s);"
            end
        elseif cls == C.CBackendHelperLayoutAssert then
            lines[#lines + 1] = "    typedef char ml_size_assert[(sizeof(" .. fallback_emit_type(C.CBackendNamed(kind.assertion.id)) .. ") == " .. tostring(kind.assertion.size) .. ") ? 1 : -1]; (void)sizeof(ml_size_assert);"
        elseif cls == C.CBackendHelperRequireFeature then
            lines[#lines + 1] = "    /* required target feature: " .. mode_suffix(kind.feature) .. " - " .. tostring(kind.reason):gsub("[\r\n]", " ") .. " */"
        elseif cls == C.CBackendHelperIntBinary then
            if kind.op == Core.BinAdd then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 + (" .. uret .. ")a2);"
            elseif kind.op == Core.BinSub then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 - (" .. uret .. ")a2);"
            elseif kind.op == Core.BinMul then lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 * (" .. uret .. ")a2);"
            else lines[#lines + 1] = "    return (" .. ret .. ")(" .. binary_expr(kind.op):gsub("a", "a1"):gsub("b", "a2") .. ");" end
        else
            lines[#lines + 1] = "    /* helper kind has no side effects */"
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
    T._moonlift_api_cache.c_helpers = api
    return api
end

return bind_context