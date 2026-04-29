local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")

local M = {}
local Session = {}
Session.__index = Session

function M.new(opts)
    opts = opts or {}
    local T = pvm.context()
    A2.Define(T)
    return setmetatable({
        T = T,
        prefix = opts.prefix or "host",
        next_id = 0,
        _api = nil,
    }, Session)
end

function Session:symbol_key(kind, name)
    self.next_id = self.next_id + 1
    return table.concat({ self.prefix, kind, tostring(self.next_id), tostring(name) }, ":")
end

function Session:type_sym(name)
    local C = self.T.MoonCore
    return C.TypeSym(self:symbol_key("type", name), name)
end

function Session:id(kind, name)
    local C = self.T.MoonCore
    return C.Id(self:symbol_key(kind or "id", name))
end

function Session:api()
    if self._api then return self._api end
    local api = { session = self, T = self.T }
    require("moonlift.host_issue_values").Install(api, self)
    require("moonlift.host_type_values").Install(api, self)
    require("moonlift.host_expr_values").Install(api, self)
    require("moonlift.host_place_values").Install(api, self)
    require("moonlift.host_fragment_values").Install(api, self)
    require("moonlift.host_struct_values").Install(api, self)
    require("moonlift.host_decl_values").Install(api, self)
    require("moonlift.host_template_values").Install(api, self)
    require("moonlift.host_func_values").Install(api, self)
    require("moonlift.host_region_values").Install(api, self)
    require("moonlift.host_module_values").Install(api, self)
    self._api = api
    return api
end

function Session:classify_type(ty_value)
    local api = self:api()
    local ty = api.as_moon2_type(ty_value, "classify_type expects type value")
    return require("moonlift.type_classify").Define(self.T).classify(ty)
end

function Session:size_align(ty_value, env)
    local api = self:api()
    local ty = api.as_moon2_type(ty_value, "size_align expects type value")
    return require("moonlift.type_size_align").Define(self.T).result(ty, env)
end

function Session:abi_of(ty_value, env)
    local api = self:api()
    local ty = api.as_moon2_type(ty_value, "abi_of expects type value")
    return require("moonlift.type_abi_classify").Define(self.T).decide(ty, env)
end

function Session:layout_of(type_value)
    local pvm = require("moonlift.pvm")
    local api = self:api()
    local Sem = self.T.MoonSem
    local tv
    if type(type_value) == "table" and type(type_value.as_type_value) == "function" then tv = type_value:as_type_value() else tv = api.as_type_value(type_value, "layout_of expects type value") end
    local fields = type_value.fields or tv.fields
    local fields_by_name = type_value.fields_by_name or tv.fields_by_name
    if fields == nil and fields_by_name == nil then return nil end
    local offset = 0
    local align = 1
    local layouts = {}
    if fields ~= nil then
        for i = 1, #fields do
            local f = fields[i]
            local r = self:size_align(f.type)
            if pvm.classof(r) ~= self.T.MoonType.TypeMemLayoutKnown then return nil end
            local a = r.layout.align
            if a > align then align = a end
            local rem = offset % a
            if rem ~= 0 then offset = offset + (a - rem) end
            layouts[#layouts + 1] = Sem.FieldLayout(f.name, offset, f.type.ty)
            offset = offset + r.layout.size
        end
    end
    local rem = offset % align
    if rem ~= 0 then offset = offset + (align - rem) end
    return Sem.LayoutNamed(type_value.owner_module and type_value.owner_module.name or "", type_value.name or tv.source_hint, layouts, offset, align)
end

M.Session = Session
return M
