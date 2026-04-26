local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local Sem = T.Moon2Sem
    local Tr = T.Moon2Tree
    local H = T.Moon2Host

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

    local function one(phase, node, env)
        return pvm.one(phase(node, env))
    end

    local function maybe_one(g, p, c)
        local values = pvm.drain(g, p, c)
        if #values == 0 then return nil end
        return values[1]
    end

    local function map_exprs(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_expr, xs[i], env) end
        return out
    end

    local function map_stmts(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_stmt, xs[i], env) end
        return out
    end

    local function map_jump_args(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = pvm.with(xs[i], { value = one(resolve_expr, xs[i].value, env) }) end
        return out
    end

    local function map_items(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_item, xs[i], env) end
        return out
    end

    type_ref_layout = pvm.phase("moon2_sem_type_ref_layout", {
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
        [Ty.TypeRefPath] = function() return pvm.empty() end,
        [Ty.TypeRefSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    type_layout = pvm.phase("moon2_sem_type_layout", {
        [Ty.TNamed] = function(self, env) return type_ref_layout(self.ref, env) end,
        [Ty.TScalar] = function() return pvm.empty() end,
        [Ty.TPtr] = function() return pvm.empty() end,
        [Ty.TArray] = function() return pvm.empty() end,
        [Ty.TSlice] = function() return pvm.empty() end,
        [Ty.TView] = function() return pvm.empty() end,
        [Ty.TFunc] = function() return pvm.empty() end,
        [Ty.TClosure] = function() return pvm.empty() end,
        [Ty.TSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    field_in_layout = pvm.phase("moon2_sem_field_in_layout", {
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
        return H.HostRepOpaque("sem_layout")
    end

    resolve_field_ref = pvm.phase("moon2_sem_resolve_field_ref", {
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
        if cls == Tr.PlaceTyped or cls == Tr.PlaceOpen or cls == Tr.PlaceSem then return h.ty end
        return nil
    end

    resolve_index_base = pvm.phase("moon2_sem_layout_index_base", {
        [Tr.IndexBaseExpr] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env) })) end,
        [Tr.IndexBasePlace] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_place, self.base, env) })) end,
        [Tr.IndexBaseView] = function(self, env) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env) })) end,
    }, { args_cache = "last" })

    resolve_place = pvm.phase("moon2_sem_layout_place", {
        [Tr.PlaceRef] = function(self) return pvm.once(self) end,
        [Tr.PlaceDeref] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env) })) end,
        [Tr.PlaceDot] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_place, self.base, env) })) end,
        [Tr.PlaceField] = function(self, env)
            local base = one(resolve_place, self.base, env)
            local base_ty = type_of_place(base)
            local field = self.field
            if base_ty ~= nil then field = pvm.one(resolve_field_ref(self.field, base_ty, env)) end
            return pvm.once(pvm.with(self, { base = base, field = field }))
        end,
        [Tr.PlaceIndex] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_index_base, self.base, env), index = one(resolve_expr, self.index, env) })) end,
        [Tr.PlaceSlotValue] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_view = pvm.phase("moon2_sem_layout_view", {
        [Tr.ViewFromExpr] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env) })) end,
        [Tr.ViewContiguous] = function(self, env) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env), len = one(resolve_expr, self.len, env) })) end,
        [Tr.ViewStrided] = function(self, env) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env), len = one(resolve_expr, self.len, env), stride = one(resolve_expr, self.stride, env) })) end,
        [Tr.ViewRestrided] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env), stride = one(resolve_expr, self.stride, env) })) end,
        [Tr.ViewWindow] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env), start = one(resolve_expr, self.start, env), len = one(resolve_expr, self.len, env) })) end,
        [Tr.ViewRowBase] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env), row_offset = one(resolve_expr, self.row_offset, env) })) end,
        [Tr.ViewInterleaved] = function(self, env) return pvm.once(pvm.with(self, { data = one(resolve_expr, self.data, env), len = one(resolve_expr, self.len, env), stride = one(resolve_expr, self.stride, env), lane = one(resolve_expr, self.lane, env) })) end,
        [Tr.ViewInterleavedView] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_view, self.base, env), stride = one(resolve_expr, self.stride, env), lane = one(resolve_expr, self.lane, env) })) end,
    }, { args_cache = "last" })

    resolve_domain = pvm.phase("moon2_sem_layout_domain", {
        [Tr.DomainRange] = function(self, env) return pvm.once(pvm.with(self, { stop = one(resolve_expr, self.stop, env) })) end,
        [Tr.DomainRange2] = function(self, env) return pvm.once(pvm.with(self, { start = one(resolve_expr, self.start, env), stop = one(resolve_expr, self.stop, env) })) end,
        [Tr.DomainZipEqValues] = function(self, env) return pvm.once(pvm.with(self, { values = map_exprs(self.values, env) })) end,
        [Tr.DomainValue] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.DomainView] = function(self, env) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env) })) end,
        [Tr.DomainZipEqViews] = function(self, env) local views = {}; for i = 1, #self.views do views[#views + 1] = one(resolve_view, self.views[i], env) end; return pvm.once(pvm.with(self, { views = views })) end,
        [Tr.DomainSlotValue] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_expr = pvm.phase("moon2_sem_layout_expr", {
        [Tr.ExprLit] = function(self) return pvm.once(self) end,
        [Tr.ExprRef] = function(self) return pvm.once(self) end,
        [Tr.ExprDot] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_expr, self.base, env) })) end,
        [Tr.ExprUnary] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ExprBinary] = function(self, env) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env), rhs = one(resolve_expr, self.rhs, env) })) end,
        [Tr.ExprCompare] = function(self, env) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env), rhs = one(resolve_expr, self.rhs, env) })) end,
        [Tr.ExprLogic] = function(self, env) return pvm.once(pvm.with(self, { lhs = one(resolve_expr, self.lhs, env), rhs = one(resolve_expr, self.rhs, env) })) end,
        [Tr.ExprCast] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ExprMachineCast] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ExprIntrinsic] = function(self, env) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env) })) end,
        [Tr.ExprAddrOf] = function(self, env) return pvm.once(pvm.with(self, { place = one(resolve_place, self.place, env) })) end,
        [Tr.ExprDeref] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ExprCall] = function(self, env) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env) })) end,
        [Tr.ExprLen] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ExprField] = function(self, env)
            local base = one(resolve_expr, self.base, env)
            local h = base.h
            local base_ty = nil
            local h_cls = pvm.classof(h)
            if h_cls == Tr.ExprTyped or h_cls == Tr.ExprOpen or h_cls == Tr.ExprSem or h_cls == Tr.ExprCode then base_ty = h.ty end
            local field = self.field
            if base_ty ~= nil then field = pvm.one(resolve_field_ref(self.field, base_ty, env)) end
            return pvm.once(pvm.with(self, { base = base, field = field }))
        end,
        [Tr.ExprIndex] = function(self, env) return pvm.once(pvm.with(self, { base = one(resolve_index_base, self.base, env), index = one(resolve_expr, self.index, env) })) end,
        [Tr.ExprAgg] = function(self, env) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { value = one(resolve_expr, self.fields[i].value, env) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
        [Tr.ExprArray] = function(self, env) return pvm.once(pvm.with(self, { elems = map_exprs(self.elems, env) })) end,
        [Tr.ExprIf] = function(self, env) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env), then_expr = one(resolve_expr, self.then_expr, env), else_expr = one(resolve_expr, self.else_expr, env) })) end,
        [Tr.ExprSelect] = function(self, env) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env), then_expr = one(resolve_expr, self.then_expr, env), else_expr = one(resolve_expr, self.else_expr, env) })) end,
        [Tr.ExprSwitch] = function(self, env) local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = map_stmts(self.arms[i].body, env), result = one(resolve_expr, self.arms[i].result, env) }) end; return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env), arms = arms, default_expr = one(resolve_expr, self.default_expr, env) })) end,
        [Tr.ExprControl] = function(self, env) return pvm.once(pvm.with(self, { region = one(resolve_control_expr_region, self.region, env) })) end,
        [Tr.ExprBlock] = function(self, env) return pvm.once(pvm.with(self, { stmts = map_stmts(self.stmts, env), result = one(resolve_expr, self.result, env) })) end,
        [Tr.ExprClosure] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
        [Tr.ExprView] = function(self, env) return pvm.once(pvm.with(self, { view = one(resolve_view, self.view, env) })) end,
        [Tr.ExprLoad] = function(self, env) return pvm.once(pvm.with(self, { addr = one(resolve_expr, self.addr, env) })) end,
        [Tr.ExprSlotValue] = function(self) return pvm.once(self) end,
        [Tr.ExprUseExprFrag] = function(self, env) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env) })) end,
    }, { args_cache = "last" })

    local function resolve_entry_block(block, env)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { init = one(resolve_expr, block.params[i].init, env) }) end
        return pvm.with(block, { params = params, body = map_stmts(block.body, env) })
    end

    local function resolve_control_block(block, env)
        return pvm.with(block, { body = map_stmts(block.body, env) })
    end

    resolve_control_stmt_region = pvm.phase("moon2_sem_layout_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, env)
            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env) end
            return pvm.once(pvm.with(self, { entry = resolve_entry_block(self.entry, env), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    resolve_control_expr_region = pvm.phase("moon2_sem_layout_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, env)
            local blocks = {}
            for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env) end
            return pvm.once(pvm.with(self, { entry = resolve_entry_block(self.entry, env), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    resolve_stmt = pvm.phase("moon2_sem_layout_stmt", {
        [Tr.StmtLet] = function(self, env) return pvm.once(pvm.with(self, { init = one(resolve_expr, self.init, env) })) end,
        [Tr.StmtVar] = function(self, env) return pvm.once(pvm.with(self, { init = one(resolve_expr, self.init, env) })) end,
        [Tr.StmtSet] = function(self, env) return pvm.once(pvm.with(self, { place = one(resolve_place, self.place, env), value = one(resolve_expr, self.value, env) })) end,
        [Tr.StmtExpr] = function(self, env) return pvm.once(pvm.with(self, { expr = one(resolve_expr, self.expr, env) })) end,
        [Tr.StmtAssert] = function(self, env) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env) })) end,
        [Tr.StmtIf] = function(self, env) return pvm.once(pvm.with(self, { cond = one(resolve_expr, self.cond, env), then_body = map_stmts(self.then_body, env), else_body = map_stmts(self.else_body, env) })) end,
        [Tr.StmtSwitch] = function(self, env) local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = map_stmts(self.arms[i].body, env) }) end; return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env), arms = arms, default_body = map_stmts(self.default_body, env) })) end,
        [Tr.StmtJump] = function(self, env) return pvm.once(pvm.with(self, { args = map_jump_args(self.args, env) })) end,
        [Tr.StmtJumpCont] = function(self, env) return pvm.once(pvm.with(self, { args = map_jump_args(self.args, env) })) end,
        [Tr.StmtYieldVoid] = function(self) return pvm.once(self) end,
        [Tr.StmtYieldValue] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.StmtReturnVoid] = function(self) return pvm.once(self) end,
        [Tr.StmtReturnValue] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.StmtControl] = function(self, env) return pvm.once(pvm.with(self, { region = one(resolve_control_stmt_region, self.region, env) })) end,
        [Tr.StmtUseRegionSlot] = function(self) return pvm.once(self) end,
        [Tr.StmtUseRegionFrag] = function(self, env) return pvm.once(pvm.with(self, { args = map_exprs(self.args, env) })) end,
    }, { args_cache = "last" })

    resolve_func = pvm.phase("moon2_sem_layout_func", {
        [Tr.FuncLocal] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
        [Tr.FuncExport] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
        [Tr.FuncLocalContract] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
        [Tr.FuncExportContract] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
        [Tr.FuncOpen] = function(self, env) return pvm.once(pvm.with(self, { body = map_stmts(self.body, env) })) end,
    }, { args_cache = "last" })

    resolve_const = pvm.phase("moon2_sem_layout_const", {
        [Tr.ConstItem] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.ConstItemOpen] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
    }, { args_cache = "last" })

    resolve_static = pvm.phase("moon2_sem_layout_static", {
        [Tr.StaticItem] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
        [Tr.StaticItemOpen] = function(self, env) return pvm.once(pvm.with(self, { value = one(resolve_expr, self.value, env) })) end,
    }, { args_cache = "last" })

    resolve_type_decl = pvm.phase("moon2_sem_layout_type_decl", {
        [Tr.TypeDeclStruct] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclUnion] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclEnumSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenStruct] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenUnion] = function(self) return pvm.once(self) end,
    })

    resolve_item = pvm.phase("moon2_sem_layout_item", {
        [Tr.ItemFunc] = function(self, env) return pvm.once(pvm.with(self, { func = one(resolve_func, self.func, env) })) end,
        [Tr.ItemExtern] = function(self) return pvm.once(self) end,
        [Tr.ItemConst] = function(self, env) return pvm.once(pvm.with(self, { c = one(resolve_const, self.c, env) })) end,
        [Tr.ItemStatic] = function(self, env) return pvm.once(pvm.with(self, { s = one(resolve_static, self.s, env) })) end,
        [Tr.ItemImport] = function(self) return pvm.once(self) end,
        [Tr.ItemType] = function(self, env) return pvm.once(pvm.with(self, { t = one(resolve_type_decl, self.t, env) })) end,
        [Tr.ItemUseTypeDeclSlot] = function(self) return pvm.once(self) end,
        [Tr.ItemUseItemsSlot] = function(self) return pvm.once(self) end,
        [Tr.ItemUseModule] = function(self, env) return pvm.once(pvm.with(self, { module = one(resolve_module, self.module, env) })) end,
        [Tr.ItemUseModuleSlot] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    resolve_module = pvm.phase("moon2_sem_layout_module", {
        [Tr.Module] = function(module, env) return pvm.once(pvm.with(module, { items = map_items(module.items, env) })) end,
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
        expr = function(expr, env) return one(resolve_expr, expr, env or empty_env()) end,
        place = function(place, env) return one(resolve_place, place, env or empty_env()) end,
        module = function(module, env) return one(resolve_module, module, env or empty_env()) end,
    }
end

return M
