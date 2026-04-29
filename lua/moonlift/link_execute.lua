local pvm = require("moonlift.pvm")

local M = {}

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", [['"'"']]) .. "'"
end

local function run_capture(argv, env)
    local prefix = {}
    for i = 1, #(env or {}) do
        prefix[#prefix + 1] = tostring(env[i].key) .. "=" .. shell_quote(env[i].value)
    end
    local parts = {}
    for i = 1, #argv do parts[#parts + 1] = shell_quote(argv[i]) end
    local command = (#prefix > 0 and (table.concat(prefix, " ") .. " ") or "") .. table.concat(parts, " ")
    local pipe, err = io.popen(command .. " 2>&1", "r")
    if pipe == nil then return false, -1, err or "could not start command" end
    local out = pipe:read("*a")
    local ok, why, code = pipe:close()
    if ok == true or ok == 0 then return true, 0, out end
    return false, tonumber(code) or 1, out ~= "" and out or tostring(why or "command failed")
end

function M.Define(T)
    local Link = T.Moon2Link
    assert(Link, "moonlift.link_execute.Define expects moonlift.asdl in the context")

    local function execute(plan)
        for i = 1, #plan.commands do
            local cmd = plan.commands[i]
            local cls = pvm.classof(cmd)
            if cls == Link.LinkCmdWriteFile then
                local f, err = io.open(cmd.path.text, "wb")
                if not f then return Link.LinkFailed(Link.LinkReport({ Link.LinkIssueCommandFailed(i, 1, err or "write failed") })) end
                f:write(cmd.contents)
                f:close()
            elseif cls == Link.LinkCmdRemoveFile then
                os.remove(cmd.path.text)
            elseif cls == Link.LinkCmdRun then
                local argv = { cmd.tool.path.text }
                for j = 1, #cmd.args do argv[#argv + 1] = cmd.args[j] end
                local ok, code, stderr = run_capture(argv, cmd.env)
                if not ok then return Link.LinkFailed(Link.LinkReport({ Link.LinkIssueCommandFailed(i, code, stderr) })) end
            end
        end
        return Link.LinkOk(plan.plan.output)
    end

    local phase = pvm.phase("moon2_link_execute", {
        [Link.LinkCommandPlan] = function(self) return pvm.once(execute(self)) end,
    })

    return {
        phase = phase,
        execute = execute,
    }
end

return M
