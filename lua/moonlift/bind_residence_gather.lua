local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local B = T.MoonBind
    local Tr = T.MoonTree

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)

    local binding_facts
    local value_ref_facts
    local place_facts
    local place_address_facts
    local expr_facts
    local stmt_facts
    local view_facts
    local domain_facts
    local index_base_facts
    local control_stmt_region_facts
    local control_expr_region_facts
    local func_facts
    local extern_facts
    local const_facts
    local static_facts
    local item_facts
    local module_facts

    local function pack(g, p, c) return { g, p, c } end
    local function cat(trips) return pvm.concat_all(trips) end
    local function each(phase, xs) return pvm.children(phase, xs) end

    binding_facts = pvm.phase("moonlift_bind_residence_binding_facts", {
        [B.Binding] = function(binding)
            local facts = { B.ResidenceFactBinding(binding) }
            local scalar_result = scalar_api.result(binding.ty)
            if pvm.classof(scalar_result) == Ty.TypeBackScalarUnavailable then
                facts[#facts + 1] = B.ResidenceFactNonScalarAbi(binding)
            end
            return pvm.children(function(fact) return pvm.once(fact) end, facts)
        end,
    })

    value_ref_facts = pvm.phase("moonlift_bind_residence_value_ref_facts", {
        [B.ValueRefBinding] = function(self) return binding_facts(self.binding) end,
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
        [B.ValueRefSlot] = function() return pvm.empty() end,
        [B.ValueRefFuncSlot] = function() return pvm.empty() end,
        [B.ValueRefConstSlot] = function() return pvm.empty() end,
        [B.ValueRefStaticSlot] = function() return pvm.empty() end,
    })

    place_address_facts = pvm.phase("moonlift_bind_residence_place_address_facts", {
        [Tr.PlaceRef] = function(self)
            if pvm.classof(self.ref) == B.ValueRefBinding then
                return cat({ pack(value_ref_facts(self.ref)), pack(pvm.once(B.ResidenceFactAddressTaken(self.ref.binding))) })
            end
            return value_ref_facts(self.ref)
        end,
        [Tr.PlaceDeref] = function(self) return expr_facts(self.base) end,
        [Tr.PlaceDot] = function(self) return place_address_facts(self.base) end,
        [Tr.PlaceField] = function(self) return place_address_facts(self.base) end,
        [Tr.PlaceIndex] = function(self) return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) }) end,
        [Tr.PlaceSlotValue] = function() return pvm.empty() end,
    })

    place_facts = pvm.phase("moonlift_bind_residence_place_facts", {
        [Tr.PlaceRef] = function(self) return value_ref_facts(self.ref) end,
        [Tr.PlaceDeref] = function(self) return expr_facts(self.base) end,
        [Tr.PlaceDot] = function(self) return place_facts(self.base) end,
        [Tr.PlaceField] = function(self) return place_facts(self.base) end,
        [Tr.PlaceIndex] = function(self) return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) }) end,
        [Tr.PlaceSlotValue] = function() return pvm.empty() end,
    })

    view_facts = pvm.phase("moonlift_bind_residence_view_facts", {
        [Tr.ViewFromExpr] = function(self) return expr_facts(self.base) end,
        [Tr.ViewContiguous] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)) }) end,
        [Tr.ViewStrided] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)) }) end,
        [Tr.ViewRestrided] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)) }) end,
        [Tr.ViewWindow] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.start)), pack(expr_facts(self.len)) }) end,
        [Tr.ViewRowBase] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.row_offset)) }) end,
        [Tr.ViewInterleaved] = function(self) return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) }) end,
        [Tr.ViewInterleavedView] = function(self) return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) }) end,
    })

    domain_facts = pvm.phase("moonlift_bind_residence_domain_facts", {
        [Tr.DomainRange] = function(self) return expr_facts(self.stop) end,
        [Tr.DomainRange2] = function(self) return cat({ pack(expr_facts(self.start)), pack(expr_facts(self.stop)) }) end,
        [Tr.DomainZipEqValues] = function(self) return each(expr_facts, self.values) end,
        [Tr.DomainValue] = function(self) return expr_facts(self.value) end,
        [Tr.DomainView] = function(self) return view_facts(self.view) end,
        [Tr.DomainZipEqViews] = function(self) return each(view_facts, self.views) end,
        [Tr.DomainSlotValue] = function() return pvm.empty() end,
    })

    index_base_facts = pvm.phase("moonlift_bind_residence_index_base_facts", {
        [Tr.IndexBaseExpr] = function(self) return expr_facts(self.base) end,
        [Tr.IndexBasePlace] = function(self) return place_facts(self.base) end,
        [Tr.IndexBaseView] = function(self) return view_facts(self.view) end,
    })

    local function entry_block_facts(block)
        local trips = { pack(each(stmt_facts, block.body)) }
        for i = 1, #block.params do trips[#trips + 1] = pack(expr_facts(block.params[i].init)) end
        return cat(trips)
    end

    local function control_block_facts(block)
        return each(stmt_facts, block.body)
    end

    control_stmt_region_facts = pvm.phase("moonlift_bind_residence_control_stmt_region_facts", {
        [Tr.ControlStmtRegion] = function(self)
            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
        end,
    })

    control_expr_region_facts = pvm.phase("moonlift_bind_residence_control_expr_region_facts", {
        [Tr.ControlExprRegion] = function(self)
            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
        end,
    })

    expr_facts = pvm.phase("moonlift_bind_residence_expr_facts", {
        [Tr.ExprLit] = function() return pvm.empty() end,
        [Tr.ExprRef] = function(self) return value_ref_facts(self.ref) end,
        [Tr.ExprDot] = function(self) return expr_facts(self.base) end,
        [Tr.ExprUnary] = function(self) return expr_facts(self.value) end,
        [Tr.ExprBinary] = function(self) return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprCompare] = function(self) return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprLogic] = function(self) return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) }) end,
        [Tr.ExprCast] = function(self) return expr_facts(self.value) end,
        [Tr.ExprMachineCast] = function(self) return expr_facts(self.value) end,
        [Tr.ExprIntrinsic] = function(self) return each(expr_facts, self.args) end,
        [Tr.ExprAddrOf] = function(self) return place_address_facts(self.place) end,
        [Tr.ExprDeref] = function(self) return expr_facts(self.value) end,
        [Tr.ExprCall] = function(self) return each(expr_facts, self.args) end,
        [Tr.ExprLen] = function(self) return expr_facts(self.value) end,
        [Tr.ExprField] = function(self) return expr_facts(self.base) end,
        [Tr.ExprIndex] = function(self) return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) }) end,
        [Tr.ExprAgg] = function(self)
            local trips = {}
            for i = 1, #self.fields do trips[#trips + 1] = pack(expr_facts(self.fields[i].value)) end
            return cat(trips)
        end,
        [Tr.ExprArray] = function(self) return each(expr_facts, self.elems) end,
        [Tr.ExprIf] = function(self) return cat({ pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) }) end,
        [Tr.ExprSelect] = function(self) return cat({ pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) }) end,
        [Tr.ExprSwitch] = function(self)
            local trips = { pack(expr_facts(self.value)) }
            for i = 1, #self.arms do
                trips[#trips + 1] = pack(each(stmt_facts, self.arms[i].body))
                trips[#trips + 1] = pack(expr_facts(self.arms[i].result))
            end
            trips[#trips + 1] = pack(expr_facts(self.default_expr))
            return cat(trips)
        end,
        [Tr.ExprControl] = function(self) return control_expr_region_facts(self.region) end,
        [Tr.ExprBlock] = function(self) return cat({ pack(each(stmt_facts, self.stmts)), pack(expr_facts(self.result)) }) end,
        [Tr.ExprClosure] = function(self) return each(stmt_facts, self.body) end,
        [Tr.ExprView] = function(self) return view_facts(self.view) end,
        [Tr.ExprLoad] = function(self) return expr_facts(self.addr) end,
        [Tr.ExprSlotValue] = function() return pvm.empty() end,
        [Tr.ExprUseExprFrag] = function(self) return each(expr_facts, self.args) end,
    })

    stmt_facts = pvm.phase("moonlift_bind_residence_stmt_facts", {
        [Tr.StmtLet] = function(self) return cat({ pack(binding_facts(self.binding)), pack(expr_facts(self.init)) }) end,
        [Tr.StmtVar] = function(self) return cat({ pack(binding_facts(self.binding)), pack(pvm.once(B.ResidenceFactMutableCell(self.binding))), pack(expr_facts(self.init)) }) end,
        [Tr.StmtSet] = function(self) return cat({ pack(place_facts(self.place)), pack(expr_facts(self.value)) }) end,
        [Tr.StmtExpr] = function(self) return expr_facts(self.expr) end,
        [Tr.StmtAssert] = function(self) return expr_facts(self.cond) end,
        [Tr.StmtIf] = function(self) return cat({ pack(expr_facts(self.cond)), pack(each(stmt_facts, self.then_body)), pack(each(stmt_facts, self.else_body)) }) end,
        [Tr.StmtSwitch] = function(self)
            local trips = { pack(expr_facts(self.value)) }
            for i = 1, #self.arms do trips[#trips + 1] = pack(each(stmt_facts, self.arms[i].body)) end
            trips[#trips + 1] = pack(each(stmt_facts, self.default_body))
            return cat(trips)
        end,
        [Tr.StmtJump] = function(self)
            local trips = {}
            for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end
            return cat(trips)
        end,
        [Tr.StmtJumpCont] = function(self)
            local trips = {}
            for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end
            return cat(trips)
        end,
        [Tr.StmtYieldVoid] = function() return pvm.empty() end,
        [Tr.StmtYieldValue] = function(self) return expr_facts(self.value) end,
        [Tr.StmtReturnVoid] = function() return pvm.empty() end,
        [Tr.StmtReturnValue] = function(self) return expr_facts(self.value) end,
        [Tr.StmtControl] = function(self) return control_stmt_region_facts(self.region) end,
        [Tr.StmtUseRegionSlot] = function() return pvm.empty() end,
        [Tr.StmtUseRegionFrag] = function(self) return each(expr_facts, self.args) end,
    })

    func_facts = pvm.phase("moonlift_bind_residence_func_facts", {
        [Tr.FuncLocal] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncExport] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncLocalContract] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncExportContract] = function(self) return each(stmt_facts, self.body) end,
        [Tr.FuncOpen] = function(self) return each(stmt_facts, self.body) end,
    })

    extern_facts = pvm.phase("moonlift_bind_residence_extern_facts", {
        [Tr.ExternFunc] = function() return pvm.empty() end,
        [Tr.ExternFuncOpen] = function() return pvm.empty() end,
    })

    const_facts = pvm.phase("moonlift_bind_residence_const_facts", {
        [Tr.ConstItem] = function(self) return expr_facts(self.value) end,
        [Tr.ConstItemOpen] = function(self) return expr_facts(self.value) end,
    })

    static_facts = pvm.phase("moonlift_bind_residence_static_facts", {
        [Tr.StaticItem] = function(self) return expr_facts(self.value) end,
        [Tr.StaticItemOpen] = function(self) return expr_facts(self.value) end,
    })

    item_facts = pvm.phase("moonlift_bind_residence_item_facts", {
        [Tr.ItemFunc] = function(self) return func_facts(self.func) end,
        [Tr.ItemExtern] = function(self) return extern_facts(self.func) end,
        [Tr.ItemConst] = function(self) return const_facts(self.c) end,
        [Tr.ItemStatic] = function(self) return static_facts(self.s) end,
        [Tr.ItemImport] = function() return pvm.empty() end,
        [Tr.ItemType] = function() return pvm.empty() end,
        [Tr.ItemUseTypeDeclSlot] = function() return pvm.empty() end,
        [Tr.ItemUseItemsSlot] = function() return pvm.empty() end,
        [Tr.ItemUseModule] = function(self) return module_facts(self.module) end,
        [Tr.ItemUseModuleSlot] = function() return pvm.empty() end,
    })

    module_facts = pvm.phase("moonlift_bind_residence_module_facts", {
        [Tr.Module] = function(module) return each(item_facts, module.items) end,
    })

    local function fact_set(g, p, c)
        return B.ResidenceFactSet(pvm.drain(g, p, c))
    end

    return {
        binding_facts = binding_facts,
        expr_facts = expr_facts,
        stmt_facts = stmt_facts,
        item_facts = item_facts,
        module_facts = module_facts,
        fact_set = fact_set,
        facts_of_module = function(module) return fact_set(module_facts(module)) end,
        facts_of_stmts = function(stmts) return fact_set(each(stmt_facts, stmts)) end,
    }
end

return M
