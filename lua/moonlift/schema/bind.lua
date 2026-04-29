-- Clean MoonBind schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonBind" {
        A.sum "BindingClass" {
            A.variant "BindingClassLocalValue",
            A.variant "BindingClassLocalCell",
            A.variant "BindingClassArg" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BindingClassBlockParam" {
                A.field "region_id" "string",
                A.field "block_name" "string",
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BindingClassEntryBlockParam" {
                A.field "region_id" "string",
                A.field "block_name" "string",
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BindingClassContParam" {
                A.field "region_id" "string",
                A.field "cont_name" "string",
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BindingClassGlobalFunc" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "BindingClassGlobalConst" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "BindingClassGlobalStatic" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "BindingClassExtern" {
                A.field "symbol" "string",
                A.variant_unique,
            },
            A.variant "BindingClassOpenParam" {
                A.field "param" "MoonOpen.OpenParam",
                A.variant_unique,
            },
            A.variant "BindingClassImport" {
                A.field "import" "MoonOpen.ValueImport",
                A.variant_unique,
            },
            A.variant "BindingClassFuncSym" {
                A.field "sym" "MoonCore.FuncSym",
                A.variant_unique,
            },
            A.variant "BindingClassExternSym" {
                A.field "sym" "MoonCore.ExternSym",
                A.variant_unique,
            },
            A.variant "BindingClassConstSym" {
                A.field "sym" "MoonCore.ConstSym",
                A.variant_unique,
            },
            A.variant "BindingClassStaticSym" {
                A.field "sym" "MoonCore.StaticSym",
                A.variant_unique,
            },
            A.variant "BindingClassFuncSlot" {
                A.field "slot" "MoonOpen.FuncSlot",
                A.variant_unique,
            },
            A.variant "BindingClassConstSlot" {
                A.field "slot" "MoonOpen.ConstSlot",
                A.variant_unique,
            },
            A.variant "BindingClassStaticSlot" {
                A.field "slot" "MoonOpen.StaticSlot",
                A.variant_unique,
            },
            A.variant "BindingClassValueSlot" {
                A.field "slot" "MoonOpen.ValueSlot",
                A.variant_unique,
            },
        },

        A.product "Binding" {
            A.field "id" "MoonCore.Id",
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.field "class" "MoonBind.BindingClass",
            A.unique,
        },

        A.sum "Residence" {
            A.variant "ResidenceUnknown",
            A.variant "ResidenceValue",
            A.variant "ResidenceStack",
            A.variant "ResidenceCell",
        },

        A.sum "ResidenceReason" {
            A.variant "ResidenceBecauseDefault",
            A.variant "ResidenceBecauseAddressTaken",
            A.variant "ResidenceBecauseMutableCell",
            A.variant "ResidenceBecauseNonScalarAbi",
            A.variant "ResidenceBecauseMaterializedTemporary",
            A.variant "ResidenceBecauseBackendRequired",
        },

        A.sum "ResidenceFact" {
            A.variant "ResidenceFactBinding" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ResidenceFactAddressTaken" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ResidenceFactMutableCell" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ResidenceFactNonScalarAbi" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ResidenceFactMaterializedTemporary" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ResidenceFactBackendRequired" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
        },

        A.product "ResidenceFactSet" {
            A.field "facts" (A.many "MoonBind.ResidenceFact"),
            A.unique,
        },

        A.product "ResidenceDecision" {
            A.field "binding" "MoonBind.Binding",
            A.field "residence" "MoonBind.Residence",
            A.field "reason" "MoonBind.ResidenceReason",
            A.unique,
        },

        A.product "ResidencePlan" {
            A.field "decisions" (A.many "MoonBind.ResidenceDecision"),
            A.unique,
        },

        A.product "MachineBinding" {
            A.field "binding" "MoonBind.Binding",
            A.field "residence" "MoonBind.Residence",
            A.unique,
        },

        A.product "MachineBindingSet" {
            A.field "bindings" (A.many "MoonBind.MachineBinding"),
            A.unique,
        },

        A.sum "ValueRef" {
            A.variant "ValueRefName" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ValueRefPath" {
                A.field "path" "MoonCore.Path",
                A.variant_unique,
            },
            A.variant "ValueRefBinding" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ValueRefSlot" {
                A.field "slot" "MoonOpen.ValueSlot",
                A.variant_unique,
            },
            A.variant "ValueRefFuncSlot" {
                A.field "slot" "MoonOpen.FuncSlot",
                A.variant_unique,
            },
            A.variant "ValueRefConstSlot" {
                A.field "slot" "MoonOpen.ConstSlot",
                A.variant_unique,
            },
            A.variant "ValueRefStaticSlot" {
                A.field "slot" "MoonOpen.StaticSlot",
                A.variant_unique,
            },
        },

        A.product "ValueEntry" {
            A.field "name" "string",
            A.field "binding" "MoonBind.Binding",
            A.unique,
        },

        A.product "TypeEntry" {
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "Env" {
            A.field "module_name" "string",
            A.field "values" (A.many "MoonBind.ValueEntry"),
            A.field "types" (A.many "MoonBind.TypeEntry"),
            A.field "layouts" (A.many "MoonSem.TypeLayout"),
            A.unique,
        },

        A.product "ConstEntry" {
            A.field "module_name" "string",
            A.field "item_name" "string",
            A.field "ty" "MoonType.Type",
            A.field "value" "MoonTree.Expr",
            A.unique,
        },

        A.product "ConstEnv" {
            A.field "entries" (A.many "MoonBind.ConstEntry"),
            A.unique,
        },

        A.sum "StmtEnvEffect" {
            A.variant "StmtEnvNoBinding",
            A.variant "StmtEnvAddBinding" {
                A.field "entry" "MoonBind.ValueEntry",
                A.variant_unique,
            },
            A.variant "StmtEnvAddBindings" {
                A.field "entries" (A.many "MoonBind.ValueEntry"),
                A.variant_unique,
            },
        },
    }
end
