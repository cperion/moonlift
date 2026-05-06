-- Explicit hosted Lua evaluation phase.
--
-- This is intentionally small: execute Lua opaque steps and evaluate splice
-- expressions.  Role-compatibility checking has moved to host_splice.lua —
-- the parser-assigned slot kind is now the authoritative role, so there is
-- no expectation to check here.

local pvm = require("moonlift.pvm")

local M = {}

local function ensure_env(session)
    if session._host_eval_env then return session._host_eval_env end
    local env = { __moonlift_host = session:api(), moon = session:api(), moonlift = session:api() }
    setmetatable(env, { __index = _G })
    session._host_eval_env = env
    return env
end

local function eval_chunk(src, env, chunkname)
    local fn, err = loadstring(src, chunkname)
    if not fn then return false, err end
    setfenv(fn, env)
    return pcall(fn)
end

local function eval_expr(src, env, chunkname)
    local fn, err = loadstring("return (" .. src .. ")", chunkname)
    if not fn then
        fn, err = loadstring("return " .. src, chunkname)
    end
    if not fn then return false, err end
    setfenv(fn, env)
    return pcall(fn)
end

local function eval_template(T, session, template, env)
    local H = T.MoonHost
    local splices, issues = {}, {}
    for i = 1, #template.parts do
        local part = template.parts[i]
        if pvm.classof(part) == H.TemplateSplicePart then
            local splice = part.splice
            local ok, value_or_err = eval_expr(splice.lua_source.text, env, "=(moonlift.splice." .. splice.id .. ")")
            if not ok then
                issues[#issues + 1] = H.HostIssueSpliceEvalError(splice.id, tostring(value_or_err))
            else
                splices[#splices + 1] = H.HostSpliceResult(
                    splice.id,
                    require("moonlift.host_values").value_ref(session, value_or_err, splice.id))
            end
        end
    end
    return H.HostEvaluatedTemplate(template, splices, issues)
end

function M.Define(T)
    local H = T.MoonHost

    local eval = pvm.phase("moonlift_host_eval", function(program, session)
        local env = ensure_env(session)
        local templates, issues = {}, {}
        for i = 1, #program.steps do
            local step = program.steps[i]
            local cls = pvm.classof(step)
            if cls == H.HostStepLua then
                local ok, err = eval_chunk(step.source.text, env, "=(moonlift.host." .. step.id .. ")")
                if not ok then issues[#issues + 1] = H.HostIssueLuaStepError(step.id, tostring(err)) end
            elseif cls == H.HostStepIsland then
                local evaluated = eval_template(T, session, step.template, env)
                templates[#templates + 1] = evaluated
                for j = 1, #evaluated.issues do issues[#issues + 1] = evaluated.issues[j] end
            end
        end
        return H.HostEvalResult(program, templates, H.HostReport(issues))
    end, { args_cache = "none" })

    return {
        eval = eval,
        eval_template = function(session, template, env)
            return eval_template(T, session, template, env or ensure_env(session))
        end,
        ensure_env = function(session) return ensure_env(session) end,
    }
end

return M
