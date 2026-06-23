local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T, opts)
    opts = opts or {}
    local Ty = T.MoonType
    local Tr = T.MoonTree

    local expr_type
    local stmt_facts
    local stmt_terminates
    local region_facts
    local region_decide

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end
    local function labels_equal(a, b) return a.name == b.name end
    local function control_type_matches(expected, actual)
        if expected == actual then return true end
        if expected == nil or actual == nil then return false end
        local ecls = schema.classof(expected)
        local acls = schema.classof(actual)
        if ecls == Ty.TOwned or acls == Ty.TOwned then return false end
        if ecls == Ty.TAccess then return control_type_matches(expected.base, actual) end
        if acls == Ty.TAccess then return control_type_matches(expected, actual.base) end
        if ecls == Ty.TLease and acls == Ty.TLease and expected.base == actual.base then return true end
        if ecls == Ty.TLease and expected.base == actual then return true end
        return false
    end

    local function expr_ty(expr)
        return erased.one(expr_type(expr.h))
    end

    local function named_type_name(ty)
        if ty ~= nil and schema.classof(ty) == Ty.TNamed then
            local ref = ty.ref
            local cls = schema.classof(ref)
            if cls == Ty.TypeRefGlobal then return ref.type_name or ref.name end
            if cls == Ty.TypeRefPath and ref.path and #ref.path.parts > 0 then return ref.path.parts[#ref.path.parts].text or ref.path.parts[#ref.path.parts].name end
        end
        return nil
    end

    local function body_terminates(stmts)
        for i = 1, #stmts do
            if erased.one(stmt_terminates(stmts[i])) then return true end
        end
        return false
    end

    function expr_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprTyped) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprOpen) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_control_expr_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtJump) then
            return (function(stmt, region_id, from_label, entry_label)

            local facts = { Tr.ControlFactJump(region_id, from_label, stmt.target) }
            for i = 1, #stmt.args do
                facts[#facts + 1] = Tr.ControlFactJumpArg(region_id, from_label, stmt.target, stmt.args[i].name, expr_ty(stmt.args[i].value))
            end
            if labels_equal(stmt.target, from_label) or labels_equal(stmt.target, entry_label) then
                facts[#facts + 1] = Tr.ControlFactBackedge(region_id, from_label, stmt.target)
            end
            return erased.children(function(fact) return erased.once(fact) end, facts)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(_, region_id, from_label)

            return erased.once(Tr.ControlFactYieldVoid(region_id, from_label))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(stmt, region_id, from_label)

            return erased.once(Tr.ControlFactYieldValue(region_id, from_label, expr_ty(stmt.value)))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(_, region_id, from_label)

            return erased.once(Tr.ControlFactReturn(region_id, from_label))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(_, region_id, from_label)

            return erased.once(Tr.ControlFactReturn(region_id, from_label))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(stmt, region_id, from_label, entry_label)

            local out = {}
            for i = 1, #stmt.then_body do append_all(out, stmt_facts(stmt.then_body[i], region_id, from_label, entry_label)) end
            for i = 1, #stmt.else_body do append_all(out, stmt_facts(stmt.else_body[i], region_id, from_label, entry_label)) end
            return erased.children(function(fact) return erased.once(fact) end, out)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(stmt, region_id, from_label, entry_label)

            local out = {}
            for i = 1, #stmt.arms do
                for j = 1, #stmt.arms[i].body do append_all(out, stmt_facts(stmt.arms[i].body[j], region_id, from_label, entry_label)) end
            end
            if #(stmt.variant_arms or {}) > 0 then
                local arm_facts = {}
                local type_name = named_type_name(expr_ty(stmt.value))
                local def = type_name and opts.variant_def and opts.variant_def(type_name) or nil
                for i = 1, #(stmt.variant_arms or {}) do
                    local arm = stmt.variant_arms[i]
                    local variant = def and def.variants[arm.variant_name] or nil
                    local binds = {}
                    for j = 1, #(arm.binds or {}) do binds[#binds + 1] = Tr.BlockParam(arm.binds[j].name, arm.binds[j].ty) end
                    arm_facts[#arm_facts + 1] = Tr.ControlVariantArmFact(arm.variant_name, variant and variant.tag or -1, Tr.BlockLabel("variant:" .. from_label.name .. ":" .. arm.variant_name), binds)
                    for j = 1, #arm.body do append_all(out, stmt_facts(arm.body[j], region_id, from_label, entry_label)) end
                end
                out[#out + 1] = Tr.ControlFactVariantSwitch(region_id, from_label, type_name or "", arm_facts, Tr.BlockLabel("variant:" .. from_label.name .. ":default"))
            end
            for i = 1, #stmt.default_body do append_all(out, stmt_facts(stmt.default_body[i], region_id, from_label, entry_label)) end
            return erased.children(function(fact) return erased.once(fact) end, out)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(stmt)

            return region_facts(stmt.region)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtLet) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtTrap) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_control_stmt_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_terminates(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtJump) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(stmt)
 return erased.once(body_terminates(stmt.then_body) and body_terminates(stmt.else_body))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(stmt)

            if not body_terminates(stmt.default_body) then return erased.once(false) end
            for i = 1, #stmt.arms do
                if not body_terminates(stmt.arms[i].body) then return erased.once(false) end
            end
            for i = 1, #(stmt.variant_arms or {}) do
                if not body_terminates(stmt.variant_arms[i].body) then return erased.once(false) end
            end
            return erased.once(true)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtLet) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function()
 return erased.once(false)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtTrap) then
            return (function()
 return erased.once(true)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_control_stmt_terminates: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function entry_facts(region_id, entry)
        local facts = { Tr.ControlFactEntryBlock(region_id, entry.label), Tr.ControlFactBlock(region_id, entry.label) }
        for i = 1, #entry.params do
            facts[#facts + 1] = Tr.ControlFactEntryParam(region_id, entry.label, i, entry.params[i].name, entry.params[i].ty)
            facts[#facts + 1] = Tr.ControlFactBlockParam(region_id, entry.label, i, entry.params[i].name, entry.params[i].ty)
        end
        for i = 1, #entry.body do append_all(facts, stmt_facts(entry.body[i], region_id, entry.label, entry.label)) end
        return facts
    end

    local function block_facts(region_id, entry_label, block)
        local facts = { Tr.ControlFactBlock(region_id, block.label) }
        for i = 1, #block.params do
            facts[#facts + 1] = Tr.ControlFactBlockParam(region_id, block.label, i, block.params[i].name, block.params[i].ty)
        end
        for i = 1, #block.body do append_all(facts, stmt_facts(block.body[i], region_id, block.label, entry_label)) end
        return facts
    end

    local function facts_for(region_id, entry, blocks)
        local facts = entry_facts(region_id, entry)
        for i = 1, #blocks do append_all(facts, block_facts(region_id, entry.label, blocks[i])) end
        return facts
    end

    function region_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(region)

            return erased.children(function(fact) return erased.once(fact) end, facts_for(region.region_id, region.entry, region.blocks))
            end)(node, ...)
        elseif schema.isa(node, Tr.ControlExprRegion) then
            return (function(region)

            return erased.children(function(fact) return erased.once(fact) end, facts_for(region.region_id, region.entry, region.blocks))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_control_region_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function has_label(labels, label)
        return labels[label.name] == true
    end

    local function jump_key(from_label, to_label)
        return from_label.name .. "->" .. to_label.name
    end

    local function decide_from_facts(region, facts)
        local labels = {}
        local params_by_label = {}
        local args_by_jump = {}
        local jump_fact_key = {}
        local current_jump_key = nil
        local jump_seq = 0
        local is_expr_region = schema.classof(region) == Tr.ControlExprRegion
        for i = 1, #facts do
            local fact = facts[i]
            local cls = schema.classof(fact)
            if cls == Tr.ControlFactJump then
                jump_seq = jump_seq + 1
                current_jump_key = jump_key(fact.from_label, fact.to_label) .. "#" .. tostring(jump_seq)
                jump_fact_key[i] = current_jump_key
            elseif cls ~= Tr.ControlFactJumpArg then
                current_jump_key = nil
            end
            if cls == Tr.ControlFactBlock then
                if labels[fact.label.name] then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectDuplicateLabel(region.region_id, fact.label))
                end
                labels[fact.label.name] = true
                params_by_label[fact.label.name] = params_by_label[fact.label.name] or {}
            elseif cls == Tr.ControlFactBlockParam then
                local params = params_by_label[fact.label.name] or {}
                params[fact.name] = fact.ty
                params_by_label[fact.label.name] = params
            elseif cls == Tr.ControlFactJumpArg then
                local key = current_jump_key or (jump_key(fact.from_label, fact.to_label) .. "#orphan")
                local args = args_by_jump[key] or { label = fact.to_label, by_name = {} }
                if args.by_name[fact.name] ~= nil then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectDuplicateJumpArg(region.region_id, fact.to_label, fact.name))
                end
                args.by_name[fact.name] = fact.ty
                args_by_jump[key] = args
            elseif cls == Tr.ControlFactYieldVoid then
                if is_expr_region then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectYieldOutsideRegion("void yield in value-producing control region"))
                end
            elseif cls == Tr.ControlFactYieldValue then
                if not is_expr_region then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectYieldOutsideRegion("value yield in statement control region"))
                end
                if not control_type_matches(region.result_ty, fact.ty) then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectYieldType(region.region_id, region.result_ty, fact.ty))
                end
            end
        end
        for i = 1, #facts do
            local fact = facts[i]
            if schema.classof(fact) == Tr.ControlFactJump then
                if not has_label(labels, fact.to_label) then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectMissingLabel(region.region_id, fact.to_label))
                end
                local params = params_by_label[fact.to_label.name] or {}
                local args = (args_by_jump[jump_fact_key[i]] or { by_name = {} }).by_name
                for name, expected in pairs(params) do
                    if args[name] == nil then
                        return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectMissingJumpArg(region.region_id, fact.to_label, name))
                    end
                    if not control_type_matches(expected, args[name]) then
                        return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectJumpType(region.region_id, fact.to_label, name, expected, args[name]))
                    end
                end
                for name, _ in pairs(args) do
                    if params[name] == nil then
                        return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectExtraJumpArg(region.region_id, fact.to_label, name))
                    end
                end
            end
        end
        if not body_terminates(region.entry.body) then
            return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectUnterminatedBlock(region.region_id, region.entry.label))
        end
        for i = 1, #region.blocks do
            if not body_terminates(region.blocks[i].body) then
                return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectUnterminatedBlock(region.region_id, region.blocks[i].label))
            end
        end
        return Tr.ControlDecisionReducible(region.region_id, facts)
    end

    function region_decide(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(region)

            local facts = region_facts(region)
            return erased.once(decide_from_facts(region, facts))
            end)(node, ...)
        elseif schema.isa(node, Tr.ControlExprRegion) then
            return (function(region)

            local facts = region_facts(region)
            return erased.once(decide_from_facts(region, facts))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_control_decide: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        stmt_facts = stmt_facts,
        stmt_terminates = stmt_terminates,
        region_facts = region_facts,
        region_decide = region_decide,
        facts = function(region) return Tr.ControlFactSet(region_facts(region)) end,
        decide = function(region) return erased.one(region_decide(region)) end,
    }
end

return M
