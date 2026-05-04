local M = {}

function M.Install(api, session)
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
        if cls == H.HostIssueTemplateParseError then return "host template " .. issue.template_id .. " parse failed: " .. issue.message end
        if cls == H.HostIssueRegionComposeMissingExit then return "region compose: fragment " .. issue.fragment_name .. " has no exit " .. issue.exit_name end
        if cls == H.HostIssueRegionComposeIncompatibleCont then return "region compose: fragment " .. issue.fragment_name .. "." .. issue.exit_name .. " expected " .. issue.expected .. ", got " .. issue.actual end
        if cls == H.HostIssueRegionComposeIncompleteRoute then return "region compose: missing route for " .. issue.fragment_name .. "." .. issue.exit_name end
        if cls == H.HostIssueRegionComposeContextMismatch then return "region compose: context mismatch between " .. issue.left .. " and " .. issue.right end
        return tostring(issue)
    end

    function api.raise_host_issue(issue)
        error(api.host_issue_to_string(issue), 2)
    end

    api.HostIssue = H
end

return M
