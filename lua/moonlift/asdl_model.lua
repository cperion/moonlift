-- Canonical ASDL-as-data meta-model.
--
-- This is the small bootstrap schema used by the Lua-hosted schema builder.
-- User-facing schema files should build MoonAsdl.Schema values instead of
-- hand-writing parser text.  The old text parser remains a compatibility
-- backend for now.

local M = {}

M.SCHEMA = [[
module MoonAsdl {
    Schema = Schema(MoonAsdl.Module* modules) unique

    Module = Module(string name, MoonAsdl.Decl* decls, MoonAsdl.ModuleAttr* attrs) unique

    Decl = SumDecl(string name, MoonAsdl.Variant* variants, MoonAsdl.DeclAttr* attrs) unique
         | ProductDecl(string name, MoonAsdl.Field* fields, MoonAsdl.DeclAttr* attrs) unique
         | AliasDecl(string name, MoonAsdl.TypeExpr target, MoonAsdl.DeclAttr* attrs) unique

    Variant = Variant(string name, MoonAsdl.Field* fields, MoonAsdl.VariantAttr* attrs) unique

    Field = Field(string name, MoonAsdl.TypeExpr ty, MoonAsdl.FieldCardinality cardinality) unique

    TypeExpr = TypeBuiltin(string name) unique
             | TypeName(string module_name, string name) unique
             | TypeRelativeName(string name) unique
             | TypeList(MoonAsdl.TypeExpr elem) unique
             | TypeOptional(MoonAsdl.TypeExpr elem) unique

    FieldCardinality = FieldOne | FieldMany | FieldOptional

    DeclAttr = DeclUnique
             | DeclDoc(string text) unique

    ModuleAttr = ModuleDoc(string text) unique

    VariantAttr = VariantUnique
                | VariantDoc(string text) unique
}
]]

function M.Define(T)
    if T.MoonAsdl ~= nil then return T end
    T:Define(M.SCHEMA)
    return T
end

return M
