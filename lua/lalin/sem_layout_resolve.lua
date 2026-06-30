local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local Sem = T.LalinSem
    local Tr = T.LalinTree
    local H = T.LalinHost

    local module_type_api = require("lalin.tree_module_type")(T)

    local function index_ty() return Ty.TScalar(C.ScalarIndex) end

    local type_layout
    local type_ref_layout
    local field_in_layout
    local resolve_field_ref
    local resolve_place
    local resolve_expr
    local resolve_view
    local resolve_domain
    local resolve_index_base
    local resolve_control_stmt_region
    local resolve_control_expr_region
    local resolve_stmt
    local resolve_func
    local resolve_const
    local resolve_static
    local resolve_type_decl
    local resolve_item
    local resolve_module

    local function one(phase, node, env, target)
        return only(phase(node, env, target))
    end

    local function maybe_one(g, p, c)
        local values = g
        if #values == 0 then return nil end
        return values[1]
    end

    local function map_exprs(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_expr, xs[i], env, target) end
        return out
    end

    local function map_stmts(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_stmt, xs[i], env, target) end
        return out
    end

    local function map_jump_args(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = schema.with(xs[i], { value = one(resolve_expr, xs[i].value, env, target) }) end
        return out
    end

    local function map_items(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_item, xs[i], env, target) end
        return out
    end

    function type_ref_layout(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeRefGlobal) then
            return (function(ref, env)

            for i = 1, #env.layouts do
                local layout = env.layouts[i]
                if schema.classof(layout) == Sem.LayoutNamed and layout.module_name == ref.module_name and layout.type_name == ref.type_name then
                    return single(layout)
                end
            end
            return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefLocal) then
            return (function(ref, env)

            for i = 1, #env.layouts do
                local layout = env.layouts[i]
                if schema.classof(layout) == Sem.LayoutLocal and layout.sym == ref.sym then
                    return single(layout)
                end
            end
            return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefPath) then
            return (function(ref, env)

            if #ref.path.parts == 1 then
                local name = ref.path.parts[1].text
                for i = 1, #env.layouts do
                    local layout = env.layouts[i]
                    if schema.classof(layout) == Sem.LayoutNamed and layout.type_name == name then return single(layout) end
                end
            end
            return {}
            end)(node, ...)
        else
            error("phase lalin_sem_type_ref_layout: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function type_layout(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TNamed) then
            return (function(self, env, target)
 return type_ref_layout(self.ref, env)
            end)(node, ...)
        elseif schema.isa(node, Ty.TScalar) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TPtr) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TArray) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlice) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TView) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TLease) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TOwned) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TAccess) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.THandle) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TFunc) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TClosure) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TCType) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Ty.TCFuncPtr) then
            return (function()
 return {}
            end)(node, ...)
        else
            error("phase lalin_sem_type_layout: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function field_in_layout(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Sem.LayoutNamed) then
            return (function(layout, field_name)

            for i = 1, #layout.fields do
                local field = layout.fields[i]
                if field.field_name == field_name then
                    return single(field)
                end
            end
            return {}
            end)(node, ...)
        elseif schema.isa(node, Sem.LayoutLocal) then
            return (function(layout, field_name)

            for i = 1, #layout.fields do
                local field = layout.fields[i]
                if field.field_name == field_name then
                    return single(field)
                end
            end
            return {}
            end)(node, ...)
        else
            error("phase lalin_sem_field_in_layout: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local function storage_for_type(ty)
        if schema.classof(ty) == Ty.TScalar then return H.HostRepScalar(ty.scalar) end
        if schema.classof(ty) == Ty.TPtr then return H.HostRepPtr(ty.elem) end
        if schema.classof(ty) == Ty.TView then return H.HostRepView(ty.elem) end
        if schema.classof(ty) == Ty.TAccess then return storage_for_type(ty.base) end
        return H.HostRepOpaque("sem_layout")
    end

    local function access_base_type(ty)
        local cls = schema.classof(ty)
        if cls == Ty.TAccess or cls == Ty.TLease then return access_base_type(ty.base) end
        return ty
    end

    function resolve_field_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Sem.FieldByOffset) then
            return (function(field)
 return single(field)
            end)(node, ...)
        elseif schema.isa(node, Sem.FieldByName) then
            return (function(field, base_ty, env)

            local layout = maybe_one(type_layout(base_ty, env))
            if layout == nil then return single(field) end
            local resolved = maybe_one(field_in_layout(layout, field.field_name))
            if resolved == nil then return single(field) end
            return single(Sem.FieldByOffset(resolved.field_name, resolved.offset, resolved.ty, storage_for_type(resolved.ty)))
            end)(node, ...)
        else
            error("phase lalin_sem_resolve_field_ref: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local function type_of_place(place)
        local h = place.h
        local cls = schema.classof(h)
        if cls == Tr.PlaceTyped then return h.ty end
        return nil
    end

    function resolve_index_base(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_expr, self.base, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_place, self.base, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self, env, target)
 return single(schema.with(self, { view = one(resolve_view, self.view, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_index_base: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_place(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_expr, self.base, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self, env, target)

            local base = one(resolve_place, self.base, env, target)
            local base_ty = type_of_place(base)
            local lookup_ty = access_base_type(base_ty)
            if lookup_ty ~= nil and schema.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            if lookup_ty ~= nil then
                local field = only(resolve_field_ref(Sem.FieldByName(self.name, lookup_ty), lookup_ty, env))
                if schema.classof(field) == Sem.FieldByOffset then return single(Tr.PlaceField(Tr.PlaceTyped(field.ty), base, field)) end
            end
            return single(schema.with(self, { base = base }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self, env, target)

            local base = one(resolve_place, self.base, env, target)
            local base_ty = type_of_place(base)
            base_ty = access_base_type(base_ty)
            if base_ty ~= nil and schema.classof(base_ty) == Ty.TPtr then base_ty = base_ty.elem end
            local field = self.field
            if base_ty ~= nil then field = only(resolve_field_ref(self.field, base_ty, env)) end
            return single(schema.with(self, { base = base, field = field }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_index_base, self.base, env, target), index = one(resolve_expr, self.index, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_place: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_view(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ViewFromExpr) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_expr, self.base, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewContiguous) then
            return (function(self, env, target)
 return single(schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewStrided) then
            return (function(self, env, target)
 return single(schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRestrided) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_view, self.base, env, target), stride = one(resolve_expr, self.stride, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewWindow) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_view, self.base, env, target), start = one(resolve_expr, self.start, env, target), len = one(resolve_expr, self.len, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRowBase) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_view, self.base, env, target), row_offset = one(resolve_expr, self.row_offset, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleaved) then
            return (function(self, env, target)
 return single(schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleavedView) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_view, self.base, env, target), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_view: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_domain(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.DomainRange) then
            return (function(self, env, target)
 return single(schema.with(self, { stop = one(resolve_expr, self.stop, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainRange2) then
            return (function(self, env, target)
 return single(schema.with(self, { start = one(resolve_expr, self.start, env, target), stop = one(resolve_expr, self.stop, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqValues) then
            return (function(self, env, target)
 return single(schema.with(self, { values = map_exprs(self.values, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainValue) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainView) then
            return (function(self, env, target)
 return single(schema.with(self, { view = one(resolve_view, self.view, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqViews) then
            return (function(self, env, target)
 local views = {}; for i = 1, #self.views do views[#views + 1] = one(resolve_view, self.views[i], env, target) end; return single(schema.with(self, { views = views }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_domain: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_expr(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self, env, target)

            local base = one(resolve_expr, self.base, env, target)
            local h = base.h
            local base_ty = nil
            local h_cls = schema.classof(h)
            if h_cls == Tr.ExprTyped then base_ty = h.ty end
            local lookup_ty = access_base_type(base_ty)
            if lookup_ty ~= nil and schema.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            if lookup_ty ~= nil then
                local field = only(resolve_field_ref(Sem.FieldByName(self.name, lookup_ty), lookup_ty, env))
                if schema.classof(field) == Sem.FieldByOffset then return single(Tr.ExprField(Tr.ExprTyped(field.ty), base, field)) end
            end
            return single(schema.with(self, { base = base }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self, env, target)
 return single(schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self, env, target)
 return single(schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self, env, target)
 return single(schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self, env, target)
 return single(schema.with(self, { args = map_exprs(self.args, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self, env, target)
 return single(schema.with(self, { place = one(resolve_place, self.place, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self, env, target)
 return single(schema.with(self, { callee = one(resolve_expr, self.callee, env, target), args = map_exprs(self.args, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self, env, target)

            local base = one(resolve_expr, self.base, env, target)
            local h = base.h
            local base_ty = nil
            local h_cls = schema.classof(h)
            if h_cls == Tr.ExprTyped then base_ty = h.ty end
            base_ty = access_base_type(base_ty)
            if base_ty ~= nil and schema.classof(base_ty) == Ty.TPtr then base_ty = base_ty.elem end
            local field = self.field
            if base_ty ~= nil then field = only(resolve_field_ref(self.field, base_ty, env)) end
            return single(schema.with(self, { base = base, field = field }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self, env, target)
 return single(schema.with(self, { base = one(resolve_index_base, self.base, env, target), index = one(resolve_expr, self.index, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self, env, target)
 local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { value = one(resolve_expr, self.fields[i].value, env, target) }) end; return single(schema.with(self, { fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self, env, target)
 return single(schema.with(self, { elems = map_exprs(self.elems, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self, env, target)
 return single(schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self, env, target)
 return single(schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self, env, target)
 local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target), result = one(resolve_expr, self.arms[i].result, env, target) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target), result = one(resolve_expr, self.variant_arms[i].result, env, target) }) end; return single(schema.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body or {}, env, target), default_expr = one(resolve_expr, self.default_expr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self, env, target)
 return single(schema.with(self, { region = one(resolve_control_expr_region, self.region, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self, env, target)
 return single(schema.with(self, { stmts = map_stmts(self.stmts, env, target), result = one(resolve_expr, self.result, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self, env, target)
 return single(schema.with(self, { body = map_stmts(self.body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self, env, target)
 return single(schema.with(self, { view = one(resolve_view, self.view, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self, env, target)
 return single(schema.with(self, { addr = one(resolve_expr, self.addr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self, env, target)
 return single(schema.with(self, { addr = one(resolve_expr, self.addr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self, env, target)
 return single(schema.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self, env, target)
 return single(schema.with(self, { addr = one(resolve_expr, self.addr, env, target), expected = one(resolve_expr, self.expected, env, target), replacement = one(resolve_expr, self.replacement, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSizeOf) then
            return (function(self, env, target)

            local layout_api = require("lalin.type_size_align")(T)
            local result = layout_api.result(self.ty, env, target)
            if schema.classof(result) == Ty.TypeMemLayoutKnown then
                local size = tostring(result.layout.size)
                return single(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(size)))
            end
            return single(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("0")))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAlignOf) then
            return (function(self, env, target)

            local layout_api = require("lalin.type_size_align")(T)
            local result = layout_api.result(self.ty, env, target)
            if schema.classof(result) == Ty.TypeMemLayoutKnown then
                local align = tostring(result.layout.align)
                return single(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(align)))
            end
            return single(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("1")))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprNull) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIsNull) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCtor) then
            return (function(self, env, target)
 return single(schema.with(self, { args = map_exprs(self.args, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_expr: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local function resolve_entry_block(block, env, target)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = schema.with(block.params[i], { init = one(resolve_expr, block.params[i].init, env, target) }) end
        return schema.with(block, { params = params, body = map_stmts(block.body, env, target) })
    end

    local function resolve_control_block(block, env, target)
        return schema.with(block, { body = map_stmts(block.body, env, target) })
    end

    function resolve_control_stmt_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(self, env, target)

            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
            return single(schema.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_control_stmt_region: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_control_expr_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlExprRegion) then
            return (function(self, env, target)

            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
            return single(schema.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_control_expr_region: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_stmt(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self, env, target)
 return single(schema.with(self, { init = one(resolve_expr, self.init, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self, env, target)
 return single(schema.with(self, { init = one(resolve_expr, self.init, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(self, env, target)
 return single(schema.with(self, { place = one(resolve_place, self.place, env, target), value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(self, env, target)
 return single(schema.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self, env, target)
 return single(schema.with(self, { expr = one(resolve_expr, self.expr, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(self, env, target)
 return single(schema.with(self, { cond = one(resolve_expr, self.cond, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self, env, target)
 return single(schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_body = map_stmts(self.then_body, env, target), else_body = map_stmts(self.else_body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(self, env, target)
 local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target) }) end; return single(schema.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self, env, target)
 return single(schema.with(self, { args = map_jump_args(self.args, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(self, env, target)
 return single(schema.with(self, { args = map_jump_args(self.args, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(self, env, target)
 return single(schema.with(self, { region = one(resolve_control_stmt_region, self.region, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtTrap) then
            return (function(self)
 return single(self)
            end)(node, ...)
        else
            error("phase lalin_sem_layout_stmt: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_func(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function(self, env, target)
 return single(schema.with(self, { body = map_stmts(self.body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function(self, env, target)
 return single(schema.with(self, { body = map_stmts(self.body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self, env, target)
 return single(schema.with(self, { body = map_stmts(self.body, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self, env, target)
 return single(schema.with(self, { body = map_stmts(self.body, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_func: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ConstItem) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_const: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_static(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StaticItem) then
            return (function(self, env, target)
 return single(schema.with(self, { value = one(resolve_expr, self.value, env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_static: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_type_decl(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.TypeDeclStruct) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclUnion) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclEnumSugar) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclTaggedUnionSugar) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclHandle) then
            return (function(self)
 return single(self)
            end)(node, ...)
        else
            error("phase lalin_sem_layout_type_decl: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_item(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemFunc) then
            return (function(self, env, target)
 return single(schema.with(self, { func = one(resolve_func, self.func, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function(self, env, target)
 return single(schema.with(self, { c = one(resolve_const, self.c, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function(self, env, target)
 return single(schema.with(self, { s = one(resolve_static, self.s, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function(self)
 return single(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemType) then
            return (function(self, env, target)
 return single(schema.with(self, { t = one(resolve_type_decl, self.t, env, target) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegion) then
            return (function(self)
 return single(self)
            end)(node, ...)
        else
            error("phase lalin_sem_layout_item: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function resolve_module(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module, env, target)

            local resolved_env = env
            if resolved_env == nil or #resolved_env.layouts == 0 then
                resolved_env = Sem.LayoutEnv(module_type_api.env(module, target).layouts)
            end
            return single(schema.with(module, { items = map_items(module.items, resolved_env, target) }))
            end)(node, ...)
        else
            error("phase lalin_sem_layout_module: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local function empty_env()
        return Sem.LayoutEnv({})
    end

    return {
        empty_env = empty_env,
        type_layout = type_layout,
        field_in_layout = field_in_layout,
        resolve_field_ref = resolve_field_ref,
        resolve_expr = resolve_expr,
        resolve_place = resolve_place,
        resolve_module = resolve_module,
        field = function(field, base_ty, env) return only(resolve_field_ref(field, base_ty, env or empty_env())) end,
        expr = function(expr, env, target) return one(resolve_expr, expr, env or empty_env(), target) end,
        place = function(place, env, target) return one(resolve_place, place, env or empty_env(), target) end,
        module = function(module, env, target) return one(resolve_module, module, env, target) end,
    }
end

return bind_context
