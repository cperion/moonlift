-- Clean MoonType schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonType" {
        A.sum "TypeRef" {
            A.variant "TypeRefPath" {
                A.field "path" "MoonCore.Path",
                A.variant_unique,
            },
            A.variant "TypeRefGlobal" {
                A.field "module_name" "string",
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "TypeRefLocal" {
                A.field "sym" "MoonCore.TypeSym",
                A.variant_unique,
            },
            A.variant "TypeRefSlot" {
                A.field "slot" "MoonOpen.TypeSlot",
                A.variant_unique,
            },
        },

        A.sum "ArrayLen" {
            A.variant "ArrayLenExpr" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ArrayLenConst" {
                A.field "count" "number",
                A.variant_unique,
            },
            A.variant "ArrayLenSlot" {
                A.field "slot" "MoonOpen.ExprSlot",
                A.variant_unique,
            },
        },

        A.sum "Type" {
            A.variant "TScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "TPtr" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TArray" {
                A.field "count" "MoonType.ArrayLen",
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TSlice" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TView" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TFunc" {
                A.field "params" (A.many "MoonType.Type"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TClosure" {
                A.field "params" (A.many "MoonType.Type"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TNamed" {
                A.field "ref" "MoonType.TypeRef",
                A.variant_unique,
            },
            A.variant "TSlot" {
                A.field "slot" "MoonOpen.TypeSlot",
                A.variant_unique,
            },
        },

        A.sum "TypeClass" {
            A.variant "TypeClassScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "TypeClassPointer" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeClassArray" {
                A.field "elem" "MoonType.Type",
                A.field "count" "number",
                A.variant_unique,
            },
            A.variant "TypeClassSlice" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeClassView" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeClassCallable" {
                A.field "params" (A.many "MoonType.Type"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeClassClosure" {
                A.field "params" (A.many "MoonType.Type"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeClassAggregate" {
                A.field "module_name" "string",
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "TypeClassUnknown",
        },

        A.sum "TypeBackScalarResult" {
            A.variant "TypeBackScalarKnown" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "TypeBackScalarUnavailable" {
                A.field "ty" "MoonType.Type",
                A.field "class" "MoonType.TypeClass",
                A.variant_unique,
            },
        },

        A.sum "TypeMemLayoutResult" {
            A.variant "TypeMemLayoutKnown" {
                A.field "layout" "MoonSem.MemLayout",
                A.variant_unique,
            },
            A.variant "TypeMemLayoutUnknown" {
                A.field "ty" "MoonType.Type",
                A.field "class" "MoonType.TypeClass",
                A.variant_unique,
            },
        },

        A.sum "AbiClass" {
            A.variant "AbiIgnore",
            A.variant "AbiDirect" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "AbiIndirect" {
                A.field "layout" "MoonSem.MemLayout",
                A.variant_unique,
            },
            A.variant "AbiDescriptor" {
                A.field "layout" "MoonSem.MemLayout",
                A.variant_unique,
            },
            A.variant "AbiUnknown" {
                A.field "class" "MoonType.TypeClass",
                A.variant_unique,
            },
        },

        A.product "AbiDecision" {
            A.field "ty" "MoonType.Type",
            A.field "class" "MoonType.AbiClass",
            A.unique,
        },

        A.sum "AbiParamPlan" {
            A.variant "AbiParamScalar" {
                A.field "name" "string",
                A.field "binding" "MoonBind.Binding",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "AbiParamView" {
                A.field "name" "string",
                A.field "binding" "MoonBind.Binding",
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.field "stride" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "AbiParamRejected" {
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "AbiResultPlan" {
            A.variant "AbiResultVoid",
            A.variant "AbiResultScalar" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "AbiResultView" {
                A.field "elem" "MoonType.Type",
                A.field "out" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "AbiResultRejected" {
                A.field "ty" "MoonType.Type",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "FuncAbiPlan" {
            A.field "func_name" "string",
            A.field "params" (A.many "MoonType.AbiParamPlan"),
            A.field "result" "MoonType.AbiResultPlan",
            A.unique,
        },

        A.product "Param" {
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "FieldDecl" {
            A.field "field_name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "VariantDecl" {
            A.field "name" "string",
            A.field "payload" "MoonType.Type",
            A.unique,
        },
    }
end
