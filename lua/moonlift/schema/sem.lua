-- Clean MoonSem schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonSem" {
        A.sum "FieldRef" {
            A.variant "FieldByName" {
                A.field "field_name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "FieldByOffset" {
                A.field "field_name" "string",
                A.field "offset" "number",
                A.field "ty" "MoonType.Type",
                A.field "storage" "MoonHost.HostFieldRep",
                A.variant_unique,
            },
        },

        A.product "FieldLayout" {
            A.field "field_name" "string",
            A.field "offset" "number",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "MemLayout" {
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.sum "TypeLayout" {
            A.variant "LayoutNamed" {
                A.field "module_name" "string",
                A.field "type_name" "string",
                A.field "fields" (A.many "MoonSem.FieldLayout"),
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "LayoutLocal" {
                A.field "sym" "MoonCore.TypeSym",
                A.field "fields" (A.many "MoonSem.FieldLayout"),
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
        },

        A.product "LayoutEnv" {
            A.field "layouts" (A.many "MoonSem.TypeLayout"),
            A.unique,
        },

        A.product "ConstFieldValue" {
            A.field "name" "string",
            A.field "value" "MoonSem.ConstValue",
            A.unique,
        },

        A.sum "ConstValue" {
            A.variant "ConstInt" {
                A.field "ty" "MoonType.Type",
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "ConstFloat" {
                A.field "ty" "MoonType.Type",
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "ConstBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "ConstNil" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ConstAgg" {
                A.field "ty" "MoonType.Type",
                A.field "fields" (A.many "MoonSem.ConstFieldValue"),
                A.variant_unique,
            },
            A.variant "ConstArray" {
                A.field "elem_ty" "MoonType.Type",
                A.field "elems" (A.many "MoonSem.ConstValue"),
                A.variant_unique,
            },
        },

        A.product "ConstLocalEntry" {
            A.field "binding" "MoonBind.Binding",
            A.field "value" "MoonSem.ConstValue",
            A.unique,
        },

        A.product "ConstLocalEnv" {
            A.field "entries" (A.many "MoonSem.ConstLocalEntry"),
            A.unique,
        },

        A.sum "FlowClass" {
            A.variant "FlowUnknown",
            A.variant "FlowFallsThrough",
            A.variant "FlowJumps",
            A.variant "FlowYields",
            A.variant "FlowReturns",
            A.variant "FlowTerminates",
        },

    }
end
