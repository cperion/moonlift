-- MoonAsdl projection meta-model.
--
-- This defines the small runtime schema value vocabulary used as the projection
-- target for MoonSchema.  It is intentionally built directly as runtime classes;
-- there is no text schema parser in the active path.

local schema_context = require("moonlift.schema_context")

local DEFINITIONS = {
    {
        name = "MoonAsdl.Schema",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "modules", type = "MoonAsdl.Module", list = true },
            },
        },
    },
    {
        name = "MoonAsdl.Module",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "decls", type = "MoonAsdl.Decl", list = true },
                { name = "attrs", type = "MoonAsdl.ModuleAttr", list = true },
            },
        },
    },
    {
        name = "MoonAsdl.Decl",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.SumDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "variants", type = "MoonAsdl.Variant", list = true },
                    { name = "attrs", type = "MoonAsdl.DeclAttr", list = true },
                } },
                { name = "MoonAsdl.ProductDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "fields", type = "MoonAsdl.Field", list = true },
                    { name = "attrs", type = "MoonAsdl.DeclAttr", list = true },
                } },
                { name = "MoonAsdl.AliasDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "target", type = "MoonAsdl.TypeExpr" },
                    { name = "attrs", type = "MoonAsdl.DeclAttr", list = true },
                } },
            },
        },
    },
    {
        name = "MoonAsdl.Variant",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "fields", type = "MoonAsdl.Field", list = true },
                { name = "attrs", type = "MoonAsdl.VariantAttr", list = true },
            },
        },
    },
    {
        name = "MoonAsdl.Field",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "ty", type = "MoonAsdl.TypeExpr" },
                { name = "cardinality", type = "MoonAsdl.FieldCardinality" },
            },
        },
    },
    {
        name = "MoonAsdl.TypeExpr",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.TypeBuiltin", unique = true, fields = { { name = "name", type = "string" } } },
                { name = "MoonAsdl.TypeName", unique = true, fields = {
                    { name = "module_name", type = "string" },
                    { name = "name", type = "string" },
                } },
                { name = "MoonAsdl.TypeRelativeName", unique = true, fields = { { name = "name", type = "string" } } },
                { name = "MoonAsdl.TypeList", unique = true, fields = { { name = "elem", type = "MoonAsdl.TypeExpr" } } },
                { name = "MoonAsdl.TypeOptional", unique = true, fields = { { name = "elem", type = "MoonAsdl.TypeExpr" } } },
            },
        },
    },
    {
        name = "MoonAsdl.FieldCardinality",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.FieldOne" },
                { name = "MoonAsdl.FieldMany" },
                { name = "MoonAsdl.FieldOptional" },
            },
        },
    },
    {
        name = "MoonAsdl.DeclAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.DeclUnique" },
                { name = "MoonAsdl.DeclDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
    {
        name = "MoonAsdl.ModuleAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.ModuleDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
    {
        name = "MoonAsdl.VariantAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "MoonAsdl.VariantUnique" },
                { name = "MoonAsdl.VariantDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
}

local function bind_context(T)
    if T.MoonAsdl ~= nil then return T end
    schema_context.define(T, DEFINITIONS)
    return T
end

return bind_context