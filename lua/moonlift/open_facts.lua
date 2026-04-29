local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local O = T.MoonOpen
    local B = T.MoonBind
    local Tr = T.MoonTree

    local slot_fact
    local value_import_fact
    local open_set_facts
    local expr_header_facts
    local place_header_facts
    local stmt_header_facts
    local module_header_facts
    local binding_class_facts
    local binding_facts
    local value_ref_facts
    local slot_value_facts
    local slot_binding_facts
    local fill_set_facts
    local expr_facts
    local place_facts
    local stmt_facts
    local view_facts
    local domain_facts
    local index_base_facts
    local control_stmt_region_facts
    local control_expr_region_facts
    local field_init_facts
    local switch_stmt_arm_facts
    local switch_expr_arm_facts
    local func_facts
    local extern_facts
    local const_facts
    local static_facts
    local type_decl_facts
    local item_facts
    local module_facts

    local function pack(g, p, c) return { g, p, c } end
    local function cat(trips) return pvm.concat_all(trips) end
    local function each(phase, xs) return pvm.children(phase, xs) end
    local function slot(slot_node) return pvm.once(O.MetaFactSlot(slot_node)) end

    slot_fact = pvm.phase("moon2_open_slot_fact", {
        [O.SlotType] = function(self) return slot(self) end,
        [O.SlotValue] = function(self) return slot(self) end,
        [O.SlotExpr] = function(self) return slot(self) end,
        [O.SlotPlace] = function(self) return slot(self) end,
        [O.SlotDomain] = function(self) return slot(self) end,
        [O.SlotRegion] = function(self) return slot(self) end,
        [O.SlotCont] = function(self) return slot(self) end,
        [O.SlotFunc] = function(self) return slot(self) end,
        [O.SlotConst] = function(self) return slot(self) end,
        [O.SlotStatic] = function(self) return slot(self) end,
        [O.SlotTypeDecl] = function(self) return slot(self) end,
        [O.SlotItems] = function(self) return slot(self) end,
        [O.SlotModule] = function(self) return slot(self) end,
    })

    value_import_fact = pvm.phase("moon2_open_value_import_fact", {
        [O.ImportValue] = function(self) return pvm.once(O.MetaFactValueImportUse(self)) end,
        [O.ImportGlobalFunc] = function(self) return pvm.once(O.MetaFactGlobalFunc(self.module_name, self.item_name)) end,
        [O.ImportGlobalConst] = function(self) return pvm.once(O.MetaFactGlobalConst(self.module_name, self.item_name)) end,
        [O.ImportGlobalStatic] = function(self) return pvm.once(O.MetaFactGlobalStatic(self.module_name, self.item_name)) end,
        [O.ImportExtern] = function(self) return pvm.once(O.MetaFactExtern(self.symbol)) end,
    })

    open_set_facts = pvm.phase("moon2_open_set_facts", {
        [O.OpenSet] = function(open)
            return cat({
                pack(each(value_import_fact, open.value_imports)),
                pack(each(slot_fact, open.slots)),
            })
        end,
    })

    expr_header_facts = pvm.phase("moon2_open_expr_header_facts", {
        [Tr.ExprSurface] = function() return pvm.empty() end,
        [Tr.ExprTyped] = function() return pvm.empty() end,
        [Tr.ExprOpen] = function(self) return open_set_facts(self.open) end,
        [Tr.ExprSem] = function() return pvm.empty() end,
        [Tr.ExprCode] = function() return pvm.empty() end,
    })

    place_header_facts = pvm.phase("moon2_open_place_header_facts", {
        [Tr.PlaceSurface] = function() return pvm.empty() end,
        [Tr.PlaceTyped] = function() return pvm.empty() end,
        [Tr.PlaceOpen] = function(self) return open_set_facts(self.open) end,
        [Tr.PlaceSem] = function() return pvm.empty() end,
    })

    stmt_header_facts = pvm.phase("moon2_open_stmt_header_facts", {
        [Tr.StmtSurface] = function() return pvm.empty() end,
        [Tr.StmtTyped] = function() return pvm.empty() end,
        [Tr.StmtOpen] = function(self) return open_set_facts(self.open) end,
        [Tr.StmtSem] = function() return pvm.empty() end,
        [Tr.StmtCode] = function() return pvm.empty() end,
    })

    module_header_facts = pvm.phase("moon2_open_module_header_facts", {
        [Tr.ModuleSurface] = function() return pvm.empty() end,
        [Tr.ModuleTyped] = function() return pvm.empty() end,
        [Tr.ModuleOpen] = function(self)
            local name_trip
            if self.name == O.ModuleNameOpen then
                name_trip = pack(pvm.once(O.MetaFactOpenModuleName))
            else
                name_trip = pack(pvm.empty())
            end
            return cat({ name_trip, pack(open_set_facts(self.open)) })
        end,
        [Tr.ModuleSem] = function() return pvm.empty() end,
        [Tr.ModuleCode] = function() return pvm.empty() end,
    })

    binding_class_facts = pvm.phase("moon2_open_binding_class_facts", {
        [B.BindingClassLocalValue] = function(_, binding) return pvm.once(O.MetaFactLocalValue(binding.id.text, binding.name)) end,
        [B.BindingClassLocalCell] = function(_, binding) return pvm.once(O.MetaFactLocalCell(binding.id.text, binding.name)) end,
        [B.BindingClassArg] = function() return pvm.empty() end,
        [B.BindingClassEntryBlockParam] = function(self, binding) return pvm.once(O.MetaFactEntryBlockParam(self.region_id, self.block_name, self.index, binding.name)) end,
        [B.BindingClassBlockParam] = function(self, binding) return pvm.once(O.MetaFactBlockParam(self.region_id, self.block_name, self.index, binding.name)) end,
        [B.BindingClassGlobalFunc] = function(self) return pvm.once(O.MetaFactGlobalFunc(self.module_name, self.item_name)) end,
        [B.BindingClassGlobalConst] = function(self) return pvm.once(O.MetaFactGlobalConst(self.module_name, self.item_name)) end,
        [B.BindingClassGlobalStatic] = function(self) return pvm.once(O.MetaFactGlobalStatic(self.module_name, self.item_name)) end,
        [B.BindingClassExtern] = function(self) return pvm.once(O.MetaFactExtern(self.symbol)) end,
        [B.BindingClassOpenParam] = function(self) return pvm.once(O.MetaFactParamUse(self.param)) end,
        [B.BindingClassImport] = function(self) return value_import_fact(self.import) end,
        [B.BindingClassFuncSym] = function() return pvm.empty() end,
        [B.BindingClassExternSym] = function() return pvm.empty() end,
        [B.BindingClassConstSym] = function() return pvm.empty() end,
        [B.BindingClassStaticSym] = function() return pvm.empty() end,
        [B.BindingClassFuncSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotFunc(self.slot))) end,
        [B.BindingClassConstSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotConst(self.slot))) end,
        [B.BindingClassStaticSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotStatic(self.slot))) end,
        [B.BindingClassValueSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotValue(self.slot))) end,
    })

    binding_facts = pvm.phase("moon2_open_binding_facts", {
        [B.Binding] = function(binding)
            return binding_class_facts(binding.class, binding)
        end,
    })

    value_ref_facts = pvm.phase("moon2_open_value_ref_facts", {
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
        [B.ValueRefBinding] = function(self) return binding_facts(self.binding) end,
        [B.ValueRefSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotValue(self.slot))) end,
        [B.ValueRefFuncSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotFunc(self.slot))) end,
        [B.ValueRefConstSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotConst(self.slot))) end,
        [B.ValueRefStaticSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotStatic(self.slot))) end,
    })

    slot_value_facts = pvm.phase("moon2_open_slot_value_facts", {
        [O.SlotValueType] = function() return pvm.empty() end,
        [O.SlotValueExpr] = function(self) return expr_facts(self.expr) end,
        [O.SlotValuePlace] = function(self) return place_facts(self.place) end,
        [O.SlotValueDomain] = function(self) return domain_facts(self.domain) end,
        [O.SlotValueRegion] = function(self) return each(stmt_facts, self.body) end,
        [O.SlotValueCont] = function() return pvm.empty() end,
        [O.SlotValueContSlot] = function() return pvm.empty() end,
        [O.SlotValueFunc] = function(self) return func_facts(self.func) end,
        [O.SlotValueConst] = function(self) return const_facts(self.c) end,
        [O.SlotValueStatic] = function(self) return static_facts(self.s) end,
        [O.SlotValueTypeDecl] = function(self) return type_decl_facts(self.t) end,
        [O.SlotValueItems] = function(self) return each(item_facts, self.items) end,
        [O.SlotValueModule] = function(self) return module_facts(self.module) end,
    })

    slot_binding_facts = pvm.phase("moon2_open_slot_binding_facts", {
        [O.SlotBinding] = function(binding)
            return slot_value_facts(binding.value)
        end,
    })

    fill_set_facts = pvm.phase("moon2_open_fill_set_facts", {
        [O.FillSet] = function(fills)
            return each(slot_binding_facts, fills.bindings)
        end,
    })

    field_init_facts = pvm.phase("moon2_open_field_init_facts", {
        [Tr.FieldInit] = function(init)
            return expr_facts(init.value)
        end,
    })

    switch_stmt_arm_facts = pvm.phase("moon2_open_switch_stmt_arm_facts", {
        [Tr.SwitchStmtArm] = function(arm)
            return each(stmt_facts, arm.body)
        end,
    })

    switch_expr_arm_facts = pvm.phase("moon2_open_switch_expr_arm_facts", {
        [Tr.SwitchExprArm] = function(arm)
            return cat({ pack(each(stmt_facts, arm.body)), pack(expr_facts(arm.result)) })
        end,
    })

    view_facts = pvm.phase("moon2_open_view_facts", {
        [Tr.ViewFromExpr] = function(self) return expr_facts(self.base) end,
        [Tr.ViewContiguous] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)) }) end,
        [Tr.ViewStrided] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)) }) end,
        [Tr.ViewRestrided] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)) }) end,
        [Tr.ViewWindow] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.start)), pack(expr_facts(self.len)) }) end,
        [Tr.ViewRowBase] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.row_offset)) }) end,
        [Tr.ViewInterleaved] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) }) end,
        [Tr.ViewInterleavedView] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) }) end,
    })

    domain_facts = pvm.phase("moon2_open_domain_facts", {
        [Tr.DomainRange] = function(self) return expr_facts(self.stop) end,
        [Tr.DomainRange2] = function(self) return cat({ pack(expr_facts(self.start)), pack(expr_facts(self.stop)) }) end,
        [Tr.DomainZipEqValues] = function(self) return each(expr_facts, self.values) end,
        [Tr.DomainValue] = function(self) return expr_facts(self.value) end,
        [Tr.DomainView] = function(self) return view_facts(self.view) end,
        [Tr.DomainZipEqViews] = function(self) return each(view_facts, self.views) end,
        [Tr.DomainSlotValue] = function(self) return pvm.once(O.MetaFactSlot(O.SlotDomain(self.slot))) end,
    })

    index_base_facts = pvm.phase("moon2_open_index_base_facts", {
        [Tr.IndexBaseExpr] = function(self) return expr_facts(self.base) end,
        [Tr.IndexBasePlace] = function(self) return place_facts(self.base) end,
        [Tr.IndexBaseView] = function(self) return view_facts(self.view) end,
    })

    place_facts = pvm.phase("moon2_open_place_facts", {
        [Tr.PlaceRef] = function(self) return cat({ pack(place_header_facts(self.h)), pack(value_ref_facts(self.ref)) }) end,
        [Tr.PlaceDeref] = function(self) return cat({ pack(place_header_facts(self.h)), pack(expr_facts(self.base)) }) end,
        [Tr.PlaceDot] = function(self) return cat({ pack(place_header_facts(self.h)), pack(place_facts(self.base)) }) end,
        [Tr.PlaceField] = function(self) return cat({ pack(place_header_facts(self.h)), pack(place_facts(self.base)) }) end,
        [Tr.PlaceIndex] = function(self) return cat({ pack(place_header_facts(self.h)), pack(index_base_facts(self.base)), pack(expr_facts(self.index)) }) end,
        [Tr.PlaceSlotValue] = function(self) return cat({ pack(place_header_facts(self.h)), pack(pvm.once(O.MetaFactSlot(O.SlotPlace(self.slot)))) }) end,
    })

    local function entry_block_facts(block)
        local trips = { pack(each(stmt_facts, block.body)) }
        for i = 1, #block.params do trips[#trips + 1] = pack(expr_facts(block.params[i].init)) end
        return cat(trips)
    end

    local function control_block_facts(block)
        return each(stmt_facts, block.body)
    end

    control_stmt_region_facts = pvm.phase("moon2_open_control_stmt_region_facts", {
        [Tr.ControlStmtRegion] = function(self)
            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
        end,
    })

    control_expr_region_facts = pvm.phase("moon2_open_control_expr_region_facts", {
        [Tr.ControlExprRegion] = function(self)
            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
        end,
    })

    expr_facts = pvm.phase("moon2_open_expr_facts", {
        [Tr.ExprLit] = function(self) return expr_header_facts(self.h) end,
        [Tr.ExprRef] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(value_ref_facts(self.ref)) }) end,
        [Tr.ExprDot] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.base)) }) end,
        [Tr.ExprUnary] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.ExprBinary] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprCompare] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprLogic] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprCast] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.ExprMachineCast] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.ExprIntrinsic] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.args)) }) end,
        [Tr.ExprAddrOf] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(place_facts(self.place)) }) end,
        [Tr.ExprDeref] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.ExprCall] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.args)) }) end,
        [Tr.ExprLen] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.ExprField] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.base)) }) end,
        [Tr.ExprIndex] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(index_base_facts(self.base)), pack(expr_facts(self.index)) }) end,
        [Tr.ExprAgg] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(field_init_facts, self.fields)) }) end,
        [Tr.ExprArray] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.elems)) }) end,
        [Tr.ExprIf] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) }) end,
        [Tr.ExprSelect] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) }) end,
        [Tr.ExprSwitch] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)), pack(each(switch_expr_arm_facts, self.arms)), pack(expr_facts(self.default_expr)) }) end,
        [Tr.ExprControl] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(control_expr_region_facts(self.region)) }) end,
        [Tr.ExprBlock] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(stmt_facts, self.stmts)), pack(expr_facts(self.result)) }) end,
        [Tr.ExprClosure] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(each(stmt_facts, self.body)) }) end,
        [Tr.ExprView] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(view_facts(self.view)) }) end,
        [Tr.ExprLoad] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.addr)) }) end,
        [Tr.ExprSlotValue] = function(self) return cat({ pack(expr_header_facts(self.h)), pack(pvm.once(O.MetaFactSlot(O.SlotExpr(self.slot)))) }) end,
        [Tr.ExprUseExprFrag] = function(self)
            return cat({ pack(expr_header_facts(self.h)), pack(pvm.once(O.MetaFactExprFragUse(self.use_id))), pack(open_set_facts(self.frag.open)), pack(expr_facts(self.frag.body)), pack(each(expr_facts, self.args)), pack(each(slot_binding_facts, self.fills)) })
        end,
    })

    stmt_facts = pvm.phase("moon2_open_stmt_facts", {
        [Tr.StmtLet] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(binding_facts(self.binding)), pack(expr_facts(self.init)) }) end,
        [Tr.StmtVar] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(binding_facts(self.binding)), pack(expr_facts(self.init)) }) end,
        [Tr.StmtSet] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(place_facts(self.place)), pack(expr_facts(self.value)) }) end,
        [Tr.StmtExpr] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.expr)) }) end,
        [Tr.StmtAssert] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.cond)) }) end,
        [Tr.StmtIf] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.cond)), pack(each(stmt_facts, self.then_body)), pack(each(stmt_facts, self.else_body)) }) end,
        [Tr.StmtSwitch] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)), pack(each(switch_stmt_arm_facts, self.arms)), pack(each(stmt_facts, self.default_body)) }) end,
        [Tr.StmtJump] = function(self) local trips = { pack(stmt_header_facts(self.h)) }; for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end; return cat(trips) end,
        [Tr.StmtJumpCont] = function(self) local trips = { pack(stmt_header_facts(self.h)), pack(pvm.once(O.MetaFactSlot(O.SlotCont(self.slot)))) }; for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end; return cat(trips) end,
        [Tr.StmtYieldVoid] = function(self) return stmt_header_facts(self.h) end,
        [Tr.StmtYieldValue] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.StmtReturnVoid] = function(self) return stmt_header_facts(self.h) end,
        [Tr.StmtReturnValue] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)) }) end,
        [Tr.StmtControl] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(control_stmt_region_facts(self.region)) }) end,
        [Tr.StmtUseRegionSlot] = function(self) return cat({ pack(stmt_header_facts(self.h)), pack(pvm.once(O.MetaFactSlot(O.SlotRegion(self.slot)))) }) end,
        [Tr.StmtUseRegionFrag] = function(self)
            return cat({ pack(stmt_header_facts(self.h)), pack(pvm.once(O.MetaFactRegionFragUse(self.use_id))), pack(open_set_facts(self.frag.open)), pack(entry_block_facts(self.frag.entry)), pack(each(control_block_facts, self.frag.blocks)), pack(each(expr_facts, self.args)), pack(each(slot_binding_facts, self.fills)) })
        end,
    })

    func_facts = pvm.phase("moon2_open_func_facts", {
        [Tr.FuncLocal] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncExport] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncLocalContract] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncExportContract] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncOpen] = function(self) return cat({ pack(open_set_facts(self.open)), pack(each(stmt_facts, self.body)) }) end,
    })

    extern_facts = pvm.phase("moon2_open_extern_facts", {
        [Tr.ExternFunc] = function() return pvm.empty() end,
        [Tr.ExternFuncOpen] = function() return pvm.empty() end,
    })

    const_facts = pvm.phase("moon2_open_const_facts", {
        [Tr.ConstItem] = function(self) return expr_facts(self.value) end,
        [Tr.ConstItemOpen] = function(self) return cat({ pack(open_set_facts(self.open)), pack(expr_facts(self.value)) }) end,
    })

    static_facts = pvm.phase("moon2_open_static_facts", {
        [Tr.StaticItem] = function(self) return expr_facts(self.value) end,
        [Tr.StaticItemOpen] = function(self) return cat({ pack(open_set_facts(self.open)), pack(expr_facts(self.value)) }) end,
    })

    type_decl_facts = pvm.phase("moon2_open_type_decl_facts", {
        [Tr.TypeDeclStruct] = function() return pvm.empty() end,
        [Tr.TypeDeclUnion] = function() return pvm.empty() end,
        [Tr.TypeDeclEnumSugar] = function() return pvm.empty() end,
        [Tr.TypeDeclTaggedUnionSugar] = function() return pvm.empty() end,
        [Tr.TypeDeclOpenStruct] = function(self) return pvm.once(O.MetaFactLocalType(self.sym)) end,
        [Tr.TypeDeclOpenUnion] = function(self) return pvm.once(O.MetaFactLocalType(self.sym)) end,
    })

    item_facts = pvm.phase("moon2_open_item_facts", {
        [Tr.ItemFunc] = function(self) return func_facts(self.func) end,
        [Tr.ItemExtern] = function(self) return extern_facts(self.func) end,
        [Tr.ItemConst] = function(self) return const_facts(self.c) end,
        [Tr.ItemStatic] = function(self) return static_facts(self.s) end,
        [Tr.ItemImport] = function() return pvm.empty() end,
        [Tr.ItemType] = function(self) return type_decl_facts(self.t) end,
        [Tr.ItemUseTypeDeclSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotTypeDecl(self.slot))) end,
        [Tr.ItemUseItemsSlot] = function(self) return pvm.once(O.MetaFactSlot(O.SlotItems(self.slot))) end,
        [Tr.ItemUseModule] = function(self) return cat({ pack(pvm.once(O.MetaFactModuleUse(self.use_id))), pack(module_facts(self.module)), pack(each(slot_binding_facts, self.fills)) }) end,
        [Tr.ItemUseModuleSlot] = function(self) return cat({ pack(pvm.once(O.MetaFactModuleSlotUse(self.use_id, self.slot))), pack(pvm.once(O.MetaFactSlot(O.SlotModule(self.slot)))), pack(each(slot_binding_facts, self.fills)) }) end,
    })

    module_facts = pvm.phase("moon2_open_module_facts", {
        [Tr.Module] = function(module)
            return cat({ pack(module_header_facts(module.h)), pack(each(item_facts, module.items)) })
        end,
    })

    local function fact_set(g, p, c)
        return O.MetaFactSet(pvm.drain(g, p, c))
    end

    return {
        slot_fact = slot_fact,
        value_import_fact = value_import_fact,
        open_set_facts = open_set_facts,
        expr_header_facts = expr_header_facts,
        place_header_facts = place_header_facts,
        stmt_header_facts = stmt_header_facts,
        module_header_facts = module_header_facts,
        binding_class_facts = binding_class_facts,
        binding_facts = binding_facts,
        value_ref_facts = value_ref_facts,
        slot_value_facts = slot_value_facts,
        slot_binding_facts = slot_binding_facts,
        fill_set_facts = fill_set_facts,
        expr_facts = expr_facts,
        place_facts = place_facts,
        stmt_facts = stmt_facts,
        view_facts = view_facts,
        domain_facts = domain_facts,
        item_facts = item_facts,
        module_facts = module_facts,
        fact_set = fact_set,
        facts_of_module = function(module) return fact_set(module_facts(module)) end,
        facts_of_open_set = function(open) return fact_set(open_set_facts(open)) end,
    }
end

return M
