-- Evaluated host-template to ASDL parser bridge.
--
-- Final architecture target: parser-with-typed-holes.  This module is the
-- choke-point for that lowering.  Today it renders evaluated templates through
-- typed HostValueRefs and immediately parses to ASDL, keeping source rendering
-- contained at this boundary.

local pvm = require("moonlift.pvm")

local M = {}

local function splice_map(evaluated)
    local out = {}
    for i = 1, #evaluated.splices do out[evaluated.splices[i].splice_id] = evaluated.splices[i] end
    return out
end

local function splice_source(session, splice_result)
    local value = session:lookup_host_value(splice_result.value.id)
    if value == nil then error("missing host value for splice " .. splice_result.splice_id, 2) end
    local tv = type(value)
    if tv == "number" or tv == "boolean" then return tostring(value) end
    if tv == "nil" then return "nil" end
    if tv == "string" then return value end
    if (tv == "table" or tv == "userdata") and type(value.moonlift_splice_source) == "function" then
        return value:moonlift_splice_source()
    end
    return tostring(value)
end

function M.render(session, evaluated)
    local H = session.T.MoonHost
    local by_id = splice_map(evaluated)
    local out = {}
    for i = 1, #evaluated.template.parts do
        local part = evaluated.template.parts[i]
        local cls = pvm.classof(part)
        if cls == H.TemplateText then
            out[#out + 1] = part.text.source.text
        elseif cls == H.TemplateSplicePart then
            out[#out + 1] = splice_source(session, assert(by_id[part.splice.id], "unresolved splice " .. part.splice.id))
        end
    end
    return table.concat(out)
end

function M.Define(T)
    local H = T.MoonHost
    local Parse = require("moonlift.parse").Define(T)
    local HostValues = require("moonlift.host_values")

    local parse_template = pvm.phase("moonlift_host_template_parse", function(evaluated, session, env)
        env = env or {}
        if #evaluated.issues ~= 0 then
            return H.HostTemplateParseResult and H.HostTemplateParseResult(evaluated, nil, evaluated.issues) or evaluated
        end
        local text = M.render(session, evaluated)
        if evaluated.template.kind_word == "region" then
            local parsed = Parse.parse_region_frag(text, env)
            if #parsed.issues == 0 and parsed.value and parsed.value.frag then
                return HostValues.region_frag_value(session, parsed.value.frag, { deps = parsed.value.deps })
            end
            return parsed
        elseif evaluated.template.kind_word == "expr" then
            local parsed = Parse.parse_expr_frag(text, env)
            if #parsed.issues == 0 and parsed.value and parsed.value.frag then
                return HostValues.expr_frag_value(session, parsed.value.frag)
            end
            return parsed
        elseif evaluated.template.kind_word == "module" then
            return Parse.parse_module(text, env)
        end
        return text
    end, { args_cache = "none" })

    return {
        parse_template = parse_template,
        render = M.render,
    }
end

return M
