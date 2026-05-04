local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Tr = T.MoonTree

    local expr_type
    local stmt_facts
    local stmt_terminates
    local region_facts
    local region_decide

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end
    local function labels_equal(a, b) return a.name == b.name end

    local function expr_ty(expr)
        return pvm.one(expr_type(expr.h))
    end

    local function body_terminates(stmts)
        for i = 1, #stmts do
            if pvm.one(stmt_terminates(stmts[i])) then return true end
        end
        return false
    end

    expr_type = pvm.phase("moonlift_tree_control_expr_type", {
        [Tr.ExprTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprOpen] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSem] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprCode] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSurface] = function() return pvm.empty() end,
    })

    stmt_facts = pvm.phase("moonlift_tree_control_stmt_facts", {
        [Tr.StmtJump] = function(stmt, region_id, from_label, entry_label)
            local facts = { Tr.ControlFactJump(region_id, from_label, stmt.target) }
            for i = 1, #stmt.args do
                facts[#facts + 1] = Tr.ControlFactJumpArg(region_id, from_label, stmt.target, stmt.args[i].name, expr_ty(stmt.args[i].value))
            end
            if labels_equal(stmt.target, from_label) or labels_equal(stmt.target, entry_label) then
                facts[#facts + 1] = Tr.ControlFactBackedge(region_id, from_label, stmt.target)
            end
            return pvm.children(function(fact) return pvm.once(fact) end, facts)
        end,
        [Tr.StmtYieldVoid] = function(_, region_id, from_label)
            return pvm.once(Tr.ControlFactYieldVoid(region_id, from_label))
        end,
        [Tr.StmtYieldValue] = function(stmt, region_id, from_label)
            return pvm.once(Tr.ControlFactYieldValue(region_id, from_label, expr_ty(stmt.value)))
        end,
        [Tr.StmtReturnVoid] = function(_, region_id, from_label)
            return pvm.once(Tr.ControlFactReturn(region_id, from_label))
        end,
        [Tr.StmtReturnValue] = function(_, region_id, from_label)
            return pvm.once(Tr.ControlFactReturn(region_id, from_label))
        end,
        [Tr.StmtIf] = function(stmt, region_id, from_label, entry_label)
            local out = {}
            for i = 1, #stmt.then_body do append_all(out, pvm.drain(stmt_facts(stmt.then_body[i], region_id, from_label, entry_label))) end
            for i = 1, #stmt.else_body do append_all(out, pvm.drain(stmt_facts(stmt.else_body[i], region_id, from_label, entry_label))) end
            return pvm.children(function(fact) return pvm.once(fact) end, out)
        end,
        [Tr.StmtSwitch] = function(stmt, region_id, from_label, entry_label)
            local out = {}
            for i = 1, #stmt.arms do
                for j = 1, #stmt.arms[i].body do append_all(out, pvm.drain(stmt_facts(stmt.arms[i].body[j], region_id, from_label, entry_label))) end
            end
            for i = 1, #(stmt.variant_arms or {}) do
                for j = 1, #stmt.variant_arms[i].body do append_all(out, pvm.drain(stmt_facts(stmt.variant_arms[i].body[j], region_id, from_label, entry_label))) end
            end
            for i = 1, #stmt.default_body do append_all(out, pvm.drain(stmt_facts(stmt.default_body[i], region_id, from_label, entry_label))) end
            return pvm.children(function(fact) return pvm.once(fact) end, out)
        end,
        [Tr.StmtControl] = function(stmt)
            return region_facts(stmt.region)
        end,
        [Tr.StmtLet] = function() return pvm.empty() end,
        [Tr.StmtVar] = function() return pvm.empty() end,
        [Tr.StmtSet] = function() return pvm.empty() end,
        [Tr.StmtExpr] = function() return pvm.empty() end,
        [Tr.StmtAssert] = function() return pvm.empty() end,
        [Tr.StmtJumpCont] = function() return pvm.empty() end,
        [Tr.StmtUseRegionSlot] = function() return pvm.empty() end,
        [Tr.StmtUseRegionFrag] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    stmt_terminates = pvm.phase("moonlift_tree_control_stmt_terminates", {
        [Tr.StmtJump] = function() return pvm.once(true) end,
        [Tr.StmtJumpCont] = function() return pvm.once(true) end,
        [Tr.StmtYieldVoid] = function() return pvm.once(true) end,
        [Tr.StmtYieldValue] = function() return pvm.once(true) end,
        [Tr.StmtReturnVoid] = function() return pvm.once(true) end,
        [Tr.StmtReturnValue] = function() return pvm.once(true) end,
        [Tr.StmtIf] = function(stmt) return pvm.once(body_terminates(stmt.then_body) and body_terminates(stmt.else_body)) end,
        [Tr.StmtSwitch] = function(stmt)
            if not body_terminates(stmt.default_body) then return pvm.once(false) end
            for i = 1, #stmt.arms do
                if not body_terminates(stmt.arms[i].body) then return pvm.once(false) end
            end
            for i = 1, #(stmt.variant_arms or {}) do
                if not body_terminates(stmt.variant_arms[i].body) then return pvm.once(false) end
            end
            return pvm.once(true)
        end,
        [Tr.StmtLet] = function() return pvm.once(false) end,
        [Tr.StmtVar] = function() return pvm.once(false) end,
        [Tr.StmtSet] = function() return pvm.once(false) end,
        [Tr.StmtExpr] = function() return pvm.once(false) end,
        [Tr.StmtAssert] = function() return pvm.once(false) end,
        [Tr.StmtControl] = function() return pvm.once(false) end,
        [Tr.StmtUseRegionSlot] = function() return pvm.once(false) end,
        [Tr.StmtUseRegionFrag] = function() return pvm.once(false) end,
    })

    local function entry_facts(region_id, entry)
        local facts = { Tr.ControlFactEntryBlock(region_id, entry.label), Tr.ControlFactBlock(region_id, entry.label) }
        for i = 1, #entry.params do
            facts[#facts + 1] = Tr.ControlFactEntryParam(region_id, entry.label, i, entry.params[i].name, entry.params[i].ty)
            facts[#facts + 1] = Tr.ControlFactBlockParam(region_id, entry.label, i, entry.params[i].name, entry.params[i].ty)
        end
        for i = 1, #entry.body do append_all(facts, pvm.drain(stmt_facts(entry.body[i], region_id, entry.label, entry.label))) end
        return facts
    end

    local function block_facts(region_id, entry_label, block)
        local facts = { Tr.ControlFactBlock(region_id, block.label) }
        for i = 1, #block.params do
            facts[#facts + 1] = Tr.ControlFactBlockParam(region_id, block.label, i, block.params[i].name, block.params[i].ty)
        end
        for i = 1, #block.body do append_all(facts, pvm.drain(stmt_facts(block.body[i], region_id, block.label, entry_label))) end
        return facts
    end

    local function facts_for(region_id, entry, blocks)
        local facts = entry_facts(region_id, entry)
        for i = 1, #blocks do append_all(facts, block_facts(region_id, entry.label, blocks[i])) end
        return facts
    end

    region_facts = pvm.phase("moonlift_tree_control_region_facts", {
        [Tr.ControlStmtRegion] = function(region)
            return pvm.children(function(fact) return pvm.once(fact) end, facts_for(region.region_id, region.entry, region.blocks))
        end,
        [Tr.ControlExprRegion] = function(region)
            return pvm.children(function(fact) return pvm.once(fact) end, facts_for(region.region_id, region.entry, region.blocks))
        end,
    })

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
        local is_expr_region = pvm.classof(region) == Tr.ControlExprRegion
        for i = 1, #facts do
            local fact = facts[i]
            local cls = pvm.classof(fact)
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
                if fact.ty ~= region.result_ty then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectYieldType(region.region_id, region.result_ty, fact.ty))
                end
            end
        end
        for i = 1, #facts do
            local fact = facts[i]
            if pvm.classof(fact) == Tr.ControlFactJump then
                if not has_label(labels, fact.to_label) then
                    return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectMissingLabel(region.region_id, fact.to_label))
                end
                local params = params_by_label[fact.to_label.name] or {}
                local args = (args_by_jump[jump_fact_key[i]] or { by_name = {} }).by_name
                for name, expected in pairs(params) do
                    if args[name] == nil then
                        return Tr.ControlDecisionIrreducible(region.region_id, Tr.ControlRejectMissingJumpArg(region.region_id, fact.to_label, name))
                    end
                    if args[name] ~= expected then
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

    region_decide = pvm.phase("moonlift_tree_control_decide", {
        [Tr.ControlStmtRegion] = function(region)
            local facts = pvm.drain(region_facts(region))
            return pvm.once(decide_from_facts(region, facts))
        end,
        [Tr.ControlExprRegion] = function(region)
            local facts = pvm.drain(region_facts(region))
            return pvm.once(decide_from_facts(region, facts))
        end,
    })

    return {
        stmt_facts = stmt_facts,
        stmt_terminates = stmt_terminates,
        region_facts = region_facts,
        region_decide = region_decide,
        facts = function(region) return Tr.ControlFactSet(pvm.drain(region_facts(region))) end,
        decide = function(region) return pvm.one(region_decide(region)) end,
    }
end

return M
