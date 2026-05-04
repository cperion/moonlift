local M = {}

local TypeValue = {}
TypeValue.__index = TypeValue
TypeValue.__moonlift_host_type_value = true

local scalar_sources = {
    ScalarVoid = "void",
    ScalarBool = "bool",
    ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
    ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
    ScalarF32 = "f32", ScalarF64 = "f64",
    ScalarIndex = "index",
    ScalarRawPtr = "ptr(void)",
}

local function is_identifier(s)
    return type(s) == "string" and s:match("^[_%a][_%w]*$") ~= nil
end

function TypeValue:as_type_value()
    return self
end

function TypeValue:as_moonlift_type()
    return self.ty
end

function TypeValue:moonlift_splice_source()
    return self.source_hint
end

function TypeValue:__tostring()
    return "MoonTypeValue(" .. tostring(self.source_hint) .. ")"
end

local function type_key(v)
    local mt = type(v) == "table" and getmetatable(v)
    if mt == TypeValue then return true end
    return mt and mt.__moonlift_host_type_value == true
end

function M.Install(api, session)
    local T = session.T
    local C, Ty = T.MoonCore, T.MoonType

    local function type_value(ty, source_hint, extra)
        local v = extra or {}
        v.kind = "type"
        v.session = session
        v.ty = ty
        v.source_hint = source_hint
        return setmetatable(v, TypeValue)
    end

    local function as_type_value(v, site)
        if type_key(v) then
            if getmetatable(v) == TypeValue then return v end
            if type(v.as_type_value) == "function" then return v:as_type_value() end
        end
        error((site or "expected type value") .. ": got " .. type(v), 3)
    end

    local function as_type(v, site)
        return as_type_value(v, site).ty
    end

    local function source_of(v, site)
        return as_type_value(v, site).source_hint
    end

    local function scalar(name, scalar)
        api[name] = type_value(Ty.TScalar(scalar), scalar_sources[tostring(scalar)] or name)
    end

    scalar("void", C.ScalarVoid)
    scalar("bool", C.ScalarBool)
    scalar("i8", C.ScalarI8); scalar("i16", C.ScalarI16); scalar("i32", C.ScalarI32); scalar("i64", C.ScalarI64)
    scalar("u8", C.ScalarU8); scalar("u16", C.ScalarU16); scalar("u32", C.ScalarU32); scalar("u64", C.ScalarU64)
    scalar("f32", C.ScalarF32); scalar("f64", C.ScalarF64)
    scalar("index", C.ScalarIndex)
    api.rawptr = type_value(Ty.TScalar(C.ScalarRawPtr), "ptr(void)")

    function api.type_from_asdl(ty, source_hint, extra)
        return type_value(ty, source_hint or tostring(ty), extra)
    end

    function api.as_type_value(v, site)
        return as_type_value(v, site)
    end

    function api.as_moonlift_type(v, site)
        return as_type(v, site)
    end

    function api.ptr(elem)
        local ev = as_type_value(elem, "ptr expects a type value")
        return type_value(Ty.TPtr(ev.ty), "ptr(" .. ev.source_hint .. ")", { pointee = ev })
    end

    function api.array(count, elem)
        local len
        local count_src
        if type(count) == "number" then
            len = Ty.ArrayLenConst(count)
            count_src = tostring(count)
        elseif type(count) == "table" and type(count.as_expr_value) == "function" then
            local e = count:as_expr_value()
            len = Ty.ArrayLenExpr(e.expr)
            count_src = e.source_hint or "<expr>"
        else
            error("array expects a numeric count or expression value", 2)
        end
        local ev = as_type_value(elem, "array expects an element type")
        return type_value(Ty.TArray(len, ev.ty), "[" .. count_src .. "]" .. ev.source_hint, { element = ev })
    end

    function api.slice(elem)
        local ev = as_type_value(elem, "slice expects an element type")
        return type_value(Ty.TSlice(ev.ty), "[]" .. ev.source_hint, { element = ev })
    end

    function api.view(elem)
        local ev = as_type_value(elem, "view expects an element type")
        return type_value(Ty.TView(ev.ty), "view(" .. ev.source_hint .. ")", { element = ev })
    end

    local function type_list(xs, site)
        local tys, srcs = {}, {}
        for i = 1, #(xs or {}) do
            tys[i] = as_type(xs[i], site)
            srcs[i] = source_of(xs[i], site)
        end
        return tys, srcs
    end

    function api.func_type(params, result)
        local tys, srcs = type_list(params or {}, "func_type params must be type values")
        local ret = as_type(result or api.void, "func_type result must be a type value")
        local ret_src = source_of(result or api.void, "func_type result must be a type value")
        return type_value(Ty.TFunc(tys, ret), "func(" .. table.concat(srcs, ", ") .. ") -> " .. ret_src)
    end

    function api.closure_type(params, result)
        local tys, srcs = type_list(params or {}, "closure_type params must be type values")
        local ret = as_type(result or api.void, "closure_type result must be a type value")
        local ret_src = source_of(result or api.void, "closure_type result must be a type value")
        return type_value(Ty.TClosure(tys, ret), "closure(" .. table.concat(srcs, ", ") .. ") -> " .. ret_src)
    end

    function api.named(module_name, type_name)
        assert(type(module_name) == "string" and module_name ~= "", "named expects a module name")
        assert(type(type_name) == "string" and type_name ~= "", "named expects a type name")
        return type_value(Ty.TNamed(Ty.TypeRefGlobal(module_name, type_name)), module_name .. "." .. type_name)
    end

    function api.local_named(sym, source_hint)
        return type_value(Ty.TNamed(Ty.TypeRefLocal(sym)), source_hint or sym.name, { sym = sym })
    end

    function api.path_named(name)
        assert(is_identifier(name), "path_named expects an identifier")
        return type_value(Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) }))), name)
    end

    api.TypeValue = TypeValue
end

return M
