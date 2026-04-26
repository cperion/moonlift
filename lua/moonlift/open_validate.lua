local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local O = T.Moon2Open

    local slot_issue
    local fact_issue
    local validate_facts

    slot_issue = pvm.phase("moon2_open_slot_issue", {
        [O.SlotType] = function(self) return pvm.once(O.IssueUnfilledTypeSlot(self.slot)) end,
        [O.SlotValue] = function(self) return pvm.once(O.IssueOpenSlot(self)) end,
        [O.SlotExpr] = function(self) return pvm.once(O.IssueUnfilledExprSlot(self.slot)) end,
        [O.SlotPlace] = function(self) return pvm.once(O.IssueUnfilledPlaceSlot(self.slot)) end,
        [O.SlotDomain] = function(self) return pvm.once(O.IssueUnfilledDomainSlot(self.slot)) end,
        [O.SlotRegion] = function(self) return pvm.once(O.IssueUnfilledRegionSlot(self.slot)) end,
        [O.SlotCont] = function(self) return pvm.once(O.IssueUnfilledContSlot(self.slot)) end,
        [O.SlotFunc] = function(self) return pvm.once(O.IssueUnfilledFuncSlot(self.slot)) end,
        [O.SlotConst] = function(self) return pvm.once(O.IssueUnfilledConstSlot(self.slot)) end,
        [O.SlotStatic] = function(self) return pvm.once(O.IssueUnfilledStaticSlot(self.slot)) end,
        [O.SlotTypeDecl] = function(self) return pvm.once(O.IssueUnfilledTypeDeclSlot(self.slot)) end,
        [O.SlotItems] = function(self) return pvm.once(O.IssueUnfilledItemsSlot(self.slot)) end,
        [O.SlotModule] = function(self) return pvm.once(O.IssueUnfilledModuleSlot(self.slot)) end,
    })

    fact_issue = pvm.phase("moon2_open_fact_issue", {
        [O.MetaFactSlot] = function(self) return slot_issue(self.slot) end,
        [O.MetaFactParamUse] = function() return pvm.empty() end,
        [O.MetaFactValueImportUse] = function(self) return pvm.once(O.IssueGenericValueImport(self.import)) end,
        [O.MetaFactLocalValue] = function() return pvm.empty() end,
        [O.MetaFactLocalCell] = function() return pvm.empty() end,
        [O.MetaFactBlockParam] = function() return pvm.empty() end,
        [O.MetaFactEntryBlockParam] = function() return pvm.empty() end,
        [O.MetaFactGlobalFunc] = function() return pvm.empty() end,
        [O.MetaFactGlobalConst] = function() return pvm.empty() end,
        [O.MetaFactGlobalStatic] = function() return pvm.empty() end,
        [O.MetaFactExtern] = function() return pvm.empty() end,
        [O.MetaFactExprFragUse] = function(self) return pvm.once(O.IssueUnexpandedExprFragUse(self.use_id)) end,
        [O.MetaFactRegionFragUse] = function(self) return pvm.once(O.IssueUnexpandedRegionFragUse(self.use_id)) end,
        [O.MetaFactModuleUse] = function(self) return pvm.once(O.IssueUnexpandedModuleUse(self.use_id)) end,
        [O.MetaFactModuleSlotUse] = function() return pvm.empty() end,
        [O.MetaFactOpenModuleName] = function() return pvm.once(O.IssueOpenModuleName) end,
        [O.MetaFactLocalType] = function() return pvm.empty() end,
    })

    validate_facts = pvm.phase("moon2_open_validate_facts", function(fact_set)
        local issues = {}
        local seen = {}
        for i = 1, #fact_set.facts do
            local g, p, c = fact_issue(fact_set.facts[i])
            local one = pvm.drain(g, p, c)
            for j = 1, #one do
                local issue = one[j]
                if not seen[issue] then
                    seen[issue] = true
                    issues[#issues + 1] = issue
                end
            end
        end
        return O.ValidationReport(issues)
    end)

    return {
        slot_issue = slot_issue,
        fact_issue = fact_issue,
        validate_facts = validate_facts,
        validate = function(fact_set) return pvm.one(validate_facts(fact_set)) end,
    }
end

return M
