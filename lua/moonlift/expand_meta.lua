local pvm = require("pvm")

local M = {}

local function map_array(src, fn)
    local out = {}
    if src == nil then return out end
    for i = 1, #src do out[i] = fn(src[i], i) end
    return out
end

local function append_all(out, src)
    for i = 1, #src do out[#out + 1] = src[i] end
    return out
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    if Meta == nil then error("expand_meta: MoonliftMeta ASDL module is not defined", 2) end

    local wrap_slot
    local slot_value_type
    local slot_value_expr
    local slot_value_place
    local slot_value_domain
    local slot_value_region
    local slot_value_func
    local slot_value_const
    local slot_value_static
    local slot_value_type_decl
    local slot_value_items
    local slot_value_module

    local expand_type
    local expand_import
    local expand_layout
    local expand_open_set
    local expand_binding
    local expand_place
    local expand_index_base
    local expand_domain
    local expand_loop
    local expand_expr
    local expand_stmt
    local expand_func
    local expand_extern_func
    local expand_const
    local expand_static
    local expand_import_item
    local expand_type_decl
    local expand_item
    local expand_module

    local function one(boundary, node, env)
        if env ~= nil then return pvm.one(boundary(node, env)) end
        return pvm.one(boundary(node))
    end
    local function one_wrap_slot(node) return pvm.one(wrap_slot(node)) end
    local function one_type(node, env) return one(expand_type, node, env) end
    local function one_import(node, env) return one(expand_import, node, env) end
    local function one_layout(node, env) return one(expand_layout, node, env) end
    local function one_open_set(node, env) return one(expand_open_set, node, env) end
    local function one_binding(node, env) return one(expand_binding, node, env) end
    local function one_place(node, env) return one(expand_place, node, env) end
    local function one_index_base(node, env) return one(expand_index_base, node, env) end
    local function one_domain(node, env) return one(expand_domain, node, env) end
    local function one_loop(node, env) return one(expand_loop, node, env) end
    local function one_expr(node, env) return one(expand_expr, node, env) end
    local function one_func(node, env) return one(expand_func, node, env) end
    local function one_extern_func(node, env) return one(expand_extern_func, node, env) end
    local function one_const(node, env) return one(expand_const, node, env) end
    local function one_static(node, env) return one(expand_static, node, env) end
    local function one_import_item(node, env) return one(expand_import_item, node, env) end
    local function one_type_decl(node, env) return one(expand_type_decl, node, env) end
    local function one_module(node, env) return one(expand_module, node, env) end

    local function types(xs, env) return map_array(xs, function(x) return one_type(x, env) end) end
    local function exprs(xs, env) return map_array(xs, function(x) return one_expr(x, env) end) end
    local function field_types(xs, env) return map_array(xs, function(x) return Meta.MetaFieldType(x.field_name, one_type(x.ty, env)) end) end
    local function field_inits(xs, env) return map_array(xs, function(x) return Meta.MetaFieldInit(x.name, one_expr(x.value, env)) end) end
    local function params(xs, env) return map_array(xs, function(x) return Meta.MetaParam(x.key, x.name, one_type(x.ty, env)) end) end

    local function stmt_list(xs, env)
        local out = {}
        for i = 1, #(xs or {}) do
            local g, p, c = expand_stmt(xs[i], env)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function item_list(xs, env)
        local out = {}
        for i = 1, #(xs or {}) do
            local g, p, c = expand_item(xs[i], env)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function rebase(env, id)
        if env.rebase_prefix == nil or env.rebase_prefix == "" then return id end
        return env.rebase_prefix .. "." .. id
    end

    local function child_prefix(env, use_id)
        if env.rebase_prefix == nil or env.rebase_prefix == "" then return use_id end
        return env.rebase_prefix .. "." .. use_id
    end

    local function find_param(env, param)
        for i = 1, #env.params do
            local binding = env.params[i]
            if binding.param == param then return binding.value end
        end
        return nil
    end

    local function find_slot_value(env, slot)
        local wrapped = one_wrap_slot(slot)
        local bindings = env.fills.bindings
        for i = 1, #bindings do
            local binding = bindings[i]
            if binding.slot == wrapped then return binding.value end
        end
        return nil
    end

    local function is_slot_filled(env, slot)
        local wrapped = one_wrap_slot(slot)
        local bindings = env.fills.bindings
        for i = 1, #bindings do
            if bindings[i].slot == wrapped then return true end
        end
        return false
    end

    local function fillset(bindings)
        return Meta.MetaFillSet(bindings or {})
    end

    local function concat_fills(first, second)
        local out = {}
        for i = 1, #(first or {}) do out[#out + 1] = first[i] end
        if second ~= nil then
            for i = 1, #second.bindings do out[#out + 1] = second.bindings[i] end
        end
        return fillset(out)
    end

    wrap_slot = pvm.phase("expand_meta_wrap_slot", {
        [Meta.MetaTypeSlot] = function(self) return pvm.once(Meta.MetaSlotType(self)) end,
        [Meta.MetaExprSlot] = function(self) return pvm.once(Meta.MetaSlotExpr(self)) end,
        [Meta.MetaPlaceSlot] = function(self) return pvm.once(Meta.MetaSlotPlace(self)) end,
        [Meta.MetaDomainSlot] = function(self) return pvm.once(Meta.MetaSlotDomain(self)) end,
        [Meta.MetaRegionSlot] = function(self) return pvm.once(Meta.MetaSlotRegion(self)) end,
        [Meta.MetaFuncSlot] = function(self) return pvm.once(Meta.MetaSlotFunc(self)) end,
        [Meta.MetaConstSlot] = function(self) return pvm.once(Meta.MetaSlotConst(self)) end,
        [Meta.MetaStaticSlot] = function(self) return pvm.once(Meta.MetaSlotStatic(self)) end,
        [Meta.MetaTypeDeclSlot] = function(self) return pvm.once(Meta.MetaSlotTypeDecl(self)) end,
        [Meta.MetaItemsSlot] = function(self) return pvm.once(Meta.MetaSlotItems(self)) end,
        [Meta.MetaModuleSlot] = function(self) return pvm.once(Meta.MetaSlotModule(self)) end,
        [Meta.MetaSlotType] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotExpr] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotPlace] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotDomain] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotRegion] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotFunc] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotConst] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotStatic] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotTypeDecl] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotItems] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotModule] = function(self) return pvm.once(self) end,
    })

    slot_value_type = pvm.phase("expand_meta_slot_value_type", { [Meta.MetaSlotValueType] = function(self) return pvm.once(self.ty) end })
    slot_value_expr = pvm.phase("expand_meta_slot_value_expr", { [Meta.MetaSlotValueExpr] = function(self) return pvm.once(self.expr) end })
    slot_value_place = pvm.phase("expand_meta_slot_value_place", { [Meta.MetaSlotValuePlace] = function(self) return pvm.once(self.place) end })
    slot_value_domain = pvm.phase("expand_meta_slot_value_domain", { [Meta.MetaSlotValueDomain] = function(self) return pvm.once(self.domain) end })
    slot_value_region = pvm.phase("expand_meta_slot_value_region", { [Meta.MetaSlotValueRegion] = function(self) return pvm.once(self.body) end })
    slot_value_func = pvm.phase("expand_meta_slot_value_func", { [Meta.MetaSlotValueFunc] = function(self) return pvm.once(self.func) end })
    slot_value_const = pvm.phase("expand_meta_slot_value_const", { [Meta.MetaSlotValueConst] = function(self) return pvm.once(self.c) end })
    slot_value_static = pvm.phase("expand_meta_slot_value_static", { [Meta.MetaSlotValueStatic] = function(self) return pvm.once(self.s) end })
    slot_value_type_decl = pvm.phase("expand_meta_slot_value_type_decl", { [Meta.MetaSlotValueTypeDecl] = function(self) return pvm.once(self.t) end })
    slot_value_items = pvm.phase("expand_meta_slot_value_items", { [Meta.MetaSlotValueItems] = function(self) return pvm.once(self.items) end })
    slot_value_module = pvm.phase("expand_meta_slot_value_module", { [Meta.MetaSlotValueModule] = function(self) return pvm.once(self.module) end })

    expand_type = pvm.phase("expand_meta_type", {
        [Meta.MetaTVoid] = function(self) return pvm.once(self) end,
        [Meta.MetaTBool] = function(self) return pvm.once(self) end,
        [Meta.MetaTI8] = function(self) return pvm.once(self) end,
        [Meta.MetaTI16] = function(self) return pvm.once(self) end,
        [Meta.MetaTI32] = function(self) return pvm.once(self) end,
        [Meta.MetaTI64] = function(self) return pvm.once(self) end,
        [Meta.MetaTU8] = function(self) return pvm.once(self) end,
        [Meta.MetaTU16] = function(self) return pvm.once(self) end,
        [Meta.MetaTU32] = function(self) return pvm.once(self) end,
        [Meta.MetaTU64] = function(self) return pvm.once(self) end,
        [Meta.MetaTF32] = function(self) return pvm.once(self) end,
        [Meta.MetaTF64] = function(self) return pvm.once(self) end,
        [Meta.MetaTIndex] = function(self) return pvm.once(self) end,
        [Meta.MetaTPtr] = function(self, env) return pvm.once(Meta.MetaTPtr(one_type(self.elem, env))) end,
        [Meta.MetaTArray] = function(self, env) return pvm.once(Meta.MetaTArray(one_expr(self.count, env), one_type(self.elem, env))) end,
        [Meta.MetaTSlice] = function(self, env) return pvm.once(Meta.MetaTSlice(one_type(self.elem, env))) end,
        [Meta.MetaTView] = function(self, env) return pvm.once(Meta.MetaTView(one_type(self.elem, env))) end,
        [Meta.MetaTFunc] = function(self, env) return pvm.once(Meta.MetaTFunc(types(self.params, env), one_type(self.result, env))) end,
        [Meta.MetaTNamed] = function(self) return pvm.once(self) end,
        [Meta.MetaTLocalNamed] = function(self) return pvm.once(self) end,
        [Meta.MetaTSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(one_type(pvm.one(slot_value_type(value)), env))
        end,
    })

    expand_import = pvm.phase("expand_meta_value_import", {
        [Meta.MetaImportValue] = function(self, env) return pvm.once(Meta.MetaImportValue(self.key, self.name, one_type(self.ty, env))) end,
        [Meta.MetaImportGlobalFunc] = function(self, env) return pvm.once(Meta.MetaImportGlobalFunc(self.key, self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaImportGlobalConst] = function(self, env) return pvm.once(Meta.MetaImportGlobalConst(self.key, self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaImportGlobalStatic] = function(self, env) return pvm.once(Meta.MetaImportGlobalStatic(self.key, self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaImportExtern] = function(self, env) return pvm.once(Meta.MetaImportExtern(self.key, self.symbol, one_type(self.ty, env))) end,
    })

    expand_layout = pvm.phase("expand_meta_type_layout", {
        [Meta.MetaLayoutNamed] = function(self, env) return pvm.once(Meta.MetaLayoutNamed(self.module_name, self.type_name, field_types(self.fields, env))) end,
        [Meta.MetaLayoutLocal] = function(self, env) return pvm.once(Meta.MetaLayoutLocal(self.sym, field_types(self.fields, env))) end,
    })

    expand_open_set = pvm.phase("expand_meta_open_set", {
        [Meta.MetaOpenSet] = function(self, env)
            return pvm.once(Meta.MetaOpenSet(
                map_array(self.value_imports, function(x) return one_import(x, env) end),
                map_array(self.type_imports, function(x) return Meta.MetaTypeImport(x.key, x.local_name, one_type(x.ty, env)) end),
                map_array(self.layouts, function(x) return one_layout(x, env) end),
                (function()
                    local out = {}
                    for i = 1, #self.slots do
                        if not is_slot_filled(env, self.slots[i]) then
                            out[#out + 1] = one_wrap_slot(self.slots[i])
                        end
                    end
                    return out
                end)()
            ))
        end,
    })

    expand_binding = pvm.phase("expand_meta_binding", {
        [Meta.MetaBindParam] = function(self, env)
            local value = find_param(env, self.param)
            if value ~= nil then error("expand_meta: MetaBindParam should be replaced at expression position", 2) end
            return pvm.once(self)
        end,
        [Meta.MetaBindLocalValue] = function(self, env) return pvm.once(Meta.MetaBindLocalValue(rebase(env, self.id), self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLocalCell] = function(self, env) return pvm.once(Meta.MetaBindLocalCell(rebase(env, self.id), self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLoopCarry] = function(self, env) return pvm.once(Meta.MetaBindLoopCarry(rebase(env, self.loop_id), rebase(env, self.port_id), self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLoopIndex] = function(self, env) return pvm.once(Meta.MetaBindLoopIndex(rebase(env, self.loop_id), self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalFunc] = function(self, env) return pvm.once(Meta.MetaBindGlobalFunc(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalConst] = function(self, env) return pvm.once(Meta.MetaBindGlobalConst(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalStatic] = function(self, env) return pvm.once(Meta.MetaBindGlobalStatic(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindExtern] = function(self, env) return pvm.once(Meta.MetaBindExtern(self.symbol, one_type(self.ty, env))) end,
        [Meta.MetaBindImport] = function(self, env) return pvm.once(Meta.MetaBindImport(one_import(self.import, env))) end,
        [Meta.MetaBindFuncSym] = function(self, env) return pvm.once(Meta.MetaBindFuncSym(self.sym, one_type(self.ty, env))) end,
        [Meta.MetaBindExternSym] = function(self, env) return pvm.once(Meta.MetaBindExternSym(self.sym, one_type(self.ty, env))) end,
        [Meta.MetaBindConstSym] = function(self, env) return pvm.once(Meta.MetaBindConstSym(self.sym, one_type(self.ty, env))) end,
        [Meta.MetaBindStaticSym] = function(self, env) return pvm.once(Meta.MetaBindStaticSym(self.sym, one_type(self.ty, env))) end,
        [Meta.MetaBindFuncSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(Meta.MetaBindFuncSym(pvm.one(slot_value_func(value)).sym, self.slot.fn_ty))
        end,
        [Meta.MetaBindConstSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(Meta.MetaBindConstSym(pvm.one(slot_value_const(value)).sym, self.slot.ty))
        end,
        [Meta.MetaBindStaticSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(Meta.MetaBindStaticSym(pvm.one(slot_value_static(value)).sym, self.slot.ty))
        end,
    })

    expand_place = pvm.phase("expand_meta_place", {
        [Meta.MetaPlaceBinding] = function(self, env) return pvm.once(Meta.MetaPlaceBinding(one_binding(self.binding, env))) end,
        [Meta.MetaPlaceDeref] = function(self, env) return pvm.once(Meta.MetaPlaceDeref(one_expr(self.base, env), one_type(self.elem, env))) end,
        [Meta.MetaPlaceField] = function(self, env) return pvm.once(Meta.MetaPlaceField(one_place(self.base, env), self.name, one_type(self.ty, env))) end,
        [Meta.MetaPlaceIndex] = function(self, env) return pvm.once(Meta.MetaPlaceIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
        [Meta.MetaPlaceSlotValue] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(one_place(pvm.one(slot_value_place(value)), env))
        end,
    })

    expand_index_base = pvm.phase("expand_meta_index_base", {
        [Meta.MetaIndexBasePlace] = function(self, env) return pvm.once(Meta.MetaIndexBasePlace(one_place(self.base, env), one_type(self.elem, env))) end,
        [Meta.MetaIndexBaseView] = function(self, env) return pvm.once(Meta.MetaIndexBaseView(one_expr(self.base, env), one_type(self.elem, env))) end,
    })

    expand_domain = pvm.phase("expand_meta_domain", {
        [Meta.MetaDomainRange] = function(self, env) return pvm.once(Meta.MetaDomainRange(one_expr(self.stop, env))) end,
        [Meta.MetaDomainRange2] = function(self, env) return pvm.once(Meta.MetaDomainRange2(one_expr(self.start, env), one_expr(self.stop, env))) end,
        [Meta.MetaDomainZipEq] = function(self, env) return pvm.once(Meta.MetaDomainZipEq(exprs(self.values, env))) end,
        [Meta.MetaDomainValue] = function(self, env) return pvm.once(Meta.MetaDomainValue(one_expr(self.value, env))) end,
        [Meta.MetaDomainSlotValue] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(one_domain(pvm.one(slot_value_domain(value)), env))
        end,
    })

    local function carry_ports(xs, env) return map_array(xs, function(x) return Meta.MetaCarryPort(rebase(env, x.port_id), x.name, one_type(x.ty, env), one_expr(x.init, env)) end) end
    local function carry_updates(xs, env) return map_array(xs, function(x) return Meta.MetaCarryUpdate(rebase(env, x.port_id), one_expr(x.value, env)) end) end
    local function switch_stmt_arms(xs, env) return map_array(xs, function(x) return Meta.MetaSwitchStmtArm(one_expr(x.key, env), stmt_list(x.body, env)) end) end
    local function switch_expr_arms(xs, env) return map_array(xs, function(x) return Meta.MetaSwitchExprArm(one_expr(x.key, env), stmt_list(x.body, env), one_expr(x.result, env)) end) end

    expand_loop = pvm.phase("expand_meta_loop", {
        [Meta.MetaWhileStmt] = function(self, env) return pvm.once(Meta.MetaWhileStmt(rebase(env, self.loop_id), carry_ports(self.carries, env), one_expr(self.cond, env), stmt_list(self.body, env), carry_updates(self.next, env))) end,
        [Meta.MetaOverStmt] = function(self, env) return pvm.once(Meta.MetaOverStmt(rebase(env, self.loop_id), Meta.MetaIndexPort(self.index_port.name, one_type(self.index_port.ty, env)), one_domain(self.domain, env), carry_ports(self.carries, env), stmt_list(self.body, env), carry_updates(self.next, env))) end,
        [Meta.MetaWhileExpr] = function(self, env) return pvm.once(Meta.MetaWhileExpr(rebase(env, self.loop_id), carry_ports(self.carries, env), one_expr(self.cond, env), stmt_list(self.body, env), carry_updates(self.next, env), self.exit, one_expr(self.result, env))) end,
        [Meta.MetaOverExpr] = function(self, env) return pvm.once(Meta.MetaOverExpr(rebase(env, self.loop_id), Meta.MetaIndexPort(self.index_port.name, one_type(self.index_port.ty, env)), one_domain(self.domain, env), carry_ports(self.carries, env), stmt_list(self.body, env), carry_updates(self.next, env), self.exit, one_expr(self.result, env))) end,
    })

    expand_expr = pvm.phase("expand_meta_expr", {
        [Meta.MetaInt] = function(self, env) return pvm.once(Meta.MetaInt(self.raw, one_type(self.ty, env))) end,
        [Meta.MetaFloat] = function(self, env) return pvm.once(Meta.MetaFloat(self.raw, one_type(self.ty, env))) end,
        [Meta.MetaBool] = function(self, env) return pvm.once(Meta.MetaBool(self.value, one_type(self.ty, env))) end,
        [Meta.MetaNil] = function(self, env) return pvm.once(Meta.MetaNil(one_type(self.ty, env))) end,
        [Meta.MetaBindingExpr] = function(self, env)
            if self.binding.param ~= nil then
                local value = find_param(env, self.binding.param)
                if value ~= nil then return pvm.once(value) end
            end
            return pvm.once(Meta.MetaBindingExpr(one_binding(self.binding, env)))
        end,
        [Meta.MetaExprNeg] = function(self, env) return pvm.once(Meta.MetaExprNeg(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprNot] = function(self, env) return pvm.once(Meta.MetaExprNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprBNot] = function(self, env) return pvm.once(Meta.MetaExprBNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprAddrOf] = function(self, env) return pvm.once(Meta.MetaExprAddrOf(one_place(self.place, env), one_type(self.ty, env))) end,
        [Meta.MetaExprDeref] = function(self, env) return pvm.once(Meta.MetaExprDeref(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprAdd] = function(self, env) return pvm.once(Meta.MetaExprAdd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprSub] = function(self, env) return pvm.once(Meta.MetaExprSub(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprMul] = function(self, env) return pvm.once(Meta.MetaExprMul(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprDiv] = function(self, env) return pvm.once(Meta.MetaExprDiv(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprRem] = function(self, env) return pvm.once(Meta.MetaExprRem(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprEq] = function(self, env) return pvm.once(Meta.MetaExprEq(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprNe] = function(self, env) return pvm.once(Meta.MetaExprNe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLt] = function(self, env) return pvm.once(Meta.MetaExprLt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLe] = function(self, env) return pvm.once(Meta.MetaExprLe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprGt] = function(self, env) return pvm.once(Meta.MetaExprGt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprGe] = function(self, env) return pvm.once(Meta.MetaExprGe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprAnd] = function(self, env) return pvm.once(Meta.MetaExprAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprOr] = function(self, env) return pvm.once(Meta.MetaExprOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitAnd] = function(self, env) return pvm.once(Meta.MetaExprBitAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitOr] = function(self, env) return pvm.once(Meta.MetaExprBitOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitXor] = function(self, env) return pvm.once(Meta.MetaExprBitXor(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprShl] = function(self, env) return pvm.once(Meta.MetaExprShl(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLShr] = function(self, env) return pvm.once(Meta.MetaExprLShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprAShr] = function(self, env) return pvm.once(Meta.MetaExprAShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprCastTo] = function(self, env) return pvm.once(Meta.MetaExprCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprTruncTo] = function(self, env) return pvm.once(Meta.MetaExprTruncTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprZExtTo] = function(self, env) return pvm.once(Meta.MetaExprZExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprSExtTo] = function(self, env) return pvm.once(Meta.MetaExprSExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprBitcastTo] = function(self, env) return pvm.once(Meta.MetaExprBitcastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprSatCastTo] = function(self, env) return pvm.once(Meta.MetaExprSatCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprIntrinsicCall] = function(self, env) return pvm.once(Meta.MetaExprIntrinsicCall(self.op, one_type(self.ty, env), exprs(self.args, env))) end,
        [Meta.MetaCall] = function(self, env) return pvm.once(Meta.MetaCall(one_expr(self.callee, env), one_type(self.ty, env), exprs(self.args, env))) end,
        [Meta.MetaField] = function(self, env) return pvm.once(Meta.MetaField(one_expr(self.base, env), self.name, one_type(self.ty, env))) end,
        [Meta.MetaIndex] = function(self, env) return pvm.once(Meta.MetaIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
        [Meta.MetaAgg] = function(self, env) return pvm.once(Meta.MetaAgg(one_type(self.ty, env), field_inits(self.fields, env))) end,
        [Meta.MetaArrayLit] = function(self, env) return pvm.once(Meta.MetaArrayLit(one_type(self.ty, env), exprs(self.elems, env))) end,
        [Meta.MetaIfExpr] = function(self, env) return pvm.once(Meta.MetaIfExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaSelectExpr] = function(self, env) return pvm.once(Meta.MetaSelectExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaSwitchExpr] = function(self, env) return pvm.once(Meta.MetaSwitchExpr(one_expr(self.value, env), switch_expr_arms(self.arms, env), one_expr(self.default_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaExprLoop] = function(self, env) return pvm.once(Meta.MetaExprLoop(one_loop(self.loop, env), one_type(self.ty, env))) end,
        [Meta.MetaBlockExpr] = function(self, env) return pvm.once(Meta.MetaBlockExpr(stmt_list(self.stmts, env), one_expr(self.result, env), one_type(self.ty, env))) end,
        [Meta.MetaExprView] = function(self, env) return pvm.once(Meta.MetaExprView(one_expr(self.base, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewWindow] = function(self, env) return pvm.once(Meta.MetaExprViewWindow(one_expr(self.base, env), one_expr(self.start, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewFromPtr] = function(self, env) return pvm.once(Meta.MetaExprViewFromPtr(one_expr(self.ptr, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewFromPtrStrided] = function(self, env) return pvm.once(Meta.MetaExprViewFromPtrStrided(one_expr(self.ptr, env), one_expr(self.len, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewStrided] = function(self, env) return pvm.once(Meta.MetaExprViewStrided(one_expr(self.base, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewInterleaved] = function(self, env) return pvm.once(Meta.MetaExprViewInterleaved(one_expr(self.base, env), one_expr(self.stride, env), one_expr(self.lane, env), one_type(self.ty, env))) end,
        [Meta.MetaExprSlotValue] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(Meta.MetaExprSlotValue(self.slot, one_type(self.ty, env))) end
            return pvm.once(one_expr(pvm.one(slot_value_expr(value)), env))
        end,
        [Meta.MetaExprUseExprFrag] = function(self, env)
            local expanded_args = exprs(self.args, env)
            local param_bindings = map_array(self.frag.params, function(param, i)
                local arg = expanded_args[i]
                if arg == nil then error("expand_meta: missing argument " .. i .. " for expr fragment use '" .. self.use_id .. "'", 2) end
                return Meta.MetaParamBinding(param, arg)
            end)
            local child_env = Meta.MetaExpandEnv(concat_fills(self.fills, env.fills), param_bindings, child_prefix(env, self.use_id))
            return pvm.once(one_expr(self.frag.body, child_env))
        end,
    })

    expand_stmt = pvm.phase("expand_meta_stmt", {
        [Meta.MetaLet] = function(self, env) return pvm.once(Meta.MetaLet(rebase(env, self.id), self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Meta.MetaVar] = function(self, env) return pvm.once(Meta.MetaVar(rebase(env, self.id), self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Meta.MetaSet] = function(self, env) return pvm.once(Meta.MetaSet(one_place(self.place, env), one_expr(self.value, env))) end,
        [Meta.MetaExprStmt] = function(self, env) return pvm.once(Meta.MetaExprStmt(one_expr(self.expr, env))) end,
        [Meta.MetaAssert] = function(self, env) return pvm.once(Meta.MetaAssert(one_expr(self.cond, env))) end,
        [Meta.MetaIf] = function(self, env) return pvm.once(Meta.MetaIf(one_expr(self.cond, env), stmt_list(self.then_body, env), stmt_list(self.else_body, env))) end,
        [Meta.MetaSwitch] = function(self, env) return pvm.once(Meta.MetaSwitch(one_expr(self.value, env), switch_stmt_arms(self.arms, env), stmt_list(self.default_body, env))) end,
        [Meta.MetaReturnVoid] = function(self) return pvm.once(self) end,
        [Meta.MetaReturnValue] = function(self, env) return pvm.once(Meta.MetaReturnValue(one_expr(self.value, env))) end,
        [Meta.MetaBreak] = function(self) return pvm.once(self) end,
        [Meta.MetaBreakValue] = function(self, env) return pvm.once(Meta.MetaBreakValue(one_expr(self.value, env))) end,
        [Meta.MetaContinue] = function(self) return pvm.once(self) end,
        [Meta.MetaStmtLoop] = function(self, env) return pvm.once(Meta.MetaStmtLoop(one_loop(self.loop, env))) end,
        [Meta.MetaStmtUseRegionSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.seq(stmt_list(pvm.one(slot_value_region(value)), env))
        end,
        [Meta.MetaStmtUseRegionFrag] = function(self, env)
            local expanded_args = exprs(self.args, env)
            local param_bindings = map_array(self.frag.params, function(param, i)
                local arg = expanded_args[i]
                if arg == nil then error("expand_meta: missing argument " .. i .. " for region fragment use '" .. self.use_id .. "'", 2) end
                return Meta.MetaParamBinding(param, arg)
            end)
            local child_env = Meta.MetaExpandEnv(concat_fills(self.fills, env.fills), param_bindings, child_prefix(env, self.use_id))
            return pvm.seq(stmt_list(self.frag.body, child_env))
        end,
    })

    expand_func = pvm.phase("expand_meta_func", {
        [Meta.MetaFuncLocal] = function(self, env) return pvm.once(Meta.MetaFuncLocal(self.sym, params(self.params, env), one_open_set(self.open, env), one_type(self.result, env), stmt_list(self.body, env))) end,
        [Meta.MetaFuncExport] = function(self, env) return pvm.once(Meta.MetaFuncExport(self.sym, params(self.params, env), one_open_set(self.open, env), one_type(self.result, env), stmt_list(self.body, env))) end,
    })
    expand_extern_func = pvm.phase("expand_meta_extern_func", { [Meta.MetaExternFunc] = function(self, env) return pvm.once(Meta.MetaExternFunc(self.sym, params(self.params, env), one_type(self.result, env))) end })
    expand_const = pvm.phase("expand_meta_const", { [Meta.MetaConst] = function(self, env) return pvm.once(Meta.MetaConst(self.sym, one_open_set(self.open, env), one_type(self.ty, env), one_expr(self.value, env))) end })
    expand_static = pvm.phase("expand_meta_static", { [Meta.MetaStatic] = function(self, env) return pvm.once(Meta.MetaStatic(self.sym, one_open_set(self.open, env), one_type(self.ty, env), one_expr(self.value, env))) end })
    expand_import_item = pvm.phase("expand_meta_import_item", { [Meta.MetaImport] = function(self) return pvm.once(self) end })
    expand_type_decl = pvm.phase("expand_meta_type_decl", {
        [Meta.MetaStruct] = function(self, env) return pvm.once(Meta.MetaStruct(self.sym, field_types(self.fields, env))) end,
        [Meta.MetaUnion] = function(self, env) return pvm.once(Meta.MetaUnion(self.sym, field_types(self.fields, env))) end,
    })

    expand_item = pvm.phase("expand_meta_item", {
        [Meta.MetaItemFunc] = function(self, env) return pvm.once(Meta.MetaItemFunc(one_func(self.func, env))) end,
        [Meta.MetaItemExtern] = function(self, env) return pvm.once(Meta.MetaItemExtern(one_extern_func(self.func, env))) end,
        [Meta.MetaItemConst] = function(self, env) return pvm.once(Meta.MetaItemConst(one_const(self.c, env))) end,
        [Meta.MetaItemStatic] = function(self, env) return pvm.once(Meta.MetaItemStatic(one_static(self.s, env))) end,
        [Meta.MetaItemImport] = function(self, env) return pvm.once(Meta.MetaItemImport(one_import_item(self.imp, env))) end,
        [Meta.MetaItemType] = function(self, env) return pvm.once(Meta.MetaItemType(one_type_decl(self.t, env))) end,
        [Meta.MetaItemUseTypeDeclSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.once(Meta.MetaItemType(one_type_decl(pvm.one(slot_value_type_decl(value)), env)))
        end,
        [Meta.MetaItemUseItemsSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            return pvm.seq(item_list(pvm.one(slot_value_items(value)), env))
        end,
        [Meta.MetaItemUseModule] = function(self, env)
            local child_env = Meta.MetaExpandEnv(concat_fills(self.fills, env.fills), {}, child_prefix(env, self.use_id))
            return pvm.seq(item_list(self.module.items, child_env))
        end,
        [Meta.MetaItemUseModuleSlot] = function(self, env)
            local value = find_slot_value(env, self.slot)
            if value == nil then return pvm.once(self) end
            local module = one_module(pvm.one(slot_value_module(value)), env)
            local child_env = Meta.MetaExpandEnv(concat_fills(self.fills, env.fills), {}, child_prefix(env, self.use_id))
            return pvm.seq(item_list(module.items, child_env))
        end,
    })

    expand_module = pvm.phase("expand_meta_module", {
        [Meta.MetaModule] = function(self, env) return pvm.once(Meta.MetaModule(self.name, one_open_set(self.open, env), item_list(self.items, env))) end,
    })

    local api = {}
    api.phases = {
        type = expand_type,
        binding = expand_binding,
        place = expand_place,
        index_base = expand_index_base,
        domain = expand_domain,
        loop = expand_loop,
        expr = expand_expr,
        stmt = expand_stmt,
        func = expand_func,
        const = expand_const,
        static = expand_static,
        type_decl = expand_type_decl,
        item = expand_item,
        module = expand_module,
    }
    function api.fill_set(bindings) return Meta.MetaFillSet(bindings or {}) end
    function api.env(fills, params, rebase_prefix) return Meta.MetaExpandEnv(fills or Meta.MetaFillSet({}), params or {}, rebase_prefix or "") end
    function api.type(node, env) return one_type(node, env or api.env()) end
    function api.expr(node, env) return one_expr(node, env or api.env()) end
    function api.stmts(stmts, env) return stmt_list(stmts, env or api.env()) end
    function api.stmt(node, env) return pvm.drain(expand_stmt(node, env or api.env())) end
    function api.func(node, env) return one_func(node, env or api.env()) end
    function api.const(node, env) return one_const(node, env or api.env()) end
    function api.static(node, env) return one_static(node, env or api.env()) end
    function api.type_decl(node, env) return one_type_decl(node, env or api.env()) end
    function api.items(items, env) return item_list(items, env or api.env()) end
    function api.module(node, env) return one_module(node, env or api.env()) end
    return api
end

return M
