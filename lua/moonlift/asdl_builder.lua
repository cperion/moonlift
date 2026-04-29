-- Lua-hosted builder syntax for canonical MoonAsdl schema values.
--
-- The builder tables/functions are syntax only.  Every public constructor below
-- returns MoonAsdl ASDL values from the supplied context.

local Model = require("moonlift.asdl_model")
local pvm = require("moonlift.pvm")

local M = {}

local BUILTINS = { string = true, number = true, boolean = true }

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        if k > n then n = k end
    end
    return n == #t
end

function M.Define(T)
    Model.Define(T)
    local A = T.MoonAsdl
    local B = {}

    local function type_expr(spec)
        if type(spec) == "table" then
            local cls = pvm.classof(spec)
            if cls == A.TypeBuiltin or cls == A.TypeName or cls == A.TypeRelativeName or cls == A.TypeList or cls == A.TypeOptional then
                return spec
            end
        end
        if type(spec) ~= "string" then
            error("asdl_builder: type expression must be a string or MoonAsdl.TypeExpr", 3)
        end
        if BUILTINS[spec] then return A.TypeBuiltin(spec) end
        local module_name, name = spec:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
        if module_name ~= nil then return A.TypeName(module_name, name) end
        return A.TypeRelativeName(spec)
    end

    local function split_decl_entries(entries)
        local fields, attrs = {}, {}
        for i = 1, #(entries or {}) do
            local item = entries[i]
            local cls = pvm.classof(item)
            if cls == A.Field then fields[#fields + 1] = item
            elseif item == A.DeclUnique or cls == A.DeclDoc then attrs[#attrs + 1] = item
            else error("asdl_builder: unexpected product entry " .. tostring(item), 3) end
        end
        return fields, attrs
    end

    local function split_variant_entries(entries)
        local fields, attrs = {}, {}
        for i = 1, #(entries or {}) do
            local item = entries[i]
            local cls = pvm.classof(item)
            if cls == A.Field then fields[#fields + 1] = item
            elseif item == A.VariantUnique or cls == A.VariantDoc then attrs[#attrs + 1] = item
            else error("asdl_builder: unexpected variant entry " .. tostring(item), 3) end
        end
        return fields, attrs
    end

    local function split_module_entries(entries)
        local decls, attrs = {}, {}
        for i = 1, #(entries or {}) do
            local item = entries[i]
            local cls = pvm.classof(item)
            if cls == A.SumDecl or cls == A.ProductDecl or cls == A.AliasDecl then decls[#decls + 1] = item
            elseif cls == A.ModuleDoc then attrs[#attrs + 1] = item
            else error("asdl_builder: unexpected module entry " .. tostring(item), 3) end
        end
        return decls, attrs
    end

    local function split_schema_entries(entries)
        local modules = {}
        for i = 1, #(entries or {}) do
            local item = entries[i]
            local cls = pvm.classof(item)
            if cls == A.Schema then
                for j = 1, #item.modules do modules[#modules + 1] = item.modules[j] end
            elseif cls == A.Module then
                modules[#modules + 1] = item
            else
                error("asdl_builder: expected module or schema entry", 3)
            end
        end
        return modules
    end

    function B.schema(entries)
        if not is_array(entries) then error("asdl_builder.schema expects an array table", 2) end
        return A.Schema(split_schema_entries(entries))
    end

    function B.module(name)
        return function(entries)
            if not is_array(entries) then error("asdl_builder.module expects an array table", 2) end
            local decls, attrs = split_module_entries(entries)
            return A.Module(name, decls, attrs)
        end
    end

    function B.product(name)
        return function(entries)
            if not is_array(entries) then error("asdl_builder.product expects an array table", 2) end
            local fields, attrs = split_decl_entries(entries)
            return A.ProductDecl(name, fields, attrs)
        end
    end

    function B.sum(name)
        return function(entries)
            if not is_array(entries) then error("asdl_builder.sum expects an array table", 2) end
            local variants, attrs = {}, {}
            for i = 1, #entries do
                local item = entries[i]
                local cls = pvm.classof(item)
                if cls == A.Variant then variants[#variants + 1] = item
                elseif type(item) == "table" and item._moon_asdl_variant_builder == true then variants[#variants + 1] = item:build_empty()
                elseif cls == A.DeclDoc then attrs[#attrs + 1] = item
                else error("asdl_builder: unexpected sum entry " .. tostring(item), 2) end
            end
            return A.SumDecl(name, variants, attrs)
        end
    end

    function B.alias(name)
        return function(target)
            return A.AliasDecl(name, type_expr(target), {})
        end
    end

    function B.variant(name)
        local builder = { _moon_asdl_variant_builder = true, name = name }
        function builder:build_empty()
            return A.Variant(self.name, {}, {})
        end
        return setmetatable(builder, {
            __call = function(self, entries)
                if entries == nil then return self:build_empty() end
                if not is_array(entries) then error("asdl_builder.variant expects an array table", 2) end
                local fields, attrs = split_variant_entries(entries)
                return A.Variant(self.name, fields, attrs)
            end,
        })
    end

    function B.field(name)
        return function(ty)
            return A.Field(name, type_expr(ty), A.FieldOne)
        end
    end

    function B.many(ty) return A.TypeList(type_expr(ty)) end
    function B.optional(ty) return A.TypeOptional(type_expr(ty)) end
    function B.type(ty) return type_expr(ty) end

    B.unique = A.DeclUnique
    B.variant_unique = A.VariantUnique
    function B.doc(text) return A.DeclDoc(text) end
    function B.module_doc(text) return A.ModuleDoc(text) end
    function B.variant_doc(text) return A.VariantDoc(text) end

    B._T = T
    B._A = A
    return B
end

return M
