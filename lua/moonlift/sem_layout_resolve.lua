local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local Sem = T.MoonSem
    local Tr = T.MoonTree
    local H = T.MoonHost

    local module_type_api = require("moonlift.tree_module_type").Define(T)

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
        return pvm.one(phase(node, env, target))
    end

    local function maybe_one(g, p, c)
        local values = pvm.drain(g, p, c)
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
        for i = 1, #xs do out[#out + 1] = pvm.with(xs[i], { value = one(resolve_expr, xs[i].value, env, target) }) end
        return out
    end

    local function map_items(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_item, xs[i], env, target) end
        return out
    end

    type_ref_layout = pvm.phase("moonlift_sem_type_ref_layout", {
        [Ty.TypeRefGlobal] = function(ref, env)
            for i = 1, #env.layouts do
                local layout = env.layouts[i]
                if pvm.classof(layout) == Sem.LayoutNamed and layout.module_name == ref.module_name and layout.type_name == ref.type_name then
                    return pvm.once(layout)
                end
            end
            return pvm.empty()
        end,
        [Ty.TypeRefLocal] = function(ref, env)
            for i = 1, #env.layouts do
                local layout = env.layouts[i]
                if pvm.classof(layout) == Sem.LayoutLocal and layout.sym == ref.sym then
                    return pvm.once(layout)
                end
            end
            return pvm.empty()
        end,
        [Ty.TypeRefPath] = function(ref, env)
            if #ref.path.parts == 1 then
                local name = ref.path.parts[1].text
                for i = 1, #env.layouts do
                    local layout = env.layouts[i]
                    if pvm.classof(layout) == Sem.LayoutNamed and layout.type_name == name then return pvm.once(layout) end
                end
            end
            return pvm.empty()
        end,
        [Ty.TypeRefSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    type_layout = pvm.phase("moonlift_sem_type_layout", {
        [Ty.TNamed] = function(self, env, target) return type_ref_layout(self.ref, env) end,
        [Ty.TScalar] = function() return pvm.empty() end,
        [Ty.TPtr] = function() return pvm.empty() end,
        [Ty.TArray] = function() return pvm.empty() end,
        [Ty.TSlice] = function() return pvm.empty() end,
        [Ty.TView] = function() return pvm.empty() end,
        [Ty.TLease] = function() return pvm.empty() end,
        [Ty.TOwned] = function() return pvm.empty() end,
        [Ty.TAccess] = function() return pvm.empty() end,
        [Ty.THandle] = function() return pvm.empty() end,
        [Ty.TFunc] = function() return pvm.empty() end,
        [Ty.TClosure] = function() return pvm.empty() end,
        [Ty.TSlot] = function() return pvm.empty() end,
        [Ty.TCType] = function() return pvm.empty() end,
        [Ty.TCFuncPtr] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    field_in_layout = pvm.phase("moonlift_sem_field_in_layout", {
        [Sem.LayoutNamed] = function(layout, field_name)
            for i = 1, #layout.fields do
                local field = layout.fields[i]
                if field.field_name == field_name then
                    return pvm.once(field)
                end
            end
            return pvm.empty()
        end,
        [Sem.LayoutLocal] = function(layout, field_name)
            for i = 1, #layout.fields do
                local field = layout.fields[i]
                if field.field_name == field_name then
                    return pvm.once(field)
                end
            end
            return pvm.empty()
        end,
    }, { args_cache = "last" })

    local function storage_for_type(ty)
        if pvm.classof(ty) == Ty.TScalar then return H.HostRepScalar(ty.scalar) end
        if pvm.classof(ty) == Ty.TPtr then return H.HostRepPtr(ty.elem) end
        if pvm.classof(ty) == Ty.TView then return H.HostRepView(ty.elem) end
        if pvm.classof(ty) == Ty.TAccess then return storage_for_type(ty.base) end
        return H.HostRepOpaque("sem_layout")
    end

    resolve_field_ref = pvm.phase("moonlift_sem_resolve_field_ref", {
        [Sem.FieldByOffset] = function(field) return pvm.once(field) end,
        [Sem.FieldByName] = function(field, base_ty, env)
            local layout = maybe_one(type_layout(base_ty, env))
            if layout == nil then return pvm.once(field) end
            local resolved = maybe_one(field_in_layout(layout, field.field_name))
            if resolved == nil then return pvm.once(field) end
            return pvm.once(Sem.FieldByOffset(resolved.field_name, resolved.offset, resolved.ty, storage_for_type(resolved.ty)))
        end,
    }, { args_cache = "last" })

    local function type_of_place(place)
        local h = place.h
        local cls = pvm.classof(h)
        if cls == Tr.PlaceTyped or cls == Tr.PlaceOpen then return h.ty end
        return nil
    end

    resolve_index_base = pvm.phase("moonlift_sem_layout_index_base", {
        [Tr.IndexBaseExpr] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env, target) })) end,
        [Tr.IndexBasePlace] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_place, self.base, env, target) })) end,
        [Tr.IndexBaseView] = function(self, env, target) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env, target) })) end,
    }, { args_cache = "last" })

    resolve_place = pvm.phase("moonlift_sem_layout_place", {
        [Tr.PlaceRef] = function(self) return pvm.once(self) end,
        [Tr.PlaceDeref] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env, target) })) end,
        [Tr.PlaceDot] = function(self, env, target)
            local base = one(resolve_place, self.base, env, target)
            local base_ty = type_of_place(base)
            local lookup_ty = base_ty
            if lookup_ty ~= nil and pvm.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            if lookup_ty ~= nil then
                local field = pvm.one(resolve_field_ref(Sem.FieldByName(self.name, lookup_ty), lookup_ty, env))
                if pvm.classof(field) == Sem.FieldByOffset then return pvm.once(Tr.PlaceField(Tr.PlaceTyped(field.ty), base, field)) end
            end
            return pvm.once(pvm.with(self, { base = base }))
        end,
        [Tr.PlaceField] = function(self, env, target)
            local base = one(resolve_place, self.base, env, target)
            local base_ty = type_of_place(base)
            if base_ty ~= nil and pvm.classof(base_ty) == Ty.TPtr then base_ty = base_ty.elem end
            local field = self.field
            if base_ty ~= nil then field = pvm.one(resolve_field_ref(self.field, base_ty, env)) end
            return pvm.once(pvm.with(self, { base = base, field = field }))
        end,
        [Tr.PlaceIndex] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_index_base, self.base, env, target), index = one(resolve_expr, self.index, env, target) })) end,
        [Tr.PlaceSlotValue] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_view = pvm.phase("moonlift_sem_layout_view", {
        [Tr.ViewFromExpr] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env, target) })) end,
        [Tr.ViewContiguous] = function(self, env, target) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target) })) end,
        [Tr.ViewStrided] = function(self, env, target) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target) })) end,
        [Tr.ViewRestrided] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env, target), stride = one(resolve_expr, self.stride, env, target) })) end,
        [Tr.ViewWindow] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env, target), start = one(resolve_expr, self.start, env, target), len = one(resolve_expr, self.len, env, target) })) end,
        [Tr.ViewRowBase] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env, target), row_offset = one(resolve_expr, self.row_offset, env, target) })) end,
        [Tr.ViewInterleaved] = function(self, env, target) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) })) end,
        [Tr.ViewInterleavedView] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env, target), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) })) end,
    }, { args_cache = "last" })

    resolve_domain = pvm.phase("moonlift_sem_layout_domain", {
        [Tr.DomainRange] = function(self, env, target) return pvm.once(pvm.with(self, { stop = one(resolve_expr, self.stop, env, target) })) end,
        [Tr.DomainRange2] = function(self, env, target) return pvm.once(pvm.with(self, { start = one(resolve_expr, self.start, env, target), stop = one(resolve_expr, self.stop, env, target) })) end,
        [Tr.DomainZipEqValues] = function(self, env, target) return pvm.once(pvm.with(self, { values = map_exprs(self.values, env, target) })) end,
        [Tr.DomainValue] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.DomainView] = function(self, env, target) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env, target) })) end,
        [Tr.DomainZipEqViews] = function(self, env, target) local views = {}; for i = 1, #self.views do views[#views + 1] = one(resolve_view, self.views[i], env, target) end; return pvm.once(pvm.with(self, { views = views })) end,
        [Tr.DomainSlotValue] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_expr = pvm.phase("moonlift_sem_layout_expr", {
        [Tr.ExprLit] = function(self) return pvm.once(self) end,
        [Tr.ExprRef] = function(self) return pvm.once(self) end,
        [Tr.ExprDot] = function(self, env, target)
            local base = one(resolve_expr, self.base, env, target)
            local h = base.h
            local base_ty = nil
            local h_cls = pvm.classof(h)
            if h_cls == Tr.ExprTyped or h_cls == Tr.ExprOpen then base_ty = h.ty end
            local lookup_ty = base_ty
            if lookup_ty ~= nil and pvm.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            if lookup_ty ~= nil then
                local field = pvm.one(resolve_field_ref(Sem.FieldByName(self.name, lookup_ty), lookup_ty, env))
                if pvm.classof(field) == Sem.FieldByOffset then return pvm.once(Tr.ExprField(Tr.ExprTyped(field.ty), base, field)) end
            end
            return pvm.once(pvm.with(self, { base = base }))
        end,
        [Tr.ExprUnary] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprBinary] = function(self, env, target) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) })) end,
        [Tr.ExprCompare] = function(self, env, target) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) })) end,
        [Tr.ExprLogic] = function(self, env, target) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) })) end,
        [Tr.ExprCast] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprMachineCast] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprIntrinsic] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env, target) })) end,
        [Tr.ExprAddrOf] = function(self, env, target) return pvm.once(pvm.with(self, { place = one(resolve_place, self.place, env, target) })) end,
        [Tr.ExprDeref] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprCall] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env, target) })) end,
        [Tr.ExprLen] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprField] = function(self, env, target)
            local base = one(resolve_expr, self.base, env, target)
            local h = base.h
            local base_ty = nil
            local h_cls = pvm.classof(h)
            if h_cls == Tr.ExprTyped or h_cls == Tr.ExprOpen then base_ty = h.ty end
            if base_ty ~= nil and pvm.classof(base_ty) == Ty.TPtr then base_ty = base_ty.elem end
            local field = self.field
            if base_ty ~= nil then field = pvm.one(resolve_field_ref(self.field, base_ty, env)) end
            return pvm.once(pvm.with(self, { base = base, field = field }))
        end,
        [Tr.ExprIndex] = function(self, env, target) return pvm.once(pvm.with(self, { base = one(resolve_index_base, self.base, env, target), index = one(resolve_expr, self.index, env, target) })) end,
        [Tr.ExprAgg] = function(self, env, target) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { value = one(resolve_expr, self.fields[i].value, env, target) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
        [Tr.ExprArray] = function(self, env, target) return pvm.once(pvm.with(self, { elems = map_exprs(self.elems, env, target) })) end,
        [Tr.ExprIf] = function(self, env, target) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) })) end,
        [Tr.ExprSelect] = function(self, env, target) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) })) end,
        [Tr.ExprSwitch] = function(self, env, target) local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target), result = one(resolve_expr, self.arms[i].result, env, target) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = pvm.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target), result = one(resolve_expr, self.variant_arms[i].result, env, target) }) end; return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body or {}, env, target), default_expr = one(resolve_expr, self.default_expr, env, target) })) end,
        [Tr.ExprControl] = function(self, env, target) return pvm.once(pvm.with(self, { region = one(resolve_control_expr_region, self.region, env, target) })) end,
        [Tr.ExprBlock] = function(self, env, target) return pvm.once(pvm.with(self, { stmts = map_stmts(self.stmts, env, target), result = one(resolve_expr, self.result, env, target) })) end,
        [Tr.ExprClosure] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
        [Tr.ExprView] = function(self, env, target) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env, target) })) end,
        [Tr.ExprLoad] = function(self, env, target) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env, target) })) end,
        [Tr.ExprAtomicLoad] = function(self, env, target) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env, target) })) end,
        [Tr.ExprAtomicRmw] = function(self, env, target) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprAtomicCas] = function(self, env, target) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env, target), expected = one(resolve_expr, self.expected, env, target), replacement = one(resolve_expr, self.replacement, env, target) })) end,
        [Tr.ExprSizeOf] = function(self, env, target)
            local layout_api = require("moonlift.type_size_align").Define(T)
            local result = layout_api.result(self.ty, env, target)
            if pvm.classof(result) == Ty.TypeMemLayoutKnown then
                local size = tostring(result.layout.size)
                return pvm.once(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(size)))
            end
            return pvm.once(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("0")))
        end,
        [Tr.ExprAlignOf] = function(self, env, target)
            local layout_api = require("moonlift.type_size_align").Define(T)
            local result = layout_api.result(self.ty, env, target)
            if pvm.classof(result) == Ty.TypeMemLayoutKnown then
                local align = tostring(result.layout.align)
                return pvm.once(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(align)))
            end
            return pvm.once(Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("1")))
        end,
        [Tr.ExprNull] = function(self) return pvm.once(self) end,
        [Tr.ExprIsNull] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ExprSlotValue] = function(self) return pvm.once(self) end,
        [Tr.ExprUseExprFrag] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env, target) })) end,
        [Tr.ExprCtor] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env, target) })) end,
    }, { args_cache = "last" })

    local function resolve_entry_block(block, env, target)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { init = one(resolve_expr, block.params[i].init, env, target) }) end
        return pvm.with(block, { params = params, body = map_stmts(block.body, env, target) })
    end

    local function resolve_control_block(block, env, target)
        return pvm.with(block, { body = map_stmts(block.body, env, target) })
    end

    resolve_control_stmt_region = pvm.phase("moonlift_sem_layout_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, env, target)
            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
            return pvm.once(pvm.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    resolve_control_expr_region = pvm.phase("moonlift_sem_layout_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, env, target)
            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
            return pvm.once(pvm.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    resolve_stmt = pvm.phase("moonlift_sem_layout_stmt", {
        [Tr.StmtLet] = function(self, env, target) return pvm.once(pvm.with(self, { init = one(resolve_expr, self.init, env, target) })) end,
        [Tr.StmtVar] = function(self, env, target) return pvm.once(pvm.with(self, { init = one(resolve_expr, self.init, env, target) })) end,
        [Tr.StmtSet] = function(self, env, target) return pvm.once(pvm.with(self, { place = one(resolve_place, self.place, env, target), value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.StmtAtomicStore] = function(self, env, target) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.StmtAtomicFence] = function(self) return pvm.once(self) end,
        [Tr.StmtExpr] = function(self, env, target) return pvm.once(pvm.with(self, { expr = one(resolve_expr, self.expr, env, target) })) end,
        [Tr.StmtAssert] = function(self, env, target) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env, target) })) end,
        [Tr.StmtIf] = function(self, env, target) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env, target), then_body = map_stmts(self.then_body, env, target), else_body = map_stmts(self.else_body, env, target) })) end,
        [Tr.StmtSwitch] = function(self, env, target) local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = pvm.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target) }) end; return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body, env, target) })) end,
        [Tr.StmtJump] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_jump_args(self.args, env, target) })) end,
        [Tr.StmtJumpCont] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_jump_args(self.args, env, target) })) end,
        [Tr.StmtYieldVoid] = function(self) return pvm.once(self) end,
        [Tr.StmtYieldValue] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.StmtReturnVoid] = function(self) return pvm.once(self) end,
        [Tr.StmtReturnValue] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.StmtControl] = function(self, env, target) return pvm.once(pvm.with(self, { region = one(resolve_control_stmt_region, self.region, env, target) })) end,
        [Tr.StmtTrap] = function(self) return pvm.once(self) end,
        [Tr.StmtUseRegionSlot] = function(self) return pvm.once(self) end,
        [Tr.StmtUseRegionFrag] = function(self, env, target) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env, target) })) end,
    }, { args_cache = "last" })

    resolve_func = pvm.phase("moonlift_sem_layout_func", {
        [Tr.FuncLocal] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
        [Tr.FuncExport] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
        [Tr.FuncLocalContract] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
        [Tr.FuncExportContract] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
        [Tr.FuncOpen] = function(self, env, target) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env, target) })) end,
    }, { args_cache = "last" })

    resolve_const = pvm.phase("moonlift_sem_layout_const", {
        [Tr.ConstItem] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.ConstItemOpen] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
    }, { args_cache = "last" })

    resolve_static = pvm.phase("moonlift_sem_layout_static", {
        [Tr.StaticItem] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
        [Tr.StaticItemOpen] = function(self, env, target) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env, target) })) end,
    }, { args_cache = "last" })

    resolve_type_decl = pvm.phase("moonlift_sem_layout_type_decl", {
        [Tr.TypeDeclStruct] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclUnion] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclEnumSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclHandle] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenStruct] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenUnion] = function(self) return pvm.once(self) end,
    })

    resolve_item = pvm.phase("moonlift_sem_layout_item", {
        [Tr.ItemFunc] = function(self, env, target) return pvm.once(pvm.with(self, { func = one(resolve_func, self.func, env, target) })) end,
        [Tr.ItemExtern] = function(self) return pvm.once(self) end,
        [Tr.ItemConst] = function(self, env, target) return pvm.once(pvm.with(self, { c = one(resolve_const, self.c, env, target) })) end,
        [Tr.ItemStatic] = function(self, env, target) return pvm.once(pvm.with(self, { s = one(resolve_static, self.s, env, target) })) end,
        [Tr.ItemImport] = function(self) return pvm.once(self) end,
        [Tr.ItemType] = function(self, env, target) return pvm.once(pvm.with(self, { t = one(resolve_type_decl, self.t, env, target) })) end,
        [Tr.ItemRegionFrag] = function(self) return pvm.once(self) end,
        [Tr.ItemExprFrag] = function(self) return pvm.once(self) end,
        [Tr.ItemUseTypeDeclSlot] = function(self) return pvm.once(self) end,
        [Tr.ItemUseItemsSlot] = function(self) return pvm.once(self) end,
        [Tr.ItemUseModule] = function(self, env, target) return pvm.once(pvm.with(self, { module = one(resolve_module, self.module, env, target) })) end,
        [Tr.ItemUseModuleSlot] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_module = pvm.phase("moonlift_sem_layout_module", {
        [Tr.Module] = function(module, env, target)
            local resolved_env = env
            if resolved_env == nil or #resolved_env.layouts == 0 then
                resolved_env = Sem.LayoutEnv(module_type_api.env(module, target).layouts)
            end
            return pvm.once(pvm.with(module, { items = map_items(module.items, resolved_env, target) }))
        end,
    }, { args_cache = "last" })

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
        field = function(field, base_ty, env) return pvm.one(resolve_field_ref(field, base_ty, env or empty_env())) end,
        expr = function(expr, env, target) return one(resolve_expr, expr, env or empty_env(), target) end,
        place = function(place, env, target) return one(resolve_place, place, env or empty_env(), target) end,
        module = function(module, env, target) return one(resolve_module, module, env, target) end,
    }
end

return M
