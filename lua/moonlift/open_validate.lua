local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local O = T.MoonOpen

    local slot_issue
    local fact_issue
    local validate_facts

    slot_issue = pvm.phase("moonlift_open_slot_issue", {
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
        [O.SlotRegionFrag] = function(self) return pvm.once(O.IssueUnfilledRegionFragSlot(self.slot)) end,
        [O.SlotExprFrag] = function(self) return pvm.once(O.IssueUnfilledExprFragSlot(self.slot)) end,
        [O.SlotName] = function(self) return pvm.once(O.IssueUnfilledNameSlot(self.slot)) end,
    })

    fact_issue = pvm.phase("moonlift_open_fact_issue", {
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
        [O.MetaFactRegionFragSlotUse] = function(self) return pvm.once(O.IssueUnfilledRegionFragSlot(self.slot)) end,
        [O.MetaFactExprFragSlotUse] = function(self) return pvm.once(O.IssueUnfilledExprFragSlot(self.slot)) end,
        [O.MetaFactModuleUse] = function(self) return pvm.once(O.IssueUnexpandedModuleUse(self.use_id)) end,
        [O.MetaFactModuleSlotUse] = function() return pvm.empty() end,
        [O.MetaFactOpenModuleName] = function() return pvm.once(O.IssueOpenModuleName) end,
        [O.MetaFactLocalType] = function() return pvm.empty() end,
    })

    validate_facts = pvm.phase("moonlift_open_validate_facts", function(fact_set)
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

    local function emit_open_issues(report, collector)
        if collector and report and report.issues then
            for i = 1, #report.issues do
                collector:emit(report.issues[i], "open")
            end
        end
    end

    return {
        slot_issue = slot_issue,
        fact_issue = fact_issue,
        validate_facts = validate_facts,
        validate = function(fact_set, collector)
            local result = pvm.one(validate_facts(fact_set))
            emit_open_issues(result, collector)
            return result
        end,
    }
end

-----------------------------------------------------------------------------
-- explain_open_issue: explains a single OpenIssue / ValidationIssue
-----------------------------------------------------------------------------

function M.explain_open_issue(issue, analysis)
    local resolvers = require("moonlift.error.span_resolvers")
    local pvm = require("moonlift.pvm")
    local span = resolvers.open_resolver(issue, analysis)
    local cls = pvm.classof(issue)
    if not cls then
        return { code = "E9999", severity = "error", primary = { span = span, message = tostring(issue) } }
    end
    local kind = cls.kind

    -- Extract slot key from variant-specific field
    local function slot_key()
        if issue.slot then
            local key = issue.slot.key or tostring(issue.slot)
            local pretty = issue.slot.pretty_name
            if pretty and pretty ~= "" then
                return key .. " (" .. pretty .. ")"
            end
            return key
        end
        if issue.use_id then
            return tostring(issue.use_id)
        end
        if issue.import then
            return tostring(issue.import)
        end
        return nil
    end

    local skey = slot_key() or "?"

    local function slot_notes()
        return { { message = "this slot must be filled before compilation — use `@{" .. skey .. " = value}` at the call site" } }
    end
    local function unexpanded_notes()
        return { { message = "this fragment reference could not be expanded at load time" } }
    end

    -- Slot variants (E0801)
    if kind == "IssueUnfilledTypeSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled type slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledValueSlot" or kind == "IssueOpenSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled value slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledExprSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled expression slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledPlaceSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled place slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledDomainSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled domain slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledRegionSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled region slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledContSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled continuation slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledFuncSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled function slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledConstSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled const slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledStaticSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled static slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledTypeDeclSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled type declar slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledItemsSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled items slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledModuleSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled module slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledRegionFragSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled region fragment slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledExprFragSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled expression fragment slot `" .. skey .. "`" }, notes = slot_notes() }
    elseif kind == "IssueUnfilledNameSlot" then
        return { code = "E0801", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unfilled name slot `" .. skey .. "`" }, notes = slot_notes() }

    -- Unexpanded fragment/expr uses (E0802)
    elseif kind == "IssueUnexpandedExprFragUse" then
        return { code = "E0802", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unexpanded expression fragment use `" .. skey .. "`" }, notes = unexpanded_notes() }
    elseif kind == "IssueUnexpandedRegionFragUse" then
        if tostring(skey):match("^call%.") then
            return { code = "E0802", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unexpanded region call `" .. skey .. "`" }, notes = { { message = "region call must lower during open/RNF expansion before Code/backend lowering" }, { message = "this fragment reference could not be expanded at load time" } } }
        end
        return { code = "E0802", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unexpanded region fragment use `" .. skey .. "`" }, notes = unexpanded_notes() }
    elseif kind == "IssueUnexpandedModuleUse" then
        return { code = "E0802", severity = "error", phase_context = "while expanding fragments", primary = { span = span, message = "unexpanded module use `" .. skey .. "`" }, notes = unexpanded_notes() }

    -- Generic value import (E0803)
    elseif kind == "IssueGenericValueImport" then
        return { code = "E0803", severity = "error", phase_context = "while expanding fragments",
            primary = { span = span, message = "generic value import" .. (issue.import and (" for `" .. tostring(issue.import) .. "`") or "") },
            notes = { { message = "value imports from the host language must be declared with a type" } } }

    -- Open module name (E0804)
    elseif kind == "IssueOpenModuleName" then
        return { code = "E0804", severity = "error", phase_context = "while expanding fragments",
            primary = { span = span, message = "open module name requires a module identifier" },
            notes = { { message = "the `open` directive needs a module path to be resolved" } } }

    else
        return { code = "E9999", severity = "error", primary = { span = span, message = "unknown open issue: " .. (kind or tostring(issue)) } }
    end
end

return M
