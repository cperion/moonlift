-- Import legacy ASDL parser text into canonical MoonAsdl.Schema values.
--
-- This is a migration bridge, not the desired long-term authoring surface.  It
-- lets us run the existing Moonlift schema through the new schema-as-data path
-- while clean builder-authored Moon* modules are introduced.

local Parser = require("moonlift.asdl_parser")
local Model = require("moonlift.asdl_model")

local M = {}

local BUILTINS = { string = true, number = true, boolean = true }

local function split_qualified(name)
    local module_name, local_name = name:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
    return module_name, local_name
end

local function strip_prefix(text, prefix)
    if text:sub(1, #prefix) == prefix then return text:sub(#prefix + 1) end
    return text
end

local function type_expr(A, text)
    if BUILTINS[text] then return A.TypeBuiltin(text) end
    local module_name, local_name = split_qualified(text)
    if module_name ~= nil then return A.TypeName(module_name, local_name) end
    return A.TypeRelativeName(text)
end

local function field_value(A, field)
    local card = A.FieldOne
    if field.list then card = A.FieldMany elseif field.optional then card = A.FieldOptional end
    return A.Field(field.name, type_expr(A, field.type), card)
end

local function fields(A, xs)
    local out = {}
    for i = 1, #(xs or {}) do out[#out + 1] = field_value(A, xs[i]) end
    return out
end

local function decl_attrs(A, parsed)
    local attrs = {}
    if parsed.unique then attrs[#attrs + 1] = A.DeclUnique end
    return attrs
end

local function variant_attrs(A, parsed)
    local attrs = {}
    if parsed.unique then attrs[#attrs + 1] = A.VariantUnique end
    return attrs
end

local function module_slot(slots, order, module_name)
    local slot = slots[module_name]
    if slot == nil then
        slot = { name = module_name, decls = {} }
        slots[module_name] = slot
        order[#order + 1] = slot
    end
    return slot
end

function M.import(T, text)
    Model.Define(T)
    local A = T.MoonAsdl
    local defs = Parser.parse(text)
    local slots, order = {}, {}

    for i = 1, #defs do
        local def = defs[i]
        local module_name, local_name = split_qualified(def.name)
        if module_name == nil then error("asdl_legacy_import: definition is not module-qualified: " .. tostring(def.name), 2) end
        local slot = module_slot(slots, order, module_name)
        local typ = def.type
        if typ.kind == "product" then
            slot.decls[#slot.decls + 1] = A.ProductDecl(local_name, fields(A, typ.fields), decl_attrs(A, typ))
        elseif typ.kind == "sum" then
            local variants = {}
            local prefix = module_name .. "."
            for j = 1, #typ.constructors do
                local ctor = typ.constructors[j]
                variants[#variants + 1] = A.Variant(strip_prefix(ctor.name, prefix), fields(A, ctor.fields), variant_attrs(A, ctor))
            end
            slot.decls[#slot.decls + 1] = A.SumDecl(local_name, variants, decl_attrs(A, typ))
        else
            error("asdl_legacy_import: unsupported parsed type kind " .. tostring(typ.kind), 2)
        end
    end

    local modules = {}
    for i = 1, #order do
        local slot = order[i]
        modules[#modules + 1] = A.Module(slot.name, slot.decls, {})
    end
    return A.Schema(modules)
end

return M
