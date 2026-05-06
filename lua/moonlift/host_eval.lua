-- Explicit hosted Lua evaluation phase.
--
-- This is intentionally small: it models Lua evaluation as a PVM boundary and
-- records typed HostValueRefs for template splices.  It does not parse template
-- text; that belongs to host_template_parse.

local pvm = require("moonlift.pvm")

local M = {}

local function expectation_name(T, e)
    local H = T.MoonHost
    if e == H.SpliceAny then return "any" end
    if e == H.SpliceExpr then return "expr" end
    if e == H.SpliceType then return "type" end
    if e == H.SpliceEmit then return "emit" end
    if e == H.SpliceRegionFrag then return "region_frag" end
    if e == H.SpliceExprFrag then return "expr_frag" end
    if e == H.SpliceSource then return "source" end
    return tostring(e)
end

local function value_kind_name(session, value)
    local tv = type(value)
    if tv == "number" or tv == "boolean" or tv == "nil" then return "expr" end
    -- Strings render as raw Moonlift source/name fragments.
    if tv == "string" then return "source" end
    local ref = require("moonlift.host_values").value_ref(session, value, "classify")
    local H = session.T.MoonHost
    if ref.kind == H.HostValueRegionFrag then return "region_frag" end
    if ref.kind == H.HostValueExprFrag then return "expr_frag" end
    if ref.kind == H.HostValueType then return "type" end
    if tv == "table" then
        local mt = getmetatable(value)
        if type(value.as_type_value) == "function" or (mt and mt.__moonlift_host_type_value == true) then return "type" end
    end
    if ref.kind == H.HostValueDecl then return "decl" end
    if ref.kind == H.HostValueModule then return "module" end
    if ref.kind == H.HostValueSource then return "source" end
    if (tv == "table" or tv == "userdata") and type(value.moonlift_splice_source) == "function" then return "source" end
    return "lua"
end

local function expectation_accepts(T, expected, actual)
    local H = T.MoonHost
    if expected == H.SpliceAny then return true end
    if expected == H.SpliceExpr then return actual == "expr" or actual == "source" end
    if expected == H.SpliceType then return actual == "type" or actual == "source" end
    if expected == H.SpliceEmit then return actual == "region_frag" or actual == "expr_frag" or actual == "source" end
    if expected == H.SpliceRegionFrag then return actual == "region_frag" end
    if expected == H.SpliceExprFrag then return actual == "expr_frag" end
    if expected == H.SpliceSource then return actual == "source" end
    return false
end

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
                local actual = value_kind_name(session, value_or_err)
                if not expectation_accepts(T, splice.expected, actual) then
                    issues[#issues + 1] = H.HostIssueSpliceExpected(splice.id, expectation_name(T, splice.expected), actual)
                else
                    splices[#splices + 1] = H.HostSpliceResult(splice.id, splice.expected, require("moonlift.host_values").value_ref(session, value_or_err, splice.id))
                end
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
        eval_template = function(session, template, env) return eval_template(T, session, template, env or ensure_env(session)) end,
    }
end

return M
