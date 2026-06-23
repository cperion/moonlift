local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

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
    local cont_binding_facts
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
    local switch_variant_expr_arm_facts
    local switch_expr_arm_facts
    local func_facts
    local extern_facts
    local const_facts
    local static_facts
    local type_decl_facts
    local region_frag_facts
    local expr_frag_facts
    local item_facts
    local module_facts

    local function pack(g, p, c) return { g, p, c } end
    local function cat(trips) return pvm.concat_all(trips) end
    local function each(phase, xs) return pvm.children(phase, xs) end
    local function slot(slot_node) return pvm.once(O.MetaFactSlot(slot_node)) end
    local function declared_cont_keys(conts)
        local out = {}
        for i = 1, #(conts or {}) do out[conts[i].key] = true end
        return out
    end

    local function filter_template_facts(allowed_conts, g, p, c)
        local facts = pvm.drain(g, p, c)
        local out = {}
        for i = 1, #facts do
            local cls = schema.classof(facts[i])
            local keep = cls ~= O.MetaFactRegionFragUse and cls ~= O.MetaFactExprFragUse
            if keep and cls == O.MetaFactSlot and schema.classof(facts[i].slot) == O.SlotCont then
                keep = not (allowed_conts and allowed_conts[facts[i].slot.slot.key])
            end
            if keep then
                out[#out + 1] = facts[i]
            end
        end
        return pvm.children(function(fact) return pvm.once(fact) end, out)
    end

    function slot_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.SlotType) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValue) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotExpr) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotPlace) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotDomain) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegion) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotCont) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotFunc) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotConst) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotStatic) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotTypeDecl) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotItems) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotModule) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegionFrag) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotExprFrag) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        elseif schema.isa(node, O.SlotName) then
            return (function(self)
 return slot(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_slot_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_import_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.ImportValue) then
            return (function(self)
 return erased.once(O.MetaFactValueImportUse(self))
            end)(node, ...)
        elseif schema.isa(node, O.ImportGlobalFunc) then
            return (function(self)
 return erased.once(O.MetaFactGlobalFunc(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, O.ImportGlobalConst) then
            return (function(self)
 return erased.once(O.MetaFactGlobalConst(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, O.ImportGlobalStatic) then
            return (function(self)
 return erased.once(O.MetaFactGlobalStatic(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, O.ImportExtern) then
            return (function(self)
 return erased.once(O.MetaFactExtern(self.symbol))
            end)(node, ...)
        else
            error("erased phase moonlift_open_value_import_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function open_set_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.OpenSet) then
            return (function(open)

            return cat({
                pack(each(value_import_fact, open.value_imports)),
                pack(each(slot_fact, open.slots)),
            })
            end)(node, ...)
        else
            error("erased phase moonlift_open_set_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_header_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprTyped) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprOpen) then
            return (function(self)
 return open_set_facts(self.open)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expr_header_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function place_header_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceTyped) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceOpen) then
            return (function(self)
 return open_set_facts(self.open)
            end)(node, ...)
        else
            error("erased phase moonlift_open_place_header_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_header_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtOpen) then
            return (function(self)
 return open_set_facts(self.open)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtFlow) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_stmt_header_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function module_header_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ModuleSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleTyped) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleOpen) then
            return (function(self)

            local name_trip
            if self.name == O.ModuleNameOpen then
                name_trip = pack(erased.once(O.MetaFactOpenModuleName))
            else
                name_trip = pack(erased.empty())
            end
            return cat({ name_trip, pack(open_set_facts(self.open)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleSem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleCode) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_module_header_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binding_class_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.BindingClassLocalValue) then
            return (function(_, binding)
 return erased.once(O.MetaFactLocalValue(binding.id.text, binding.name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassLocalCell) then
            return (function(_, binding)
 return erased.once(O.MetaFactLocalCell(binding.id.text, binding.name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassArg) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassEntryBlockParam) then
            return (function(self, binding)
 return erased.once(O.MetaFactEntryBlockParam(self.region_id, self.block_name, self.index, binding.name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassBlockParam) then
            return (function(self, binding)
 return erased.once(O.MetaFactBlockParam(self.region_id, self.block_name, self.index, binding.name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassGlobalFunc) then
            return (function(self)
 return erased.once(O.MetaFactGlobalFunc(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassGlobalConst) then
            return (function(self)
 return erased.once(O.MetaFactGlobalConst(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassGlobalStatic) then
            return (function(self)
 return erased.once(O.MetaFactGlobalStatic(self.module_name, self.item_name))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassExtern) then
            return (function(self)
 return erased.once(O.MetaFactExtern(self.symbol))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenParam) then
            return (function(self)
 return erased.once(O.MetaFactParamUse(self.param))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassImport) then
            return (function(self)
 return value_import_fact(self.import)
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenSym) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenSlot) then
            return (function(self)
 return erased.once(O.MetaFactSlot(self.slot))
            end)(node, ...)
        else
            error("erased phase moonlift_open_binding_class_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binding_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.Binding) then
            return (function(binding)

            return binding_class_facts(binding.class, binding)
            end)(node, ...)
        else
            error("erased phase moonlift_open_binding_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefBinding) then
            return (function(self)
 return binding_facts(self.binding)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(self)
 return erased.once(O.MetaFactSlot(self.slot))
            end)(node, ...)
        else
            error("erased phase moonlift_open_value_ref_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function slot_value_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.SlotValueType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueExpr) then
            return (function(self)
 return expr_facts(self.expr)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValuePlace) then
            return (function(self)
 return place_facts(self.place)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueDomain) then
            return (function(self)
 return domain_facts(self.domain)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueRegion) then
            return (function(self)
 return each(stmt_facts, self.body)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueCont) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueContSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueFunc) then
            return (function(self)
 return func_facts(self.func)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueConst) then
            return (function(self)
 return const_facts(self.c)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueStatic) then
            return (function(self)
 return static_facts(self.s)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueTypeDecl) then
            return (function(self)
 return type_decl_facts(self.t)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueItems) then
            return (function(self)
 return each(item_facts, self.items)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueModule) then
            return (function(self)
 return module_facts(self.module)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueRegionFrag) then
            return (function(self)
 return region_frag_facts(self.frag)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueExprFrag) then
            return (function(self)
 return expr_frag_facts(self.frag)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValueName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_slot_value_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function slot_binding_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.SlotBinding) then
            return (function(binding)

            return slot_value_facts(binding.value)
            end)(node, ...)
        else
            error("erased phase moonlift_open_slot_binding_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function cont_binding_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.ContBinding) then
            return (function(binding)

            -- A continuation target slot in a fill binding is a lexical route,
            -- not an unfilled template hole.  Missing continuation fills are
            -- still reported from the StmtJumpCont left after RNF when no route
            -- exists.
            return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_cont_binding_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function fill_set_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.FillSet) then
            return (function(fills)

            return each(slot_binding_facts, fills.bindings)
            end)(node, ...)
        else
            error("erased phase moonlift_open_fill_set_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function field_init_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FieldInit) then
            return (function(init)

            return expr_facts(init.value)
            end)(node, ...)
        else
            error("erased phase moonlift_open_field_init_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function switch_stmt_arm_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.SwitchStmtArm) then
            return (function(arm)

            return each(stmt_facts, arm.body)
            end)(node, ...)
        else
            error("erased phase moonlift_open_switch_stmt_arm_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function switch_variant_arm_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.SwitchVariantStmtArm) then
            return (function(arm)

            return each(stmt_facts, arm.body)
            end)(node, ...)
        else
            error("erased phase moonlift_open_switch_variant_arm_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function switch_expr_arm_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.SwitchExprArm) then
            return (function(arm)

            return cat({ pack(each(stmt_facts, arm.body)), pack(expr_facts(arm.result)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_switch_expr_arm_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function switch_variant_expr_arm_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.SwitchVariantExprArm) then
            return (function(arm)

            return cat({ pack(each(stmt_facts, arm.body)), pack(expr_facts(arm.result)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_switch_variant_expr_arm_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            error("erased phase moonlift_open_view_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            return (function(self)
 return erased.once(O.MetaFactSlot(O.SlotDomain(self.slot)))
            end)(node, ...)
        else
            error("erased phase moonlift_open_domain_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            error("erased phase moonlift_open_index_base_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function place_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(value_ref_facts(self.ref)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(expr_facts(self.base)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(place_facts(self.base)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(place_facts(self.base)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(index_base_facts(self.base)), pack(expr_facts(self.index)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function(self)
 return cat({ pack(place_header_facts(self.h)), pack(erased.once(O.MetaFactSlot(O.SlotPlace(self.slot)))) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_place_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            error("erased phase moonlift_open_control_stmt_region_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            error("erased phase moonlift_open_control_expr_region_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self)
 return expr_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(value_ref_facts(self.ref)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.base)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.lhs)), pack(expr_facts(self.rhs)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.args)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(place_facts(self.place)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.args)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.base)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(index_base_facts(self.base)), pack(expr_facts(self.index)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(field_init_facts, self.fields)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCtor) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.args)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprNull) then
            return (function(self)
 return expr_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(expr_facts, self.elems)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.cond)), pack(expr_facts(self.then_expr)), pack(expr_facts(self.else_expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)), pack(each(switch_expr_arm_facts, self.arms)), pack(each(switch_variant_expr_arm_facts, self.variant_arms or {})), pack(each(stmt_facts, self.default_body or {})), pack(expr_facts(self.default_expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(control_expr_region_facts(self.region)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(stmt_facts, self.stmts)), pack(expr_facts(self.result)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(each(stmt_facts, self.body)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(view_facts(self.view)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.addr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSizeOf) then
            return (function(self)
 return expr_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAlignOf) then
            return (function(self)
 return expr_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIsNull) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.addr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.addr)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(expr_facts(self.addr)), pack(expr_facts(self.expected)), pack(expr_facts(self.replacement)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function(self)
 return cat({ pack(expr_header_facts(self.h)), pack(erased.once(O.MetaFactSlot(O.SlotExpr(self.slot)))) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(self)

            local ref_trip
            if schema.classof(self.frag) == O.ExprFragRefSlot then
                ref_trip = pack(erased.once(O.MetaFactSlot(O.SlotExprFrag(self.frag.slot))))
            else
                ref_trip = pack(erased.empty())
            end
            return cat({ pack(expr_header_facts(self.h)), pack(erased.once(O.MetaFactExprFragUse(self.use_id))), ref_trip, pack(each(expr_facts, self.args)), pack(each(slot_binding_facts, self.fills)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_expr_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(binding_facts(self.binding)), pack(expr_facts(self.init)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(binding_facts(self.binding)), pack(expr_facts(self.init)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(place_facts(self.place)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.addr)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function(self)
 return stmt_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.expr)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.cond)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.cond)), pack(each(stmt_facts, self.then_body)), pack(each(stmt_facts, self.else_body)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)), pack(each(switch_stmt_arm_facts, self.arms)), pack(each(switch_variant_arm_facts, self.variant_arms or {})), pack(each(stmt_facts, self.default_body)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self)
 local trips = { pack(stmt_header_facts(self.h)) }; for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end; return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(self)
 local trips = { pack(stmt_header_facts(self.h)), pack(erased.once(O.MetaFactSlot(O.SlotCont(self.slot)))) }; for i = 1, #self.args do trips[#trips + 1] = pack(expr_facts(self.args[i].value)) end; return cat(trips)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(self)
 return stmt_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(self)
 return stmt_header_facts(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(expr_facts(self.value)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(control_stmt_region_facts(self.region)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function(self)
 return cat({ pack(stmt_header_facts(self.h)), pack(erased.once(O.MetaFactSlot(O.SlotRegion(self.slot)))) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function(self)

            local ref_trip
            if schema.classof(self.frag) == O.RegionFragRefSlot then
                ref_trip = pack(erased.once(O.MetaFactSlot(O.SlotRegionFrag(self.frag.slot))))
            else
                ref_trip = pack(erased.empty())
            end
            return cat({ pack(stmt_header_facts(self.h)), pack(erased.once(O.MetaFactRegionFragUse(self.use_id))), ref_trip, pack(each(expr_facts, self.args)), pack(each(slot_binding_facts, self.fills)), pack(each(cont_binding_facts, self.cont_fills or {})) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtTrap) then
            return (function(self)
 return stmt_header_facts(self.h)
            end)(node, ...)
        else
            error("erased phase moonlift_open_stmt_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
 return cat({ pack(open_set_facts(self.open)), pack(each(stmt_facts, self.body)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_func_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            error("erased phase moonlift_open_extern_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
 return cat({ pack(open_set_facts(self.open)), pack(expr_facts(self.value)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_const_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
 return cat({ pack(open_set_facts(self.open)), pack(expr_facts(self.value)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_static_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function type_decl_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.TypeDeclStruct) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclUnion) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclEnumSugar) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclTaggedUnionSugar) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclHandle) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenStruct) then
            return (function(self)
 return erased.once(O.MetaFactLocalType(self.sym))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenUnion) then
            return (function(self)
 return erased.once(O.MetaFactLocalType(self.sym))
            end)(node, ...)
        else
            error("erased phase moonlift_open_type_decl_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function region_frag_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RegionFragDecl) then
            return (function(self)

            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RegionFrag) then
            return (function(self)

            local allowed_conts = declared_cont_keys(self.conts)
            local trips = { pack(open_set_facts(self.open)), pack(filter_template_facts(allowed_conts, entry_block_facts(self.entry))) }
            for i = 1, #self.blocks do
                trips[#trips + 1] = pack(filter_template_facts(allowed_conts, control_block_facts(self.blocks[i])))
            end
            return cat(trips)
            end)(node, ...)
        else
            error("erased phase moonlift_open_region_frag_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_frag_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.ExprFrag) then
            return (function(self)

            return cat({ pack(open_set_facts(self.open)), pack(filter_template_facts(nil, expr_facts(self.body))) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_expr_frag_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
            return (function(self)
 return type_decl_facts(self.t)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function(self)
 return region_frag_facts(self.frag)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function(self)
 return expr_frag_facts(self.frag)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function(self)
 return erased.once(O.MetaFactSlot(O.SlotTypeDecl(self.slot)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function(self)
 return erased.once(O.MetaFactSlot(O.SlotItems(self.slot)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self)
 return cat({ pack(erased.once(O.MetaFactModuleUse(self.use_id))), pack(module_facts(self.module)), pack(each(slot_binding_facts, self.fills)) })
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function(self)
 return cat({ pack(erased.once(O.MetaFactModuleSlotUse(self.use_id, self.slot))), pack(erased.once(O.MetaFactSlot(O.SlotModule(self.slot)))), pack(each(slot_binding_facts, self.fills)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_item_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function module_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module)

            return cat({ pack(module_header_facts(module.h)), pack(each(item_facts, module.items)) })
            end)(node, ...)
        else
            error("erased phase moonlift_open_module_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

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
