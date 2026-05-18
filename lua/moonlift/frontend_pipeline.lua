local pvm = require("moonlift.pvm")

local M = {}

local function issue_text(issue)
    if type(issue) == "table" and issue.message ~= nil then return tostring(issue.message) end
    return tostring(issue)
end

local function issue_list_text(issues)
    local msgs = {}
    for i = 1, #(issues or {}) do msgs[#msgs + 1] = issue_text(issues[i]) end
    return table.concat(msgs, "\n")
end

local function assert_no_issues(site, phase, issues)
    if #(issues or {}) ~= 0 then
        error(tostring(site or "frontend") .. " " .. phase .. " failed: " .. issue_list_text(issues), 3)
    end
end

local function assert_no_cmd_trap(T, program, site)
    local Back = T.MoonBack
    for i = 1, #(program and program.cmds or {}) do
        local cmd = program.cmds[i]
        if cmd == Back.CmdTrap or pvm.classof(cmd) == Back.CmdTrap or cmd.kind == "CmdTrap" then
            error((site or "frontend lowering") .. " produced CmdTrap at command #" .. tostring(i)
                .. "; unsupported lowering must fail before native code emission", 3)
        end
    end
end

function M.Define(T)
    local Parse = require("moonlift.parse").Define(T)
    local OpenFacts = require("moonlift.open_facts").Define(T)
    local OpenValidate = require("moonlift.open_validate").Define(T)
    local OpenExpand = require("moonlift.open_expand").Define(T)
    local ClosureConvert = require("moonlift.closure_convert").Define(T)
    local Typecheck = require("moonlift.tree_typecheck").Define(T)
    local Layout = require("moonlift.sem_layout_resolve").Define(T)
    local Lower = require("moonlift.tree_to_back").Define(T)
    local Validate = require("moonlift.back_validate").Define(T)

    local function lower_module(module, opts)
        opts = opts or {}
        local site = opts.site or "frontend"

        local expanded = OpenExpand.module(module)
        local open_report = OpenValidate.validate(OpenFacts.facts_of_module(expanded))
        assert_no_issues(site, "open validation", open_report.issues)

        local closed = ClosureConvert.module(expanded)
        local checked = Typecheck.check_module(closed)
        assert_no_issues(site, "typecheck", checked.issues)

        local resolved = Layout.module(checked.module, opts.layout_env)
        local program = Lower.module(resolved)
        if program == nil then error(site .. " lowering failed: tree_to_back produced nil program", 2) end
        assert_no_cmd_trap(T, program, site)

        local back_report = Validate.validate(program)
        assert_no_issues(site, "back validation", back_report.issues)

        return {
            expanded = expanded,
            open_report = open_report,
            closed = closed,
            checked = checked,
            resolved = resolved,
            program = program,
            back_report = back_report,
        }
    end

    local function parse_and_lower(src, opts)
        opts = opts or {}
        local site = opts.site or "frontend"
        local parsed = Parse.parse_module(src, opts.parse_opts)
        assert_no_issues(site, "parse", parsed.issues)
        local result = lower_module(parsed.module, opts)
        result.parsed = parsed
        return result
    end

    return {
        lower_module = lower_module,
        parse_and_lower = parse_and_lower,
        assert_no_cmd_trap = function(program, site) return assert_no_cmd_trap(T, program, site) end,
        issue_list_text = issue_list_text,
    }
end

return M
