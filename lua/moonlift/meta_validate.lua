local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Meta = T.MoonliftMeta
    if Meta == nil then error("meta_validate: MoonliftMeta ASDL module is not defined", 2) end

    local Query = require("moonlift.meta_query").Define(T)

    local slot_issue
    local fact_issue

    slot_issue = pvm.phase("meta_validate_slot_issue", {
        [Meta.MetaSlotType] = function(self) return pvm.once(Meta.MetaIssueUnfilledTypeSlot(self.slot)) end,
        [Meta.MetaSlotExpr] = function(self) return pvm.once(Meta.MetaIssueUnfilledExprSlot(self.slot)) end,
        [Meta.MetaSlotPlace] = function(self) return pvm.once(Meta.MetaIssueUnfilledPlaceSlot(self.slot)) end,
        [Meta.MetaSlotDomain] = function(self) return pvm.once(Meta.MetaIssueUnfilledDomainSlot(self.slot)) end,
        [Meta.MetaSlotRegion] = function(self) return pvm.once(Meta.MetaIssueUnfilledRegionSlot(self.slot)) end,
        [Meta.MetaSlotFunc] = function(self) return pvm.once(Meta.MetaIssueUnfilledFuncSlot(self.slot)) end,
        [Meta.MetaSlotConst] = function(self) return pvm.once(Meta.MetaIssueUnfilledConstSlot(self.slot)) end,
        [Meta.MetaSlotStatic] = function(self) return pvm.once(Meta.MetaIssueUnfilledStaticSlot(self.slot)) end,
        [Meta.MetaSlotTypeDecl] = function(self) return pvm.once(Meta.MetaIssueUnfilledTypeDeclSlot(self.slot)) end,
        [Meta.MetaSlotItems] = function(self) return pvm.once(Meta.MetaIssueUnfilledItemsSlot(self.slot)) end,
        [Meta.MetaSlotModule] = function(self) return pvm.once(Meta.MetaIssueUnfilledModuleSlot(self.slot)) end,
    })

    fact_issue = pvm.phase("meta_validate_fact_issue", {
        [Meta.MetaFactSlot] = function(self) return slot_issue(self.slot) end,
        [Meta.MetaFactExprFragUse] = function(self) return pvm.once(Meta.MetaIssueUnexpandedExprFragUse(self.use_id)) end,
        [Meta.MetaFactRegionFragUse] = function(self) return pvm.once(Meta.MetaIssueUnexpandedRegionFragUse(self.use_id)) end,
        [Meta.MetaFactModuleUse] = function(self) return pvm.once(Meta.MetaIssueUnexpandedModuleUse(self.use_id)) end,
        [Meta.MetaFactModuleSlotUse] = function(self) return pvm.once(Meta.MetaIssueUnexpandedModuleUse(self.use_id)) end,
        [Meta.MetaFactOpenModuleName] = function(_, module_name)
            if module_name == nil or module_name == "" then return pvm.once(Meta.MetaIssueOpenModuleName) end
            return pvm.empty()
        end,
        [Meta.MetaFactValueImportUse] = function(self)
            if self.import.kind == "MetaImportValue" then return pvm.once(Meta.MetaIssueGenericValueImport(self.import)) end
            return pvm.empty()
        end,
        [Meta.MetaFactParamUse] = function() return pvm.empty() end,
        [Meta.MetaFactLocalValue] = function() return pvm.empty() end,
        [Meta.MetaFactLocalCell] = function() return pvm.empty() end,
        [Meta.MetaFactLoopCarry] = function() return pvm.empty() end,
        [Meta.MetaFactLoopIndex] = function() return pvm.empty() end,
        [Meta.MetaFactGlobalFunc] = function() return pvm.empty() end,
        [Meta.MetaFactGlobalConst] = function() return pvm.empty() end,
        [Meta.MetaFactGlobalStatic] = function() return pvm.empty() end,
        [Meta.MetaFactExtern] = function() return pvm.empty() end,
        [Meta.MetaFactLocalType] = function() return pvm.empty() end,
    })

    local function issue_key(issue)
        local k = issue.kind
        if issue.slot ~= nil then
            local s = issue.slot
            if s.slot ~= nil then s = s.slot end
            return k .. ":" .. tostring(s.key or s.pretty_name or s)
        end
        if issue.use_id ~= nil then return k .. ":" .. tostring(issue.use_id) end
        if issue.import ~= nil then return k .. ":" .. tostring(issue.import.key or issue.import.symbol or issue.import.item_name) end
        return k
    end

    local function dedupe(issues)
        local out, seen = {}, {}
        for i = 1, #issues do
            local key = issue_key(issues[i])
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = issues[i]
            end
        end
        return out
    end

    local api = {}
    api.phases = { slot_issue = slot_issue, fact_issue = fact_issue }

    function api.report(node, module_name)
        local facts = Query.fact_list(node)
        local issues = {}
        for i = 1, #facts do
            local g, p, c = fact_issue(facts[i], module_name or "")
            pvm.drain_into(g, p, c, issues)
        end
        return Meta.MetaValidationReport(dedupe(issues))
    end

    function api.is_closed(node, module_name)
        return #api.report(node, module_name).issues == 0
    end

    function api.assert_closed(node, module_name)
        local report = api.report(node, module_name)
        if #report.issues ~= 0 then
            local parts = {}
            for i = 1, #report.issues do parts[i] = report.issues[i].kind end
            error("meta_validate: open Meta value is not closed: " .. table.concat(parts, ", "), 2)
        end
        return node
    end

    return api
end

return M
