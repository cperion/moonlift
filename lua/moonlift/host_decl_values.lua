local pvm = require("moonlift.pvm")

local M = {}

local FieldSpec = {}
FieldSpec.__index = FieldSpec

local HostFieldType = {}
HostFieldType.__index = HostFieldType

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

local function target_name_to_asdl(H, name)
    if name == "lua" then return H.HostExposeLua end
    if name == "terra" then return H.HostExposeTerra end
    if name == "c" then return H.HostExposeC end
    if name == "moonlift" then return H.HostExposeMoonlift end
    error("unknown host expose target: " .. tostring(name), 3)
end

local function attr_name_to_asdl(H, name)
    if name == "readonly" then return H.HostFieldReadonly end
    if name == "mutable" then return H.HostFieldMutable end
    if name == "noalias" then return H.HostFieldNoalias end
    error("unknown host field attr: " .. tostring(name), 3)
end

local function mutability_to_asdl(H, value)
    if value == nil or value == "readonly" then return H.HostReadonly end
    if value == "mutable" then return H.HostMutable end
    if value == "interior_mutable" then return H.HostInteriorMutable end
    error("unknown host mutability: " .. tostring(value), 3)
end

local function bounds_to_asdl(H, value)
    if value == nil or value == "checked" then return H.HostBoundsChecked end
    if value == "unchecked" then return H.HostBoundsUnchecked end
    error("unknown host bounds policy: " .. tostring(value), 3)
end

local function cache_to_asdl(H, value)
    if value == nil or value == "none" then return H.HostProxyCacheNone end
    if value == "lazy" then return H.HostProxyCacheLazy end
    if value == "eager" then return H.HostProxyCacheEager end
    error("unknown host proxy cache policy: " .. tostring(value), 3)
end

local function abi_name_to_asdl(H, value)
    if value == nil or value == "default" then return H.HostExposeAbiDefault end
    if value == "pointer" or value == "ptr" then return H.HostExposeAbiPointer end
    if value == "descriptor" then return H.HostExposeAbiDescriptor end
    if value == "data_len_stride" then return H.HostExposeAbiDataLenStride end
    if value == "expanded" or value == "expanded_scalars" then return H.HostExposeAbiExpandedScalars end
    error("unknown host expose ABI: " .. tostring(value), 3)
end

function M.Install(api, session)
    local T = session.T
    local C, Ty, H = T.Moon2Core, T.Moon2Type, T.Moon2Host

    local function layout_id(name, opts)
        opts = opts or {}
        return H.HostLayoutId((opts.key_prefix or "mlua.") .. name, name)
    end

    local function field_id(owner, name, opts)
        opts = opts or {}
        return H.HostFieldId((opts.key_prefix or "mlua.") .. owner .. "." .. name, name)
    end

    local function as_type(v, site)
        return api.as_moon2_type(v, site or "expected Moonlift type value")
    end

    local function host_field_type(expose_ty, storage, source_hint)
        return setmetatable({ expose_ty = expose_ty, storage = storage, source_hint = source_hint }, HostFieldType)
    end

    local function as_host_field_type(v, site)
        if type(v) == "table" and getmetatable(v) == HostFieldType then return v.expose_ty, v.storage end
        return as_type(v, site), H.HostStorageSame
    end

    local function as_attrs(attrs)
        local out = {}
        for i = 1, #(attrs or {}) do
            local a = attrs[i]
            out[i] = type(a) == "string" and attr_name_to_asdl(H, a) or a
        end
        return out
    end

    local function as_field_spec(v, site)
        if type(v) == "table" and getmetatable(v) == FieldSpec then return v end
        error((site or "expected host field spec") .. ": got " .. type(v), 3)
    end

    local function as_host_decl(v, site)
        local cls = pvm.classof(v)
        if cls == H.HostDeclStruct or cls == H.HostDeclExpose or cls == H.HostDeclAccessor then return v end
        if cls == H.HostStructDecl then return H.HostDeclStruct(v) end
        if cls == H.HostExposeDecl then return H.HostDeclExpose(v) end
        if cls == H.HostAccessorField or cls == H.HostAccessorLua or cls == H.HostAccessorMoonlift then return H.HostDeclAccessor(v) end
        error((site or "expected host declaration") .. ": got " .. tostring(v), 3)
    end

    function api.host_named(name)
        assert_name(name, "host_named")
        return api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal("", name)), name)
    end

    function api.host_field_type(ty, storage)
        return host_field_type(as_type(ty, "host_field_type expects a type value"), storage or H.HostStorageSame)
    end

    api.host_bool8 = host_field_type(Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolU8, C.ScalarU8), "bool8")
    api.host_bool32 = host_field_type(Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32), "bool32")

    function api.host_bool_stored(storage_ty)
        local ty = as_type(storage_ty, "host_bool_stored expects a scalar storage type")
        assert(pvm.classof(ty) == Ty.TScalar, "host_bool_stored expects a scalar storage type")
        local encoding = (ty.scalar == C.ScalarU8 or ty.scalar == C.ScalarI8) and H.HostBoolU8 or H.HostBoolI32
        return host_field_type(Ty.TScalar(C.ScalarBool), H.HostStorageBool(encoding, ty.scalar), "bool stored")
    end

    function api.host_field(name, ty, attrs)
        assert_name(name, "host_field")
        local expose_ty, storage = as_host_field_type(ty, "host_field expects a type value")
        return setmetatable({ name = name, expose_ty = expose_ty, storage = storage, attrs = as_attrs(attrs) }, FieldSpec)
    end

    function api.host_field_decl(owner_name, field_spec, opts)
        assert_name(owner_name, "host_field_decl owner")
        local f = as_field_spec(field_spec, "host_field_decl expects a field spec")
        return H.HostFieldDecl(field_id(owner_name, f.name, opts), f.name, f.expose_ty, f.storage, f.attrs)
    end

    function api.host_struct_decl(name, fields, opts)
        assert_name(name, "host_struct_decl")
        opts = opts or {}
        local repr = opts.repr or H.HostReprC
        if opts.packed ~= nil then repr = H.HostReprPacked(opts.packed) end
        local out = {}
        for i = 1, #(fields or {}) do out[i] = api.host_field_decl(name, fields[i], opts) end
        return H.HostStructDecl(layout_id(name, opts), name, repr, out)
    end

    function api.host_struct(name, fields, opts)
        return H.HostDeclStruct(api.host_struct_decl(name, fields, opts))
    end

    function api.host_expose_type(ty)
        return H.HostExposeType(as_type(ty, "host_expose_type expects a type value"))
    end

    function api.host_expose_ptr(ty)
        return H.HostExposePtr(as_type(ty, "host_expose_ptr expects a type value"))
    end

    function api.host_expose_view(ty)
        return H.HostExposeView(as_type(ty, "host_expose_view expects a type value"))
    end

    local function proxy_kind_for_subject(subject)
        local cls = pvm.classof(subject)
        if cls == H.HostExposePtr then return H.HostProxyPtr end
        if cls == H.HostExposeView then return H.HostProxyView end
        return H.HostProxyTypedRecord
    end

    local function default_abi_for_target(subject, target)
        local cls = pvm.classof(subject)
        if cls == H.HostExposeView and (target == H.HostExposeC or target == H.HostExposeTerra) then return H.HostExposeAbiDescriptor end
        if cls == H.HostExposePtr and (target == H.HostExposeC or target == H.HostExposeTerra) then return H.HostExposeAbiPointer end
        return H.HostExposeAbiDefault
    end

    local function expose_mode_for_opts(subject, opts, target)
        opts = opts or {}
        if opts.mode then return opts.mode end
        if opts.materialize then
            return H.HostExposeEagerTable(type(opts.materialize) == "string" and (opts.materialize == "full_copy" and H.HostMaterializeFullCopy or opts.materialize == "borrowed_view" and H.HostMaterializeBorrowedView or H.HostMaterializeProjectedFields) or opts.materialize)
        end
        local default_bounds = target == H.HostExposeLua and "checked" or "unchecked"
        return H.HostExposeProxy(
            opts.proxy_kind or proxy_kind_for_subject(subject),
            cache_to_asdl(H, opts.cache),
            mutability_to_asdl(H, opts.mutability),
            bounds_to_asdl(H, opts.bounds or default_bounds)
        )
    end

    local function facet_from_opts(subject, target, opts)
        opts = opts or {}
        target = type(target) == "string" and target_name_to_asdl(H, target) or target
        return H.HostExposeFacet(target, opts.abi and (type(opts.abi) == "string" and abi_name_to_asdl(H, opts.abi) or opts.abi) or default_abi_for_target(subject, target), expose_mode_for_opts(subject, opts, target))
    end

    local function as_facets(subject, opts)
        opts = opts or {}
        if opts.facets then
            local out = {}
            for i = 1, #opts.facets do
                local facet = opts.facets[i]
                if pvm.classof(facet) == H.HostExposeFacet then out[i] = facet
                else out[i] = facet_from_opts(subject, facet.target or facet[1], facet) end
            end
            return out
        end
        local targets = opts.targets or { "lua", "terra", "c" }
        local out = {}
        for i = 1, #targets do out[i] = facet_from_opts(subject, targets[i], opts) end
        return out
    end

    function api.host_expose_facet(target, opts)
        local facet = {}
        for k, v in pairs(opts or {}) do facet[k] = v end
        facet.target = target
        return facet
    end

    function api.host_expose_decl(subject, public_name, opts)
        assert_name(public_name, "host_expose_decl")
        opts = opts or {}
        if type(subject) == "table" and getmetatable(subject) == HostFieldType then subject = H.HostExposeType(subject.expose_ty) end
        if not pvm.classof(subject) then subject = api.host_expose_type(subject) end
        return H.HostExposeDecl(subject, public_name, as_facets(subject, opts))
    end

    function api.host_expose(subject, public_name, opts)
        return H.HostDeclExpose(api.host_expose_decl(subject, public_name, opts))
    end

    function api.host_lua_accessor(owner_name, name, lua_symbol)
        assert_name(owner_name, "host_lua_accessor owner")
        assert_name(name, "host_lua_accessor")
        return H.HostDeclAccessor(H.HostAccessorLua(owner_name, name, lua_symbol or (owner_name .. "_" .. name)))
    end

    function api.host_field_accessor(owner_name, name, field_name)
        assert_name(owner_name, "host_field_accessor owner")
        assert_name(name, "host_field_accessor")
        assert_name(field_name, "host_field_accessor field")
        return H.HostDeclAccessor(H.HostAccessorField(owner_name, name, field_name))
    end

    function api.host_moonlift_accessor(owner_name, name, func)
        assert_name(owner_name, "host_moonlift_accessor owner")
        assert_name(name, "host_moonlift_accessor")
        return H.HostDeclAccessor(H.HostAccessorMoonlift(owner_name, name, func))
    end

    function api.host_decl_set(decls)
        local out = {}
        for i = 1, #(decls or {}) do out[i] = as_host_decl(decls[i], "host_decl_set") end
        return H.HostDeclSet(out)
    end

    api.HostFieldSpec = FieldSpec
    api.HostFieldType = HostFieldType
end

return M
