local pvm = require("moonlift.pvm")

local function sanitize(text)
    text = tostring(text or "x"):gsub("[^%w_]", "_")
    if text == "" then text = "x" end
    if text:match("^%d") then text = "_" .. text end
    return text
end

local function class_name(value)
    local cls = pvm.classof(value) or value
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_ctype ~= nil then return T._moonlift_api_cache.luajit_ctype end

    local Code = T.MoonCode
    local Back = T.MoonBack
    local LJ = T.MoonLuaJIT

    local api = {}

    local function ensure_ordered_map(ctx, map_name, order_name)
        if ctx == nil then return nil, nil end
        ctx[map_name] = ctx[map_name] or {}
        ctx[order_name] = ctx[order_name] or {}
        return ctx[map_name], ctx[order_name]
    end

    local function remember(ctx, map_name, order_name, key, value)
        local map, order = ensure_ordered_map(ctx, map_name, order_name)
        if map == nil then return value end
        if map[key] == nil then
            map[key] = value
            order[#order + 1] = value
        end
        return map[key]
    end

    local function code_type_key(ty)
        if ty == nil then return "opaque" end
        if ty == Code.CodeTyVoid then return "void" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        if ty == Code.CodeTyIndex then return "index" end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if cls == Code.CodeTyDataPtr then return "ptr_" .. code_type_key(ty.pointee) end
        if cls == Code.CodeTyCodePtr then return "codeptr_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyNamed then return "named_" .. sanitize(ty.module_name) .. "_" .. sanitize(ty.type_name) end
        if cls == Code.CodeTyArray then return "array_" .. tostring(ty.count) .. "_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTySlice then return "slice_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyView then return "view_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyHandle then return "handle_" .. code_type_key(ty.repr) end
        if cls == Code.CodeTyLease then return "lease_" .. code_type_key(ty.base) end
        if cls == Code.CodeTyClosure then return "closure_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyImportedC then return "imported_c_" .. sanitize(ty.id.module_name) .. "_" .. sanitize(ty.id.spelling) end
        if cls == Code.CodeTyImportedCFuncPtr then return "imported_cfn_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyVector then return "vec_" .. tostring(ty.lanes) .. "_" .. code_type_key(ty.elem) end
        error("luajit_ctype: unsupported CodeType key for " .. class_name(ty), 2)
    end

    local function scalar_spelling(scalar)
        if scalar == Back.BackVoid then return "void" end
        if scalar == Back.BackBool then return "uint8_t" end
        if scalar == Back.BackI8 then return "int8_t" end
        if scalar == Back.BackI16 then return "int16_t" end
        if scalar == Back.BackI32 then return "int32_t" end
        if scalar == Back.BackI64 then return "int64_t" end
        if scalar == Back.BackU8 then return "uint8_t" end
        if scalar == Back.BackU16 then return "uint16_t" end
        if scalar == Back.BackU32 then return "uint32_t" end
        if scalar == Back.BackU64 then return "uint64_t" end
        if scalar == Back.BackF32 then return "float" end
        if scalar == Back.BackF64 then return "double" end
        if scalar == Back.BackIndex then return "intptr_t" end
        if scalar == Back.BackPtr then return "void*" end
        error("luajit_ctype: unsupported BackScalar " .. class_name(scalar), 2)
    end

    local function scalar_ctype(scalar)
        if scalar == Back.BackVoid then return LJ.LJCTypeVoid end
        if scalar == Back.BackPtr then return LJ.LJCTypePointer(nil, true) end
        return LJ.LJCTypeScalar(scalar, scalar_spelling(scalar))
    end

    local function scalar_register_rep(scalar)
        if scalar == Back.BackVoid then return LJ.LJRegVoid end
        if scalar == Back.BackBool then return LJ.LJRegLuaBoolean end
        if scalar == Back.BackI8 then return LJ.LJRegTraceInt32(8, Code.CodeSigned) end
        if scalar == Back.BackI16 then return LJ.LJRegTraceInt32(16, Code.CodeSigned) end
        if scalar == Back.BackI32 then return LJ.LJRegTraceInt32(32, Code.CodeSigned) end
        if scalar == Back.BackU8 then return LJ.LJRegTraceInt32(8, Code.CodeUnsigned) end
        if scalar == Back.BackU16 then return LJ.LJRegTraceInt32(16, Code.CodeUnsigned) end
        if scalar == Back.BackU32 then return LJ.LJRegTraceInt32(32, Code.CodeUnsigned) end
        if scalar == Back.BackI64 or scalar == Back.BackU64 or scalar == Back.BackPtr then
            return LJ.LJRegCData(scalar_ctype(scalar))
        end
        return LJ.LJRegLuaNumber
    end

    local function code_scalar(ty)
        if ty == Code.CodeTyVoid then return Back.BackVoid end
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64 end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        end
        return nil
    end

    local ctype_for_code_type
    local physical_type

    local function ctype_spelling(ctype, ctx)
        local cls = pvm.classof(ctype)
        if ctype == LJ.LJCTypeVoid then return "void" end
        if ctype == LJ.LJCTypeBool then return "bool" end
        if cls == LJ.LJCTypeScalar then return ctype.spelling end
        if cls == LJ.LJCTypePointer then
            local base = ctype.pointee and ctype_spelling(ctype.pointee, ctx) or "void"
            return base .. "*"
        end
        if cls == LJ.LJCTypeArray then return ctype_spelling(ctype.elem, ctx) .. "[" .. tostring(ctype.count) .. "]" end
        if cls == LJ.LJCTypeNamed then return ctype.spelling end
        if cls == LJ.LJCTypeFuncPtr then
            local sig = ctx and ctx.lj_sigs and ctx.lj_sigs[ctype.sig.text]
            return sig and sig.c_sig or "void (*)(void)"
        end
        error("luajit_ctype: cannot spell C type " .. class_name(ctype), 2)
    end

    local function type_id(prefix, ty)
        return LJ.LJTypeId("lj_" .. prefix .. "_" .. code_type_key(ty))
    end

    local function named_ctype(id, spelling)
        return LJ.LJCTypeNamed(id, spelling)
    end

    local function remember_decl(ctx, decl)
        local key = pvm.classof(decl) == LJ.LJCDeclRaw and ("raw:" .. decl.source) or decl.id.text
        return remember(ctx, "lj_cdefs", "lj_cdef_order", key, decl)
    end

    local function descriptor_struct(ctx, prefix, ty, fields)
        local id = type_id(prefix, ty)
        local spelling = "struct " .. id.text
        remember_decl(ctx, LJ.LJCDeclStruct(id, spelling, fields, nil, nil))
        return named_ctype(id, spelling)
    end

    local function scalar_physical(semantic, scalar)
        local cty = scalar_ctype(scalar)
        return LJ.LJPhysicalType(semantic, scalar_register_rep(scalar), cty, cty)
    end

    local function ensure_lj_sig(ctx, sig_id)
        local id = LJ.LJFuncSigId(sig_id.text)
        local code_sig = ctx and ctx.code_sigs and ctx.code_sigs[sig_id.text]
        if code_sig ~= nil and ctx ~= nil then
            local sigs, order = ensure_ordered_map(ctx, "lj_sigs", "lj_sig_order")
            if sigs[id.text] == nil then
                local params = {}
                for i = 1, #(code_sig.params or {}) do params[i] = physical_type(code_sig.params[i], ctx) end
                local results = code_sig.results or {}
                local result = nil
                if #results == 1 and results[1] ~= Code.CodeTyVoid then
                    result = physical_type(results[1], ctx)
                elseif #results > 1 then
                    error("luajit_ctype: LuaJIT ABI cannot spell multi-result CodeSig " .. sig_id.text, 3)
                end
                local pieces = {}
                for i = 1, #params do pieces[i] = ctype_spelling(params[i].abi, ctx) end
                local result_spelling = result and ctype_spelling(result.abi, ctx) or "void"
                local sig = LJ.LJFuncSig(id, params, result, result_spelling .. " (*)(" .. table.concat(pieces, ", ") .. ")")
                sigs[id.text] = sig
                order[#order + 1] = sig
            end
        end
        return id
    end

    ctype_for_code_type = function(ty, ctx)
        local scalar = code_scalar(ty)
        if scalar ~= nil then return scalar_ctype(scalar) end

        local cls = pvm.classof(ty)
        if cls == Code.CodeTyDataPtr then
            return LJ.LJCTypePointer(ty.pointee and ctype_for_code_type(ty.pointee, ctx) or nil, true)
        end
        if cls == Code.CodeTyCodePtr then
            return LJ.LJCTypeFuncPtr(ensure_lj_sig(ctx, ty.sig))
        end
        if cls == Code.CodeTyNamed then
            return named_ctype(LJ.LJTypeId("lj_named_" .. sanitize(ty.module_name) .. "_" .. sanitize(ty.type_name)), sanitize(ty.module_name) .. "_" .. sanitize(ty.type_name))
        end
        if cls == Code.CodeTyArray then
            return LJ.LJCTypeArray(ctype_for_code_type(ty.elem, ctx), ty.count)
        end
        if cls == Code.CodeTySlice then
            local elem = physical_type(ty.elem, ctx)
            return descriptor_struct(ctx, "slice", ty, {
                LJ.LJCField("data", LJ.LJCTypePointer(elem.storage, true), nil, nil, nil),
                LJ.LJCField("len", scalar_ctype(Back.BackIndex), nil, nil, nil),
            })
        end
        if cls == Code.CodeTyView then
            local elem = physical_type(ty.elem, ctx)
            return descriptor_struct(ctx, "view", ty, {
                LJ.LJCField("data", LJ.LJCTypePointer(elem.storage, true), nil, nil, nil),
                LJ.LJCField("len", scalar_ctype(Back.BackIndex), nil, nil, nil),
                LJ.LJCField("stride", scalar_ctype(Back.BackIndex), nil, nil, nil),
            })
        end
        if cls == Code.CodeTyHandle then return ctype_for_code_type(ty.repr, ctx) end
        if cls == Code.CodeTyLease then return ctype_for_code_type(ty.base, ctx) end
        if cls == Code.CodeTyClosure then
            return descriptor_struct(ctx, "closure", ty, {
                LJ.LJCField("fn", LJ.LJCTypeFuncPtr(ensure_lj_sig(ctx, ty.sig)), nil, nil, nil),
                LJ.LJCField("ctx", LJ.LJCTypePointer(nil, true), nil, nil, nil),
            })
        end
        if cls == Code.CodeTyImportedC then
            return named_ctype(LJ.LJTypeId("lj_imported_" .. sanitize(ty.id.module_name) .. "_" .. sanitize(ty.id.spelling)), ty.id.spelling)
        end
        if cls == Code.CodeTyImportedCFuncPtr then
            return LJ.LJCTypeFuncPtr(LJ.LJFuncSigId(ty.sig.text))
        end
        if cls == Code.CodeTyVector then
            return LJ.LJCTypeArray(ctype_for_code_type(ty.elem, ctx), ty.lanes)
        end
        error("luajit_ctype: unsupported CodeType for C storage " .. class_name(ty), 2)
    end

    physical_type = function(ty, ctx)
        local scalar = code_scalar(ty)
        if scalar ~= nil then return scalar_physical(ty, scalar) end

        local cls = pvm.classof(ty)
        if cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then
            local cty = ctype_for_code_type(ty, ctx)
            return LJ.LJPhysicalType(ty, LJ.LJRegCData(cty), cty, cty)
        end
        if cls == Code.CodeTyHandle or cls == Code.CodeTyLease then
            local inner = cls == Code.CodeTyHandle and physical_type(ty.repr, ctx) or physical_type(ty.base, ctx)
            return LJ.LJPhysicalType(ty, inner.register, inner.storage, inner.abi)
        end
        if cls == Code.CodeTySlice then
            local elem = physical_type(ty.elem, ctx)
            local data = LJ.LJCField("data", LJ.LJCTypePointer(elem.storage, true), nil, nil, nil)
            local len = LJ.LJCField("len", scalar_ctype(Back.BackIndex), nil, nil, nil)
            local cty = ctype_for_code_type(ty, ctx)
            return LJ.LJPhysicalType(ty, LJ.LJRegTuple({ data, len }), cty, cty)
        end
        if cls == Code.CodeTyView then
            local elem = physical_type(ty.elem, ctx)
            local data = LJ.LJCField("data", LJ.LJCTypePointer(elem.storage, true), nil, nil, nil)
            local len = LJ.LJCField("len", scalar_ctype(Back.BackIndex), nil, nil, nil)
            local stride = LJ.LJCField("stride", scalar_ctype(Back.BackIndex), nil, nil, nil)
            local cty = ctype_for_code_type(ty, ctx)
            return LJ.LJPhysicalType(ty, LJ.LJRegTuple({ data, len, stride }), cty, cty)
        end
        if cls == Code.CodeTyClosure then
            local cty = ctype_for_code_type(ty, ctx)
            return LJ.LJPhysicalType(ty, LJ.LJRegCData(cty), cty, cty)
        end
        if cls == Code.CodeTyNamed or cls == Code.CodeTyArray or cls == Code.CodeTyImportedC or cls == Code.CodeTyVector then
            local cty = ctype_for_code_type(ty, ctx)
            return LJ.LJPhysicalType(ty, LJ.LJRegCData(cty), cty, cty)
        end
        error("luajit_ctype: unsupported CodeType for physical lowering " .. class_name(ty), 2)
    end

    local function type_to_physical(moon_ty, ctx)
        local CodeType = require("moonlift.code_type")(T)
        return physical_type(CodeType.type_to_code(moon_ty, ctx), ctx)
    end

    api.code_type_key = code_type_key
    api.scalar_spelling = scalar_spelling
    api.scalar_ctype = scalar_ctype
    api.scalar_register_rep = scalar_register_rep
    api.code_scalar = code_scalar
    api.ctype_spelling = ctype_spelling
    api.ctype_for_code_type = ctype_for_code_type
    api.physical_type = physical_type
    api.code_type_to_physical = physical_type
    api.type_to_physical = type_to_physical
    api.ensure_lj_sig = ensure_lj_sig

    T._moonlift_api_cache.luajit_ctype = api
    return api
end

return bind_context
