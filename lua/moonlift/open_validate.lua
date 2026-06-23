local schema = require("moonlift.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local M = {}

local function bind_context(T)
    local O = T.MoonOpen

    local slot_issue
    local fact_issue
    local validate_facts

    function slot_issue(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.SlotType) then
            return (function(self)
 return single(O.IssueUnfilledTypeSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotValue) then
            return (function(self)
 return single(O.IssueOpenSlot(self))
            end)(node, ...)
        elseif schema.isa(node, O.SlotExpr) then
            return (function(self)
 return single(O.IssueUnfilledExprSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotPlace) then
            return (function(self)
 return single(O.IssueUnfilledPlaceSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotDomain) then
            return (function(self)
 return single(O.IssueUnfilledDomainSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegion) then
            return (function(self)
 return single(O.IssueUnfilledRegionSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotCont) then
            return (function(self)
 return single(O.IssueUnfilledContSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotFunc) then
            return (function(self)
 return single(O.IssueUnfilledFuncSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotConst) then
            return (function(self)
 return single(O.IssueUnfilledConstSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotStatic) then
            return (function(self)
 return single(O.IssueUnfilledStaticSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotTypeDecl) then
            return (function(self)
 return single(O.IssueUnfilledTypeDeclSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotItems) then
            return (function(self)
 return single(O.IssueUnfilledItemsSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotModule) then
            return (function(self)
 return single(O.IssueUnfilledModuleSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegionFrag) then
            return (function(self)
 return single(O.IssueUnfilledRegionFragSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotExprFrag) then
            return (function(self)
 return single(O.IssueUnfilledExprFragSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.SlotName) then
            return (function(self)
 return single(O.IssueUnfilledNameSlot(self.slot))
            end)(node, ...)
        else
            error("phase moonlift_open_slot_issue: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function fact_issue(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.MetaFactSlot) then
            return (function(self)
 return slot_issue(self.slot)
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactParamUse) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactValueImportUse) then
            return (function(self)
 return single(O.IssueGenericValueImport(self.import))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactLocalValue) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactLocalCell) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactBlockParam) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactEntryBlockParam) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactGlobalFunc) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactGlobalConst) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactGlobalStatic) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactExtern) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactExprFragUse) then
            return (function(self)
 return single(O.IssueUnexpandedExprFragUse(self.use_id))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactRegionFragUse) then
            return (function(self)
 return single(O.IssueUnexpandedRegionFragUse(self.use_id))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactRegionFragSlotUse) then
            return (function(self)
 return single(O.IssueUnfilledRegionFragSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactExprFragSlotUse) then
            return (function(self)
 return single(O.IssueUnfilledExprFragSlot(self.slot))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactModuleUse) then
            return (function(self)
 return single(O.IssueUnexpandedModuleUse(self.use_id))
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactModuleSlotUse) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactOpenModuleName) then
            return (function()
 return single(O.IssueOpenModuleName)
            end)(node, ...)
        elseif schema.isa(node, O.MetaFactLocalType) then
            return (function()
 return {}
            end)(node, ...)
        else
            error("phase moonlift_open_fact_issue: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function validate_facts(fact_set)
        local issues = {}
        local seen = {}
        for i = 1, #fact_set.facts do
            local g, p, c = fact_issue(fact_set.facts[i])
            local one = g
            for j = 1, #one do
                local issue = one[j]
                if not seen[issue] then
                    seen[issue] = true
                    issues[#issues + 1] = issue
                end
            end
        end
        return O.ValidationReport(issues)
    end

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
            local result = validate_facts(fact_set)
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
    local span = resolvers.open_resolver(issue, analysis)
    local cls = schema.classof(issue)
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

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})