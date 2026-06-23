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

local function bind_context(T)
    local Link = T.MoonLink
    assert(Link, "moonlift.link_execute(T) expects moonlift.schema_projection in the context")

    local function execute(plan)
        for i = 1, #plan.commands do
            local cmd = plan.commands[i]
            local cls = schema.classof(cmd)
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

    local function phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Link.LinkCommandPlan) then
            return (function(self)
 return single(execute(self))
            end)(node, ...)
        else
            error("phase moonlift_link_execute: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        phase = phase,
        execute = execute,
    }
end

return bind_context