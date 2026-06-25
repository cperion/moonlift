-- LalinAsdl projection meta-model.
--
-- This defines the small runtime schema value vocabulary used as the projection
-- target for LalinSchema.  It is intentionally built directly as runtime classes;
-- there is no text schema parser in the active path.

local schema_context = require("lalin.schema_context")

local DEFINITIONS = {
    {
        name = "LalinAsdl.Schema",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "modules", type = "LalinAsdl.Module", list = true },
            },
        },
    },
    {
        name = "LalinAsdl.Module",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "decls", type = "LalinAsdl.Decl", list = true },
                { name = "attrs", type = "LalinAsdl.ModuleAttr", list = true },
            },
        },
    },
    {
        name = "LalinAsdl.Decl",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.SumDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "variants", type = "LalinAsdl.Variant", list = true },
                    { name = "attrs", type = "LalinAsdl.DeclAttr", list = true },
                } },
                { name = "LalinAsdl.ProductDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "fields", type = "LalinAsdl.Field", list = true },
                    { name = "attrs", type = "LalinAsdl.DeclAttr", list = true },
                } },
                { name = "LalinAsdl.AliasDecl", unique = true, fields = {
                    { name = "name", type = "string" },
                    { name = "target", type = "LalinAsdl.TypeExpr" },
                    { name = "attrs", type = "LalinAsdl.DeclAttr", list = true },
                } },
            },
        },
    },
    {
        name = "LalinAsdl.Variant",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "fields", type = "LalinAsdl.Field", list = true },
                { name = "attrs", type = "LalinAsdl.VariantAttr", list = true },
            },
        },
    },
    {
        name = "LalinAsdl.Field",
        type = {
            kind = "product",
            unique = true,
            fields = {
                { name = "name", type = "string" },
                { name = "ty", type = "LalinAsdl.TypeExpr" },
                { name = "cardinality", type = "LalinAsdl.FieldCardinality" },
            },
        },
    },
    {
        name = "LalinAsdl.TypeExpr",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.TypeBuiltin", unique = true, fields = { { name = "name", type = "string" } } },
                { name = "LalinAsdl.TypeName", unique = true, fields = {
                    { name = "module_name", type = "string" },
                    { name = "name", type = "string" },
                } },
                { name = "LalinAsdl.TypeRelativeName", unique = true, fields = { { name = "name", type = "string" } } },
                { name = "LalinAsdl.TypeList", unique = true, fields = { { name = "elem", type = "LalinAsdl.TypeExpr" } } },
                { name = "LalinAsdl.TypeOptional", unique = true, fields = { { name = "elem", type = "LalinAsdl.TypeExpr" } } },
            },
        },
    },
    {
        name = "LalinAsdl.FieldCardinality",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.FieldOne" },
                { name = "LalinAsdl.FieldMany" },
                { name = "LalinAsdl.FieldOptional" },
            },
        },
    },
    {
        name = "LalinAsdl.DeclAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.DeclUnique" },
                { name = "LalinAsdl.DeclDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
    {
        name = "LalinAsdl.ModuleAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.ModuleDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
    {
        name = "LalinAsdl.VariantAttr",
        type = {
            kind = "sum",
            constructors = {
                { name = "LalinAsdl.VariantUnique" },
                { name = "LalinAsdl.VariantDoc", unique = true, fields = { { name = "text", type = "string" } } },
            },
        },
    },
}

local function bind_context(T)
    if T.LalinAsdl ~= nil then return T end
    schema_context.define(T, DEFINITIONS)
    return T
end

return bind_context