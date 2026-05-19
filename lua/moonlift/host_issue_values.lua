local M = {}

function M.Install(api, session, collector)
    local H = session.T.MoonHost

    local function report(issues)
        return H.HostReport(issues or {})
    end

    function api.host_report(issues)
        return report(issues)
    end

    function api.no_host_issues()
        return report({})
    end

    function api.host_issue_invalid_name(site, name)
        return H.HostIssueInvalidName(site, tostring(name))
    end

    function api.host_issue_expected(site, expected, actual)
        return H.HostIssueExpected(site, expected, tostring(actual))
    end

    function api.host_issue_arg_count(site, expected, actual)
        return H.HostIssueArgCount(site, expected, actual)
    end

    function api.host_issue_to_string(issue)
        local pvm = require("moonlift.pvm")
        local cls = pvm.classof(issue)
        if cls == H.HostIssueInvalidName then return issue.site .. ": invalid name `" .. issue.name .. "`" end
        if cls == H.HostIssueExpected then return issue.site .. ": expected " .. issue.expected .. ", got " .. issue.actual end
        if cls == H.HostIssueDuplicateField then return "duplicate field in " .. issue.type_name .. ": " .. issue.field_name end
        if cls == H.HostIssueDuplicateType then return "duplicate type in module " .. issue.module_name .. ": " .. issue.type_name end
        if cls == H.HostIssueDuplicateDecl then return "duplicate host declaration: " .. issue.name end
        if cls == H.HostIssueDuplicateFunc then return "duplicate function in module " .. issue.module_name .. ": " .. issue.func_name end
        if cls == H.HostIssueUnsealedType then return "module " .. issue.module_name .. " contains unsealed type " .. issue.type_name end
        if cls == H.HostIssueSealedMutation then return "cannot mutate sealed type " .. issue.type_name end
        if cls == H.HostIssueAlreadySealed then return "type already sealed " .. issue.type_name end
        if cls == H.HostIssueUnknownBinding then return issue.site .. ": unknown binding " .. issue.name end
        if cls == H.HostIssueInvalidEmitFill then return "invalid continuation fill for " .. issue.fragment_name .. ": " .. issue.fill_name end
        if cls == H.HostIssueMissingEmitFill then return "missing continuation fill for " .. issue.fragment_name .. ": " .. issue.fill_name end
        if cls == H.HostIssueInvalidPackedAlign then return "invalid packed alignment for " .. issue.type_name .. ": " .. tostring(issue.align) end
        if cls == H.HostIssueBareBoolInBoundaryStruct then return "bare bool in boundary struct " .. issue.type_name .. "." .. issue.field_name .. " requires explicit bool storage" end
        if cls == H.HostIssueArgCount then return issue.site .. ": expected " .. tostring(issue.expected) .. " args, got " .. tostring(issue.actual) end
        if cls == H.HostIssueSpliceExpected then return "splice " .. issue.splice_id .. ": expected " .. issue.expected .. ", got " .. issue.actual end
        if cls == H.HostIssueSpliceEvalError then return "splice " .. issue.splice_id .. " evaluation failed: " .. issue.message end
        if cls == H.HostIssueLuaStepError then return "Lua host step " .. issue.step_id .. " failed: " .. issue.message end
        if cls == H.HostIssueRegionComposeMissingExit then return "region compose: fragment " .. issue.fragment_name .. " has no exit " .. issue.exit_name end
        if cls == H.HostIssueRegionComposeIncompatibleCont then return "region compose: fragment " .. issue.fragment_name .. "." .. issue.exit_name .. " expected " .. issue.expected .. ", got " .. issue.actual end
        if cls == H.HostIssueRegionComposeIncompleteRoute then return "region compose: missing route for " .. issue.fragment_name .. "." .. issue.exit_name end
        if cls == H.HostIssueRegionComposeContextMismatch then return "region compose: context mismatch between " .. issue.left .. " and " .. issue.right end
        return tostring(issue)
    end

    function api.raise_host_issue(issue)
        if collector then
            collector:emit(issue, "host")
        else
            error(api.host_issue_to_string(issue), 2)
        end
    end

    function api.set_issue_collector(c)
        collector = c
    end

    api.HostIssue = H
end

-----------------------------------------------------------------------------
-- explain_host_issue: explains a single HostIssue
-----------------------------------------------------------------------------

function M.explain_host_issue(issue, analysis)
    local resolvers = require("moonlift.error.span_resolvers")
    local pvm = require("moonlift.pvm")
    local span = resolvers.host_resolver(issue, analysis)
    local cls = pvm.classof(issue)
    if not cls then
        return { code = "E9999", severity = "error", primary = { span = span, message = tostring(issue) } }
    end
    local H = cls
    local kind = cls.kind

    if kind == "HostIssueInvalidName" then
        return { code = "E0504", severity = "error", phase_context = "while checking declarations",
            primary = { span = span, message = issue.site .. ": invalid name `" .. tostring(issue.name) .. "`" } }
    elseif kind == "HostIssueExpected" then
        return { code = "E0301", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = issue.site .. ": expected " .. tostring(issue.expected) .. ", got " .. tostring(issue.actual) } }
    elseif kind == "HostIssueArgCount" then
        return { code = "E0305", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = issue.site .. ": expected " .. tostring(issue.expected) .. " args, got " .. tostring(issue.actual) },
            suggestions = { { message = "check the function signature and adjust the number of arguments" } } }
    elseif kind == "HostIssueDuplicateField" then
        return { code = "E0501", severity = "error", phase_context = "while checking struct declarations",
            primary = { span = span, message = "duplicate field in " .. tostring(issue.type_name) .. ": " .. tostring(issue.field_name) },
            suggestions = { { message = "rename or remove the duplicate field \"" .. tostring(issue.field_name) .. "\"" } } }
    elseif kind == "HostIssueDuplicateType" then
        return { code = "E0502", severity = "error", phase_context = "while checking type declarations",
            primary = { span = span, message = "duplicate type in module " .. tostring(issue.module_name) .. ": " .. tostring(issue.type_name) } }
    elseif kind == "HostIssueDuplicateDecl" then
        return { code = "E0203", severity = "error", phase_context = "while checking declarations",
            primary = { span = span, message = "duplicate host declaration: " .. tostring(issue.name) } }
    elseif kind == "HostIssueDuplicateFunc" then
        return { code = "E0203", severity = "error", phase_context = "while checking declarations",
            primary = { span = span, message = "duplicate function in module " .. tostring(issue.module_name) .. ": " .. tostring(issue.func_name) } }
    elseif kind == "HostIssueUnsealedType" then
        return { code = "E0503", severity = "error", phase_context = "while checking type declarations",
            primary = { span = span, message = "module " .. tostring(issue.module_name) .. " contains unsealed type " .. tostring(issue.type_name) } }
    elseif kind == "HostIssueSealedMutation" then
        return { code = "E0503", severity = "error", phase_context = "while checking type declarations",
            primary = { span = span, message = "cannot mutate sealed type " .. tostring(issue.type_name) } }
    elseif kind == "HostIssueAlreadySealed" then
        return { code = "E0503", severity = "error", phase_context = "while checking type declarations",
            primary = { span = span, message = "type already sealed " .. tostring(issue.type_name) } }
    elseif kind == "HostIssueUnknownBinding" then
        return { code = "E0201", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = issue.site .. ": unknown binding " .. tostring(issue.name) } }
    elseif kind == "HostIssueInvalidEmitFill" then
        return { code = "E0702", severity = "error", phase_context = "while expanding splices",
            primary = { span = span, message = "invalid continuation fill for " .. tostring(issue.fragment_name) .. ": " .. tostring(issue.fill_name) } }
    elseif kind == "HostIssueMissingEmitFill" then
        return { code = "E0702", severity = "error", phase_context = "while expanding splices",
            primary = { span = span, message = "missing continuation fill for " .. tostring(issue.fragment_name) .. ": " .. tostring(issue.fill_name) } }
    elseif kind == "HostIssueInvalidPackedAlign" then
        return { code = "E0506", severity = "error", phase_context = "while checking host layout declarations",
            primary = { span = span, message = "invalid packed alignment for " .. tostring(issue.type_name) .. ": " .. tostring(issue.align) },
            notes = { { message = "packed alignment must be a positive power of two" } },
            suggestions = { { message = "use alignment 1, 2, 4, or 8" } } }
    elseif kind == "HostIssueBareBoolInBoundaryStruct" then
        return { code = "E0505", severity = "error", phase_context = "while checking host boundary declarations",
            primary = { span = span, message = "bare bool in boundary struct " .. tostring(issue.type_name) .. "." .. tostring(issue.field_name) .. " requires explicit bool storage" },
            suggestions = {
                { message = "replace `bool` with `bool8` (byte-backed) or `bool32` (i32-backed) for a stable host ABI" },
            } }
    elseif kind == "HostIssueSpliceExpected" then
        return { code = "E0701", severity = "error", phase_context = "while expanding splices",
            primary = { span = span, message = "splice " .. tostring(issue.splice_id) .. ": expected " .. tostring(issue.expected) .. ", got " .. tostring(issue.actual) } }
    elseif kind == "HostIssueSpliceEvalError" then
        return { code = "E0703", severity = "error", phase_context = "while expanding splices",
            primary = { span = span, message = "splice " .. tostring(issue.splice_id) .. " evaluation failed: " .. tostring(issue.message) } }
    elseif kind == "HostIssueLuaStepError" then
        return { code = "E0703", severity = "error", phase_context = "while evaluating Lua host step",
            primary = { span = span, message = "Lua host step " .. tostring(issue.step_id) .. " failed: " .. tostring(issue.message) } }
    elseif kind == "HostIssueTemplateParseError" then
        return { code = "E0103", severity = "error", phase_context = "while parsing template",
            primary = { span = span, message = tostring(issue.message or "template parse error") } }
    elseif kind == "HostIssueRegionComposeMissingExit" then
        return { code = "E0403", severity = "error", phase_context = "while composing regions",
            primary = { span = span, message = "region compose: fragment `" .. tostring(issue.fragment_name or "?") .. "` has no exit `" .. tostring(issue.exit_name or "?") .. "`" },
            notes = { { message = "the exit `" .. tostring(issue.exit_name or "?") .. "` is not declared by fragment `" .. tostring(issue.fragment_name or "?") .. "`" } } }
    elseif kind == "HostIssueRegionComposeIncompatibleCont" then
        return { code = "E0404", severity = "error", phase_context = "while composing regions",
            primary = { span = span, message = "region compose: fragment `" .. tostring(issue.fragment_name or "?") .. "`.`" .. tostring(issue.exit_name or "?") .. "` expected " .. tostring(issue.expected or "?") .. " but got " .. tostring(issue.actual or "?") },
            notes = { { message = "the continuation parameters do not match between the two fragments" } } }
    elseif kind == "HostIssueRegionComposeIncompleteRoute" then
        return { code = "E0403", severity = "error", phase_context = "while composing regions",
            primary = { span = span, message = "region compose: missing route for `" .. tostring(issue.fragment_name or "?") .. "`.`" .. tostring(issue.exit_name or "?") .. "`" },
            notes = { { message = "all declared exits must be routed to a continuation in the composed region" } } }
    elseif kind == "HostIssueRegionComposeContextMismatch" then
        return { code = "E0405", severity = "error", phase_context = "while composing regions",
            primary = { span = span, message = "region compose: context mismatch between `" .. tostring(issue.left or "?") .. "` and `" .. tostring(issue.right or "?") .. "`" },
            notes = { { message = "the two fragments have incompatible region contexts and cannot be composed" } } }
    else
        return { code = "E9999", severity = "error", primary = { span = span, message = tostring(issue) } }
    end
end

return M
