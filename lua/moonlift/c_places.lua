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
    if T._moonlift_api_cache.c_places ~= nil then return T._moonlift_api_cache.c_places end

    local Ty = T.MoonType
    local Tr = T.MoonTree
    local Bn = T.MoonBind
    local Sem = T.MoonSem
    local C = T.MoonC

    local TypeToC = require("moonlift.type_to_c").Define(T)
    local SizeAlign = require("moonlift.type_size_align").Define(T)

    local api = {}

    local function binding_key(binding)
        return binding.id and binding.id.text or binding.name
    end

    local function type_of_place(place)
        local h = place.h
        local cls = pvm.classof(h)
        if cls == Tr.PlaceTyped or cls == Tr.PlaceOpen then return h.ty end
        return nil
    end

    local function elem_size(ctx, ty)
        local r = SizeAlign.result(ty, ctx and ctx.layout_env, ctx and ctx.target)
        if pvm.classof(r) ~= Ty.TypeMemLayoutKnown then error("c_places: unknown element layout for indexed place", 3) end
        return r.layout.size
    end

    local function atom_from_expr(ctx, expr)
        if ctx and ctx.expr_to_atom then return ctx.expr_to_atom(expr, ctx) end
        if ctx and ctx.expr_to_c then return ctx.expr_to_c(expr, ctx) end
        local cls = pvm.classof(expr)
        if cls and C.CBackendAtom.members[cls] then return expr end
        error("c_places: expression lowering callback required for index/deref address", 3)
    end

    local function ref_binding(ref, ctx)
        local rcls = pvm.classof(ref)
        if rcls == Bn.ValueRefBinding then return ref.binding end
        if rcls == Bn.ValueRefName and ctx and ctx.env then
            local entry = ctx.env[ref.name]
            return entry and entry.binding, entry
        end
        if rcls == Bn.ValueRefPath and ctx and ctx.env then
            local parts = {}
            for i = 1, #ref.path.parts do parts[#parts + 1] = ref.path.parts[i].text end
            local entry = ctx.env[table.concat(parts, ".")]
            return entry and entry.binding, entry
        end
        if rcls == Bn.ValueRefHole then error("c_places: open value reference cannot lower to a C place", 3) end
        return nil, nil
    end

    local function local_or_global_for_binding(binding, ctx)
        ctx = ctx or {}
        local key = binding_key(binding)
        local entry = (ctx.locals_by_binding and ctx.locals_by_binding[key]) or (ctx.env and (ctx.env[key] or ctx.env[binding.name]))
        if entry and entry.id then return "local", entry.id, entry.ty or TypeToC.type_to_c(binding.ty, ctx) end
        local gentry = (ctx.globals_by_binding and ctx.globals_by_binding[key]) or (ctx.global_ids and (ctx.global_ids[key] or ctx.global_ids[binding.name]))
        if gentry then
            if type(gentry) == "table" and gentry.id then return "global", gentry.id, gentry.ty or TypeToC.type_to_c(binding.ty, ctx) end
            return "global", gentry, (ctx.global_types and ctx.global_types[gentry.text]) or TypeToC.type_to_c(binding.ty, ctx)
        end
        local bcls = pvm.classof(binding.class)
        if bcls == Bn.BindingClassGlobalStatic or bcls == Bn.BindingClassGlobalConst then
            local id = C.CBackendGlobalId("g_" .. sanitize(binding.class.module_name .. "_" .. binding.class.item_name))
            return "global", id, (ctx.global_types and ctx.global_types[id.text]) or TypeToC.type_to_c(binding.ty, ctx)
        end
        return nil, nil, nil
    end

    local function classify(cplace)
        local cls = pvm.classof(cplace)
        local mode = (cls == C.CBackendPlaceBytes) and "bytes" or "direct"
        return { place = cplace, mode = mode, direct = mode == "direct", byte_addressed = mode == "bytes", ty = cplace.ty }
    end

    local place_to_c
    local index_base_to_place

    index_base_to_place = function(base, index_expr, result_ty, ctx)
        local bcls = pvm.classof(base)
        local index_atom = atom_from_expr(ctx, index_expr)
        if bcls == Tr.IndexBasePlace then
            local lowered = place_to_c(base.base, ctx).place
            local elem_ty = base.elem or result_ty
            return C.CBackendPlaceIndex(lowered, index_atom, TypeToC.type_to_c(elem_ty, ctx), elem_size(ctx, elem_ty))
        elseif bcls == Tr.IndexBaseExpr then
            local addr = atom_from_expr(ctx, base.base)
            local elem_ty = result_ty
            local elem_cty = TypeToC.type_to_c(elem_ty, ctx)
            local deref = C.CBackendPlaceDeref(addr, C.CBackendDataPtr(elem_cty), nil)
            return C.CBackendPlaceIndex(deref, index_atom, elem_cty, elem_size(ctx, elem_ty))
        elseif bcls == Tr.IndexBaseView then
            if ctx and ctx.view_to_place then return ctx.view_to_place(base.view, index_atom, result_ty, ctx) end
            if ctx and ctx.view_to_parts then
                local parts = ctx.view_to_parts(base.view, ctx)
                local elem_cty = TypeToC.type_to_c(result_ty, ctx)
                local data_place = C.CBackendPlaceDeref(parts.data, elem_cty, nil)
                return C.CBackendPlaceIndex(data_place, index_atom, elem_cty, elem_size(ctx, result_ty))
            end
            error("c_places: view index lowering requires view_to_place/view_to_parts callback", 3)
        end
        error("c_places: unsupported index base", 3)
    end

    place_to_c = function(place, ctx)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef then
            local binding, entry = ref_binding(place.ref, ctx)
            if binding == nil and entry == nil then error("c_places: unresolved place reference", 3) end
            if entry and entry.id then return classify(C.CBackendPlaceLocal(entry.id, entry.ty or TypeToC.type_to_c(binding.ty, ctx))) end
            local kind, id, ty = local_or_global_for_binding(binding, ctx)
            if kind == "local" then return classify(C.CBackendPlaceLocal(id, ty)) end
            if kind == "global" then return classify(C.CBackendPlaceGlobal(id, ty)) end
            error("c_places: binding has no C residence for place", 3)
        elseif cls == Tr.PlaceDeref then
            local ty = type_of_place(place)
            return classify(C.CBackendPlaceDeref(atom_from_expr(ctx, place.base), TypeToC.type_to_c(ty, ctx), nil))
        elseif cls == Tr.PlaceDot then
            error("c_places: raw PlaceDot must be resolved to PlaceField before C lowering", 3)
        elseif cls == Tr.PlaceField then
            local base = place_to_c(place.base, ctx).place
            local field = place.field
            if pvm.classof(field) ~= Sem.FieldByOffset then error("c_places: unresolved field reference in PlaceField", 3) end
            local cty = TypeToC.type_to_c(field.ty, ctx)
            local size, align = nil, nil
            local r = SizeAlign.result(field.ty, ctx and ctx.layout_env, ctx and ctx.target)
            if pvm.classof(r) == Ty.TypeMemLayoutKnown then size, align = r.layout.size, r.layout.align end
            return classify(C.CBackendPlaceField(base, C.CBackendName(sanitize(field.field_name)), cty, field.offset, size, align))
        elseif cls == Tr.PlaceIndex then
            local ty = type_of_place(place)
            return classify(index_base_to_place(place.base, place.index, ty, ctx))
        elseif cls == Tr.PlaceSlotValue then
            error("c_places: open PlaceSlotValue cannot lower to C", 3)
        end
        error("c_places: unsupported place " .. tostring(place and place.kind), 3)
    end

    local function addr_of_place(place, ctx)
        local lowered = place_to_c(place, ctx)
        return {
            kind = "address_of_place",
            place = lowered.place,
            ty = C.CBackendDataPtr(lowered.ty),
            direct = lowered.direct,
            byte_addressed = lowered.byte_addressed,
        }
    end

    local function load_place(place, dst, ctx)
        local lowered = place_to_c(place, ctx)
        return C.CBackendPlaceLoad(dst, lowered.place), lowered
    end

    local function store_place(place, value, ctx)
        local lowered = place_to_c(place, ctx)
        return C.CBackendPlaceStore(lowered.place, value), lowered
    end

    api.place_to_c = place_to_c
    api.index_base_to_place = index_base_to_place
    api.addr_of_place = addr_of_place
    api.address_of = addr_of_place
    api.load_place = load_place
    api.store_place = store_place
    api.elem_size = elem_size

    T._moonlift_api_cache.c_places = api
    return api
end

return M
