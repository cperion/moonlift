local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local Tr = T.MoonTree

    local function module_name(module)
        local h = module.h
        local cls = pvm.classof(h)
        if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then
            return h.module_name
        end
        if cls == Tr.ModuleOpen and h.name ~= T.MoonOpen.ModuleNameOpen then
            return h.name.module_name
        end
        return ""
    end

    local function collect_type_defs(module)
        local defs = {}
        for _, item in ipairs(module.items or {}) do
            if pvm.classof(item) == Tr.ItemType then
                local t = item.t
                local cls = pvm.classof(t)
                if cls == Tr.TypeDeclStruct or cls == Tr.TypeDeclUnion
                    or cls == Tr.TypeDeclEnumSugar or cls == Tr.TypeDeclTaggedUnionSugar then
                    defs[t.name] = { kind = "named" }
                elseif cls == Tr.TypeDeclHandle then
                    defs[t.name] = { kind = "handle", repr = t.repr }
                end
            end
        end
        return defs
    end

    local function single_path_name(ref)
        if pvm.classof(ref) ~= Ty.TypeRefPath then return nil end
        local parts = ref.path.parts or {}
        if #parts ~= 1 then return nil end
        return parts[1].text
    end

    local resolve_any

    local function resolve_type(ty, ctx)
        local cls = pvm.classof(ty)
        if cls == Ty.TNamed then
            local name = single_path_name(ty.ref)
            local def = name and ctx.types[name]
            if def then
                if def.kind == "handle" then
                    return Ty.THandle(Ty.TypeRefGlobal(ctx.module_name, name), def.repr)
                end
                return Ty.TNamed(Ty.TypeRefGlobal(ctx.module_name, name))
            end
            return ty
        elseif cls == Ty.THandle then
            local name = single_path_name(ty.ref)
            if name and ctx.types[name] then
                return Ty.THandle(Ty.TypeRefGlobal(ctx.module_name, name), ty.repr)
            end
            return ty
        elseif cls == Ty.TPtr then
            return pvm.with(ty, { elem = resolve_type(ty.elem, ctx) })
        elseif cls == Ty.TArray then
            return pvm.with(ty, {
                count = resolve_any(ty.count, ctx),
                elem = resolve_type(ty.elem, ctx),
            })
        elseif cls == Ty.TSlice or cls == Ty.TView then
            return pvm.with(ty, { elem = resolve_type(ty.elem, ctx) })
        elseif cls == Ty.TLease then
            return pvm.with(ty, { base = resolve_type(ty.base, ctx) })
        elseif cls == Ty.TAccess then
            return pvm.with(ty, { base = resolve_type(ty.base, ctx) })
        elseif cls == Ty.TFunc or cls == Ty.TClosure then
            local params = {}
            for i = 1, #ty.params do params[i] = resolve_type(ty.params[i], ctx) end
            return pvm.with(ty, { params = params, result = resolve_type(ty.result, ctx) })
        end
        return ty
    end

    local function resolve_list(xs, ctx)
        local changed = false
        local out = {}
        for i = 1, #xs do
            out[i] = resolve_any(xs[i], ctx)
            if out[i] ~= xs[i] then changed = true end
        end
        return changed and out or xs
    end

    resolve_any = function(v, ctx)
        if type(v) ~= "table" then return v end
        local cls = pvm.classof(v)
        if not cls then return v end
        if Ty.Type.members[cls] then return resolve_type(v, ctx) end

        local fields = rawget(cls, "__fields")
        if not fields or #fields == 0 then return v end

        local changed = false
        local updates = {}
        for i = 1, #fields do
            local name = fields[i].name
            local value = v[name]
            local next_value = value
            if type(value) == "table" then
                if pvm.classof(value) then
                    next_value = resolve_any(value, ctx)
                else
                    next_value = resolve_list(value, ctx)
                end
            end
            if next_value ~= value then
                updates[name] = next_value
                changed = true
            end
        end
        if changed then return pvm.with(v, updates) end
        return v
    end

    local function module(module)
        local ctx = {
            module_name = module_name(module),
            types = collect_type_defs(module),
        }
        return resolve_any(module, ctx)
    end

    return {
        module = module,
    }
end

return M
