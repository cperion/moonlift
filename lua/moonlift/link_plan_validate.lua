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

    local phase = pvm.phase("moon2_link_plan_validate", {
        [Link.LinkPlan] = function(self) return pvm.once(validate(self)) end,
    })

    return {
        phase = phase,
        validate = validate,
    }
end

return M
