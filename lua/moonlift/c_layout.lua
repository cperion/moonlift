local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_layout ~= nil then return T._moonlift_api_cache.c_layout end

    local Ty = T.MoonType
    local Sem = T.MoonSem
    local Tr = T.MoonTree
    local C = T.MoonC

    local TypeToC = require("moonlift.type_to_c").Define(T)
    local SizeAlign = require("moonlift.type_size_align").Define(T)

    local api = {}

    local function type_id_for_layout(layout)
        local cls = pvm.classof(layout)
        if cls == Sem.LayoutNamed then return C.CTypeId(layout.module_name, layout.type_name) end
        if cls == Sem.LayoutLocal then return C.CTypeId("local", layout.sym.name) end
        error("c_layout: unsupported layout node", 3)
    end

    local function ref_id(ref)
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal then return C.CTypeId(ref.module_name, ref.type_name) end
        if rcls == Ty.TypeRefLocal then return C.CTypeId("local", ref.sym.name) end
        if rcls == Ty.TypeRefPath and #ref.path.parts > 0 then return C.CTypeId("", ref.path.parts[#ref.path.parts].text) end
        return nil
    end

    local function layout_key(id)
        return id.module_name .. ":" .. id.spelling
    end

    local function remember_decl(ctx, decl)
        if ctx == nil then return decl end
        ctx.types = ctx.types or {}
        ctx.type_order = ctx.type_order or ctx.types
        ctx.type_decls_by_id = ctx.type_decls_by_id or {}
        local id = decl.id
        local key = layout_key(id)
        if ctx.type_decls_by_id[key] == nil then
            ctx.type_decls_by_id[key] = decl
            ctx.type_order[#ctx.type_order + 1] = decl
        end
        return decl
    end

    local function field_size_align(field_ty, env, target)
        local r = SizeAlign.result(field_ty, env, target)
        if pvm.classof(r) == Ty.TypeMemLayoutKnown then return r.layout.size, r.layout.align end
        return nil, nil
    end

    local function backend_field(field, env, ctx, target)
        local ty = TypeToC.type_to_c(field.ty, ctx)
        local size, align = field_size_align(field.ty, env, target)
        return C.CBackendField(C.CBackendName(sanitize(field.field_name)), ty, field.offset, size, align)
    end

    local function decl_from_layout(layout, env, ctx, opts)
        opts = opts or {}
        local id = type_id_for_layout(layout)
        local fields = {}
        for i = 1, #layout.fields do fields[#fields + 1] = backend_field(layout.fields[i], env, ctx, opts.target) end
        local kind = opts.kind or opts[id.spelling] or "struct"
        local decl
        if kind == "union" then
            decl = C.CBackendUnionDecl(id, fields, layout.size, layout.align)
        elseif kind == "opaque" then
            decl = C.CBackendOpaqueDecl(id)
        else
            decl = C.CBackendStructDecl(id, fields, layout.size, layout.align)
        end
        return remember_decl(ctx, decl)
    end

    local function find_layout(env, id)
        env = env or Sem.LayoutEnv({})
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            local lid = type_id_for_layout(layout)
            if lid.module_name == id.module_name and lid.spelling == id.spelling then return layout end
        end
        return nil
    end

    local function decl_for_type_decl(type_decl, mod_name, env, ctx, opts)
        opts = opts or {}
        local cls = pvm.classof(type_decl)
        if cls == Tr.TypeDeclStruct or cls == Tr.TypeDeclUnion then
            local id = C.CTypeId(mod_name or "", type_decl.name)
            local layout = find_layout(env, id)
            if layout ~= nil then return decl_from_layout(layout, env, ctx, { target = opts.target, kind = (cls == Tr.TypeDeclUnion) and "union" or "struct" }) end
            local fields = {}
            for i = 1, #type_decl.fields do
                local f = type_decl.fields[i]
                fields[#fields + 1] = C.CBackendField(C.CBackendName(sanitize(f.field_name)), TypeToC.type_to_c(f.ty, ctx), nil, nil, nil)
            end
            local decl = (cls == Tr.TypeDeclUnion) and C.CBackendUnionDecl(id, fields, nil, nil) or C.CBackendStructDecl(id, fields, nil, nil)
            return remember_decl(ctx, decl)
        elseif cls == Tr.TypeDeclOpenStruct or cls == Tr.TypeDeclOpenUnion then
            local id = C.CTypeId("local", type_decl.sym.name)
            local layout = find_layout(env, id)
            if layout ~= nil then return decl_from_layout(layout, env, ctx, { target = opts.target, kind = (cls == Tr.TypeDeclOpenUnion) and "union" or "struct" }) end
            return remember_decl(ctx, C.CBackendOpaqueDecl(id))
        elseif cls == Tr.TypeDeclEnumSugar or cls == Tr.TypeDeclTaggedUnionSugar then
            local id = C.CTypeId(mod_name or "", type_decl.name)
            local layout = find_layout(env, id)
            if layout ~= nil then return decl_from_layout(layout, env, ctx, { target = opts.target, kind = "struct" }) end
            return remember_decl(ctx, C.CBackendOpaqueDecl(id))
        end
        error("c_layout: unsupported TypeDecl " .. tostring(type_decl and type_decl.kind), 2)
    end

    local function ensure_named_type(ctx, ty, env, opts)
        opts = opts or {}
        if pvm.classof(ty) ~= Ty.TNamed then return TypeToC.type_to_c(ty, ctx) end
        local id = ref_id(ty.ref)
        if id == nil then error("c_layout: unresolved named type", 2) end
        local key = layout_key(id)
        if ctx and ctx.type_decls_by_id and ctx.type_decls_by_id[key] then return C.CBackendNamed(id) end
        local layout = find_layout(env, id)
        if layout ~= nil then decl_from_layout(layout, env, ctx, opts) end
        return C.CBackendNamed(id)
    end

    local function ensure_descriptor_type(ctx, kind, elem_ty)
        local CAbi = require("moonlift.c_abi").Define(T)
        return CAbi.ensure_descriptor_decl(ctx, kind, elem_ty)
    end

    local function decls_from_layout_env(ctx, env, opts)
        opts = opts or {}
        local out = {}
        env = env or Sem.LayoutEnv({})
        for i = 1, #env.layouts do out[#out + 1] = decl_from_layout(env.layouts[i], env, ctx, opts) end
        return out
    end

    local function layout_assertion_for_decl(decl)
        local cls = pvm.classof(decl)
        if (cls == C.CBackendStructDecl or cls == C.CBackendUnionDecl or cls == C.CBackendTypedef) and decl.size ~= nil and decl.align ~= nil then
            return C.CBackendLayoutAssertion(decl.id, decl.size, decl.align)
        end
        return nil
    end

    local function layout_assertions(ctx, decls)
        if decls == nil then decls = (ctx and (ctx.type_order or ctx.types)) or {} end
        if pvm.classof(decls) then decls = { decls } end
        local out = {}
        for i = 1, #decls do
            local a = layout_assertion_for_decl(decls[i])
            if a ~= nil then out[#out + 1] = a end
        end
        return out
    end

    api.type_id_for_layout = type_id_for_layout
    api.decl_from_layout = decl_from_layout
    api.decl_for_type_decl = decl_for_type_decl
    api.ensure_named_type = ensure_named_type
    api.ensure_descriptor_type = ensure_descriptor_type
    api.decls_from_layout_env = decls_from_layout_env
    api.layout_assertion_for_decl = layout_assertion_for_decl
    api.layout_assertions = layout_assertions

    T._moonlift_api_cache.c_layout = api
    return api
end

return M
