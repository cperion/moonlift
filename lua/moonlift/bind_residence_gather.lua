local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

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

    function binding_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.Binding) then
            return (function(binding)

            local facts = { B.ResidenceFactBinding(binding) }
            local scalar_result = scalar_api.result(binding.ty)
            if schema.classof(scalar_result) == Ty.TypeBackScalarUnavailable then
                facts[#facts + 1] = B.ResidenceFactNonScalarAbi(binding)
            end
            return erased.children(function(fact) return erased.once(fact) end, facts)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_binding_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self)
 return binding_facts(self.binding)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_value_ref_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function place_address_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)

            if schema.classof(self.ref) == B.ValueRefBinding then
                return cat({ pack(value_ref_facts(self.ref)), pack(erased.once(B.ResidenceFactAddressTaken(self.ref.binding))) })
            end
            return value_ref_facts(self.ref)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self)
 return place_address_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self)
 return place_address_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self)
 return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_place_address_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function place_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)
 return value_ref_facts(self.ref)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self)
 return place_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self)
 return place_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self)
 return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_place_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function view_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ViewFromExpr) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewContiguous) then
            return (function(self)
 return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewStrided) then
            return (function(self)
 return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRestrided) then
            return (function(self)
 return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewWindow) then
            return (function(self)
 return cat({ pack(view_facts(self.base)), pack(expr_facts(self.start)), pack(expr_facts(self.len)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRowBase) then
            return (function(self)
 return cat({ pack(view_facts(self.base)), pack(expr_facts(self.row_offset)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleaved) then
            return (function(self)
 return cat({ pack(expr_facts(self.data)), pack(expr_facts(self.len)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleavedView) then
            return (function(self)
 return cat({ pack(view_facts(self.base)), pack(expr_facts(self.stride)), pack(expr_facts(self.lane)) })
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_view_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function domain_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.DomainRange) then
            return (function(self)
 return expr_facts(self.stop)
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainRange2) then
            return (function(self)
 return cat({ pack(expr_facts(self.start)), pack(expr_facts(self.stop)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqValues) then
            return (function(self)
 return each(expr_facts, self.values)
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainValue) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainView) then
            return (function(self)
 return view_facts(self.view)
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqViews) then
            return (function(self)
 return each(view_facts, self.views)
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainSlotValue) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_domain_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function index_base_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self)
 return place_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self)
 return view_facts(self.view)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_index_base_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function entry_block_facts(block)
        local trips = { pack(each(stmt_facts, block.body)) }
        for i = 1, #block.params do trips[#trips + 1] = pack(expr_facts(block.params[i].init)) end
        return cat(trips)
    end

    local function control_block_facts(block)
        return each(stmt_facts, block.body)
    end

    function control_stmt_region_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(self)

            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_control_stmt_region_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function control_expr_region_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlExprRegion) then
            return (function(self)

            local trips = { pack(entry_block_facts(self.entry)) }
            for i = 1, #self.blocks do trips[#trips + 1] = pack(control_block_facts(self.blocks[i])) end
            return cat(trips)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_control_expr_region_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self)
 return value_ref_facts(self.ref)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self)
 return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self)
 return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self)
 return cat({ pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self)
 return each(expr_facts, self.args)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self)
 return place_address_facts(self.place)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self)
 return each(expr_facts, self.args)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self)
 return expr_facts(self.base)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self)
 return cat({ pack(index_base_facts(self.base)), pack(expr_facts(self.index)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self)

            local trips = {}
            for i = 1, #self.fields do trips[#trips + 1] = pack(expr_facts(self.fields[i].value)) end
            return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCtor) then
            return (function(self)
 return each(expr_facts, self.args or {})
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self)
 return each(expr_facts, self.elems)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self)
 return cat({ pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self)
 return cat({ pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self)

            local trips = { pack(expr_facts(self.value)) }
            for i = 1, #self.arms do
                trips[#trips + 1] = pack(each(stmt_facts, self.arms[i].body))
                trips[#trips + 1] = pack(expr_facts(self.arms[i].result))
            end
            for i = 1, #(self.variant_arms or {}) do
                trips[#trips + 1] = pack(each(stmt_facts, self.variant_arms[i].body))
                trips[#trips + 1] = pack(expr_facts(self.variant_arms[i].result))
            end
            trips[#trips + 1] = pack(each(stmt_facts, self.default_body or {}))
            trips[#trips + 1] = pack(expr_facts(self.default_expr))
            return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self)
 return control_expr_region_facts(self.region)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self)
 return cat({ pack(each(stmt_facts, self.stmts)), pack(expr_facts(self.result)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self)
 return view_facts(self.view)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self)
 return expr_facts(self.addr)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self)
 return expr_facts(self.addr)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self)
 return cat({ pack(expr_facts(self.addr)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self)
 return cat({ pack(expr_facts(self.addr)), pack(expr_facts(self.expected)), pack(expr_facts(self.replacement)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(self)
 return each(expr_facts, self.args)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_expr_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self)
 return cat({ pack(binding_facts(self.binding)), pack(expr_facts(self.init)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self)
 return cat({ pack(binding_facts(self.binding)), pack(erased.once(B.ResidenceFactMutableCell(self.binding))), pack(expr_facts(self.init)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(self)
 return cat({ pack(place_facts(self.place)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(self)
 return cat({ pack(expr_facts(self.addr)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self)
 return expr_facts(self.expr)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(self)
 return expr_facts(self.cond)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self)
 return cat({ pack(expr_facts(self.cond)), pack(each(stmt_facts, self.then_body)), pack(each(stmt_facts, self.else_body)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(self)

            local trips = { pack(expr_facts(self.value)) }
            for i = 1, #self.arms do trips[#trips + 1] = pack(each(stmt_facts, self.arms[i].body)) end
            trips[#trips + 1] = pack(each(stmt_facts, self.default_body))
            return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self)

            local trips = {}
            for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end
            return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(self)

            local trips = {}
            for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end
            return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(self)
 return control_stmt_region_facts(self.region)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function(self)
 return each(expr_facts, self.args)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_stmt_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function func_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_func_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function extern_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExternFunc) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExternFuncOpen) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_extern_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function const_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ConstItem) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.ConstItemOpen) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_const_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function static_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StaticItem) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        elseif schema.isa(node, Tr.StaticItemOpen) then
            return (function(self)
 return expr_facts(self.value)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_static_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function item_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemFunc) then
            return (function(self)
 return func_facts(self.func)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function(self)
 return extern_facts(self.func)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function(self)
 return const_facts(self.c)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function(self)
 return static_facts(self.s)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self)
 return module_facts(self.module)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_item_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function module_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module)
 return each(item_facts, module.items)
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_module_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

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
