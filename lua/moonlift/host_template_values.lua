local M = {}

local StructTemplateValue = {}
StructTemplateValue.__index = StructTemplateValue

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

local function sanitize(s)
    s = tostring(s):gsub("[^_%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if s == "" then return "T" end
    return s
end

function StructTemplateValue:instantiate(module_value, args)
    args = args or {}
    if #args ~= #self.params then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueArgCount("struct template " .. self.name, #self.params, #args)) end
    local concrete = {}
    local suffix = {}
    local fills = {}
    local O = self.session.T.MoonOpen
    for i = 1, #args do
        concrete[i] = self.api.as_type_value(args[i], "struct template arg must be a type value")
        suffix[i] = sanitize(concrete[i].source_hint)
        fills[i] = O.SlotBinding(O.SlotType(self.params[i].type_slot), O.SlotValueType(concrete[i].ty))
    end
    local env = O.ExpandEnv(O.FillSet(fills), {}, "")
    local expand = require("moonlift.open_expand").Define(self.session.T)
    local fields = {}
    for i = 1, #self.open_fields do
        fields[i] = self.api.field(self.open_fields[i].name, self.api.type_from_asdl(expand.type(self.open_fields[i].type.ty, env), self.open_fields[i].type.source_hint))
    end
    local name = self.name .. "_" .. table.concat(suffix, "_")
    return module_value:struct(name, fields)
end

function StructTemplateValue:__tostring()
    return "Moon2StructTemplateValue(" .. self.name .. ")"
end

function M.Install(api, session)
    local T = session.T
    local O, Ty = T.MoonOpen, T.MoonType

    function api.type_param(name)
        assert_name(name, "type_param")
        local slot = O.TypeSlot(session:symbol_key("type_param", name), name)
        return api.type_from_asdl(Ty.TSlot(slot), name, { type_slot = slot })
    end

    function api.struct_template(name, params, body_fn)
        assert_name(name, "struct_template")
        assert(type(params) == "table", "struct_template params must be an ordered list")
        assert(type(body_fn) == "function", "struct_template expects a body function")
        for i = 1, #params do
            local p = api.as_type_value(params[i], "struct_template param must be a type value")
            assert(p.type_slot ~= nil, "struct_template params must be type_param values")
        end
        local open_fields = body_fn(unpack(params))
        assert(type(open_fields) == "table", "struct_template body must return an ordered field list")
        for i = 1, #open_fields do
            assert(type(open_fields[i]) == "table" and getmetatable(open_fields[i]) == api.FieldValue, "struct_template body must return field values")
        end
        return setmetatable({ kind = "struct_template", session = session, api = api, name = name, params = params, open_fields = open_fields }, StructTemplateValue)
    end

    function api._module_instantiate(module_value, template, args)
        assert(type(template) == "table" and getmetatable(template) == StructTemplateValue, "instantiate expects a struct template value")
        return template:instantiate(module_value, args)
    end

    api.StructTemplateValue = StructTemplateValue
end

return M
