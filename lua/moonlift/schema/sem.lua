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

        A.sum "ConstStmtResult" {
            A.variant "ConstStmtFallsThrough" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.variant_unique,
            },
            A.variant "ConstStmtReturnVoid" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.variant_unique,
            },
            A.variant "ConstStmtReturnValue" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.field "value" "MoonSem.ConstValue",
                A.variant_unique,
            },
            A.variant "ConstStmtYieldVoid" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.variant_unique,
            },
            A.variant "ConstStmtYieldValue" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.field "value" "MoonSem.ConstValue",
                A.variant_unique,
            },
            A.variant "ConstStmtJump" {
                A.field "local_env" "MoonSem.ConstLocalEnv",
                A.field "target_label" "string",
                A.variant_unique,
            },
        },

        A.sum "ExprExit" {
            A.variant "ExprEndOnly",
            A.variant "ExprEndOrYieldValue",
        },

        A.sum "OperandContext" {
            A.variant "OperandNeedsExpected",
            A.variant "OperandHasNaturalType",
        },

        A.sum "ValueClass" {
            A.variant "ValueUnknown",
            A.variant "ValuePlain",
            A.variant "ValueAddress",
            A.variant "ValueMaterialized",
            A.variant "ValueTerminated",
        },

        A.sum "ConstClass" {
            A.variant "ConstClassUnknown",
            A.variant "ConstClassNo",
            A.variant "ConstClassYes" {
                A.field "value" "MoonSem.ConstValue",
                A.variant_unique,
            },
        },

        A.sum "CodeShapeClass" {
            A.variant "CodeShapeUnknown",
            A.variant "CodeShapeScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "CodeShapeVector" {
                A.field "elem" "MoonCore.Scalar",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        A.sum "AddressClass" {
            A.variant "AddressUnknown",
            A.variant "AddressBinding",
            A.variant "AddressStack",
            A.variant "AddressStatic",
            A.variant "AddressDeref",
            A.variant "AddressProjection",
            A.variant "AddressIndex",
            A.variant "AddressTemporary",
        },

        A.sum "FlowClass" {
            A.variant "FlowUnknown",
            A.variant "FlowFallsThrough",
            A.variant "FlowJumps",
            A.variant "FlowYields",
            A.variant "FlowReturns",
            A.variant "FlowTerminates",
        },

        A.sum "SwitchKey" {
            A.variant "SwitchKeyExpr" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "SwitchKeyConst" {
                A.field "value" "MoonSem.ConstValue",
                A.variant_unique,
            },
            A.variant "SwitchKeyRaw" {
                A.field "raw" "string",
                A.variant_unique,
            },
        },

        A.product "SwitchKeySet" {
            A.field "keys" (A.many "MoonSem.SwitchKey"),
            A.unique,
        },

        A.sum "SwitchDecision" {
            A.variant "SwitchDecisionConstKeys" {
                A.field "keys" (A.many "MoonSem.SwitchKey"),
                A.variant_unique,
            },
            A.variant "SwitchDecisionExprKeys" {
                A.field "keys" (A.many "MoonSem.SwitchKey"),
                A.variant_unique,
            },
            A.variant "SwitchDecisionCompareFallback" {
                A.field "keys" (A.many "MoonSem.SwitchKey"),
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "CallTarget" {
            A.variant "CallUnresolved" {
                A.field "callee" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "CallDirect" {
                A.field "module_name" "string",
                A.field "func_name" "string",
                A.field "fn_ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "CallExtern" {
                A.field "symbol" "string",
                A.field "fn_ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "CallIndirect" {
                A.field "callee" "MoonTree.Expr",
                A.field "fn_ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "CallClosure" {
                A.field "closure" "MoonTree.Expr",
                A.field "fn_ty" "MoonType.Type",
                A.variant_unique,
            },
        },
    }
end
