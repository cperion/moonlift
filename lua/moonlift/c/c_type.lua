-- MoonC schema: C type facts produced by cimport, consumed by lower_c and typecheck
-- Defined per C_FRONTEND_DESIGN.md §7.5

return function(A)
    return A.module "MoonC" {
        A.product "CTypeId" {
            A.field "module_name" "string",
            A.field "spelling" "string",
            A.unique,
        },

        A.sum "CTypeKind" {
            A.variant "CVoid",
            A.variant "CScalar"     { A.field "scalar" "MoonBack.BackScalar",          A.variant_unique },
            A.variant "CPointer"    { A.field "pointee" "MoonC.CTypeId",             A.variant_unique },
            A.variant "CEnum"       { A.field "scalar" "MoonBack.BackScalar",          A.variant_unique },
            A.variant "CArray"      { A.field "elem" "MoonC.CTypeId", A.field "count" "number", A.variant_unique },
            A.variant "CStruct",
            A.variant "CUnion",
            A.variant "COpaque",
            A.variant "CFuncPtr"    { A.field "sig" "MoonC.CFuncSigId",              A.variant_unique },
        },

        A.product "CTypeFact" {
            A.field "id" "MoonC.CTypeId",
            A.field "kind" "MoonC.CTypeKind",
            A.field "complete" "boolean",
            A.field "size" (A.optional "number"),
            A.field "align" (A.optional "number"),
            A.unique,
        },

        A.product "CFieldLayout" {
            A.field "owner" "MoonC.CTypeId",
            A.field "name" "string",
            A.field "type" "MoonC.CTypeId",
            A.field "offset" "number",
            A.field "size" "number",
            A.field "align" "number",
            A.field "bit_offset" (A.optional "number"),
            A.field "bit_width" (A.optional "number"),
            A.unique,
        },

        A.product "CLayoutFact" {
            A.field "type" "MoonC.CTypeId",
            A.field "size" "number",
            A.field "align" "number",
            A.field "fields" (A.many "MoonC.CFieldLayout"),
            A.unique,
        },

        A.product "CFuncSigId"     { A.field "text" "string", A.unique },

        A.product "CFuncSig" {
            A.field "id" "MoonC.CFuncSigId",
            A.field "params" (A.many "MoonC.CTypeId"),
            A.field "result" "MoonC.CTypeId",
            A.unique,
        },

        A.product "CExternFunc" {
            A.field "moon_name" "string",
            A.field "symbol" "string",
            A.field "sig" "MoonC.CFuncSigId",
            A.field "library" (A.optional "string"),
            A.unique,
        },

        A.product "CLibrary" {
            A.field "name" "string",
            A.field "link_name" (A.optional "string"),
            A.field "path" (A.optional "string"),
            A.field "symbols" (A.many "string"),
            A.unique,
        },
    }
end
