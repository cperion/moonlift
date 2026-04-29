-- Lower MoonAsdl.Schema to hosted Moonlift module/type values.
--
-- This is schema metaprogramming, not source-text emission: products become
-- module-owned structs and sums become module-owned tagged unions through the
-- existing hosted value API.

local pvm = require("moonlift.pvm")
local AsdlModel = require("moonlift.asdl_model")

local M = {}

local function sanitize(name)
    return tostring(name):gsub("[^%w_]", "_")
end

local function qname(module_name, name)
    return sanitize(module_name) .. "_" .. sanitize(name)
end

local function ensure_string_id(api, module)
    if module.type_names.StringId then return api.path_named("StringId") end
    return module:struct("StringId", { api.field("index", api.index) }).type
end

local Lower = {}
Lower.__index = Lower

function Lower:type_value(current_module, ty)
    local A = self.A
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then
        if ty.name == "boolean" then return self.api.bool end
        if ty.name == "number" then return self.api.i64 end
        if ty.name == "string" then return ensure_string_id(self.api, self.module) end
        return assert(self.api[ty.name], "unsupported builtin type for hosted schema lowering: " .. tostring(ty.name))
    end
    if cls == A.TypeRelativeName then return self.api.path_named(qname(current_module, ty.name) .. "Id") end
    if cls == A.TypeName then return self.api.path_named(qname(ty.module_name, ty.name) .. "Id") end
    if cls == A.TypeList then return self.api.path_named(self:type_source(current_module, ty.elem) .. "Range") end
    if cls == A.TypeOptional then return self.api.path_named("Optional" .. self:type_source(current_module, ty.elem)) end
    error("unsupported MoonAsdl.TypeExpr", 2)
end

function Lower:type_source(current_module, ty)
    local A = self.A
    local cls = pvm.classof(ty)
    if cls == A.TypeBuiltin then
        if ty.name == "string" then return "StringId" end
        if ty.name == "number" then return "i64" end
        if ty.name == "boolean" then return "bool" end
        return ty.name
    end
    if cls == A.TypeRelativeName then return qname(current_module, ty.name) end
    if cls == A.TypeName then return qname(ty.module_name, ty.name) end
    if cls == A.TypeList then return self:type_source(current_module, ty.elem) .. "Range" end
    if cls == A.TypeOptional then return "Optional" .. self:type_source(current_module, ty.elem) end
    error("unsupported MoonAsdl.TypeExpr", 2)
end

function Lower:field(current_module, f)
    return self.api.field(f.name, self:type_value(current_module, f.ty))
end

function Lower:emit_id_and_arena(name)
    if self.module.type_names[name .. "Id"] == nil then
        self.module:struct(name .. "Id", { self.api.field("index", self.api.index) })
    end
    if self.module.type_names[name .. "Arena"] == nil then
        self.module:struct(name .. "Arena", {
            self.api.field("values", self.api.ptr(self.api.path_named(name))),
            self.api.field("len", self.api.index),
        })
    end
end

function Lower:product(module_name, decl)
    local name = qname(module_name, decl.name)
    self:emit_id_and_arena(name)
    local fields = {}
    for i = 1, #decl.fields do fields[i] = self:field(module_name, decl.fields[i]) end
    self.module:struct(name, fields)
end

function Lower:sum(module_name, decl)
    local name = qname(module_name, decl.name)
    local variants = {}
    for i = 1, #decl.variants do
        local v = decl.variants[i]
        local payload = self.api.void
        if #v.fields == 1 then
            payload = self:type_value(module_name, v.fields[1].ty)
        elseif #v.fields > 1 then
            local payload_name = qname(module_name, decl.name .. "_" .. v.name .. "Payload")
            local fields = {}
            for j = 1, #v.fields do fields[j] = self:field(module_name, v.fields[j]) end
            payload = self.module:struct(payload_name, fields).type
        end
        variants[i] = self.api.variant(v.name, payload)
    end
    self:emit_id_and_arena(name)
    self.module:tagged_union(name, variants)
end

function M.lower_schema(api, schema, opts)
    opts = opts or {}
    AsdlModel.Define(api.T)
    local A = api.T.MoonAsdl
    assert(pvm.classof(schema) == A.Schema, "lower_schema expects MoonAsdl.Schema")
    local module = api.module(opts.module_name or "NativePvmSchema")
    local self = setmetatable({ api = api, A = A, module = module }, Lower)
    for i = 1, #schema.modules do
        local m = schema.modules[i]
        for j = 1, #m.decls do
            local decl = m.decls[j]
            local cls = pvm.classof(decl)
            if cls == A.ProductDecl then self:product(m.name, decl)
            elseif cls == A.SumDecl then self:sum(m.name, decl) end
        end
    end
    return module
end

function M.Define(T)
    AsdlModel.Define(T)
    return { lower_schema = M.lower_schema }
end

return M
