local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Link = T.MoonLink
    assert(Link, "moonlift.link_plan_validate.Define expects moonlift.asdl in the context")

    local function input_path(input)
        local cls = pvm.classof(input)
        if cls == Link.LinkInputObject or cls == Link.LinkInputStaticArchive or cls == Link.LinkInputSharedLibrary or cls == Link.LinkInputLibrarySearchPath or cls == Link.LinkInputLinkerScript then
            return input.path
        end
        return nil
    end

    local function validate(plan)
        local issues = {}
        if plan.output.text == "" then issues[#issues + 1] = Link.LinkIssueMissingOutput end
        if #plan.inputs == 0 then issues[#issues + 1] = Link.LinkIssueNoInputs end
        for i = 1, #plan.inputs do
            local path = input_path(plan.inputs[i])
            if path ~= nil and path.text ~= "" then
                local f = io.open(path.text, "rb")
                if f then f:close() else issues[#issues + 1] = Link.LinkIssueMissingInput(path) end
            end
            if pvm.classof(plan.inputs[i]) == Link.LinkInputFramework and plan.target.platform ~= Link.LinkPlatformMacOS then
                issues[#issues + 1] = Link.LinkIssueUnsupportedInput(plan.inputs[i], "framework inputs are macOS-only")
            end
        end
        return Link.LinkReport(issues)
    end

    local phase = pvm.phase("moonlift_link_plan_validate", {
        [Link.LinkPlan] = function(self) return pvm.once(validate(self)) end,
    })

    return {
        phase = phase,
        validate = validate,
    }
end

-----------------------------------------------------------------------------
-- explain_link_issue: explains a single LinkIssue
-----------------------------------------------------------------------------

function M.explain_link_issue(issue, analysis)
    local pvm = require("moonlift.pvm")
    local cls = pvm.classof(issue)
    if not cls then return { code = "E9999", severity = "error", primary = { span = nil, message = tostring(issue) } } end
    local kind = cls.kind

    if kind == "LinkIssueMissingOutput" then
        return { code = "E0901", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "link plan has no output path" } }
    elseif kind == "LinkIssueNoInputs" then
        return { code = "E0901", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "link plan has no input files" } }
    elseif kind == "LinkIssueMissingInput" then
        local path = issue.path and issue.path.text or "?"
        return { code = "E0901", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "missing input file `" .. path .. "`" } }
    elseif kind == "LinkIssueUnsupportedPlatform" then
        return { code = "E0902", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "unsupported platform for this link target" } }
    elseif kind == "LinkIssueUnsupportedInput" then
        return { code = "E0902", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "unsupported input: " .. tostring(issue.reason or "?") } }
    elseif kind == "LinkIssueUnsupportedOption" then
        return { code = "E0902", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "unsupported link option: " .. tostring(issue.reason or "?") } }
    elseif kind == "LinkIssueUnresolvedSymbol" then
        local sym = issue.symbol and issue.symbol.name or "?"
        return { code = "E0903", severity = "error", phase_context = "while checking link plan",
            primary = { span = nil, message = "unresolved symbol `" .. sym .. "`" },
            notes = { { message = "ensure the object file defining `" .. sym .. "` is included in the link plan" } } }
    elseif kind == "LinkIssueDuplicateSymbol" then
        local sym = issue.symbol and issue.symbol.name or "?"
        return { code = "E0203", severity = "error", phase_context = "while checking link plan",
            primary = { span = nil, message = "duplicate symbol `" .. sym .. "`" },
            notes = { { message = "the symbol `" .. sym .. "` is defined in multiple input files" } } }
    elseif kind == "LinkIssueToolUnavailable" then
        local tool_name = issue.tool and (issue.tool.text or tostring(issue.tool)) or "linker"
        return { code = "E0904", severity = "error", phase_context = "while checking link plan",
            primary = { span = nil, message = "linker tool `" .. tool_name .. "` is not available" },
            notes = { { message = "ensure " .. tool_name .. " is installed and on the system PATH" } } }
    elseif kind == "LinkIssueCommandFailed" then
        return { code = "E0905", severity = "error", phase_context = "while checking link plan", primary = { span = nil, message = "linker command failed (exit " .. tostring(issue.code or "?") .. ")" },
            notes = { { message = "stderr: " .. tostring(issue.stderr or "") } } }
    else
        return { code = "E9999", severity = "error", primary = { span = nil, message = kind or tostring(issue) } }
    end
end

return M
