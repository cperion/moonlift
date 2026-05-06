-- Clean MoonOpen schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonOpen" {
        A.product "TypeSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "ValueSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "ExprSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "ty" (A.optional "MoonType.Type"),
            A.unique,
        },

        A.product "PlaceSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "ty" (A.optional "MoonType.Type"),
            A.unique,
        },

        A.product "DomainSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "RegionSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "ContSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "params" (A.many "MoonTree.BlockParam"),
            A.unique,
        },

        A.product "FuncSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "fn_ty" "MoonType.Type",
            A.unique,
        },

        A.product "ConstSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "StaticSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "TypeDeclSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "ItemsSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "ModuleSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "NameSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "RegionFragSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "ExprFragSlot" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.sum "RegionFragRef" {
            A.variant "RegionFragRefName" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "RegionFragRefSlot" {
                A.field "slot" "MoonOpen.RegionFragSlot",
                A.variant_unique,
            },
        },

        A.sum "ExprFragRef" {
            A.variant "ExprFragRefName" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ExprFragRefSlot" {
                A.field "slot" "MoonOpen.ExprFragSlot",
                A.variant_unique,
            },
        },

        A.sum "Slot" {
            A.variant "SlotType" {
                A.field "slot" "MoonOpen.TypeSlot",
                A.variant_unique,
            },
            A.variant "SlotValue" {
                A.field "slot" "MoonOpen.ValueSlot",
                A.variant_unique,
            },
            A.variant "SlotExpr" {
                A.field "slot" "MoonOpen.ExprSlot",
                A.variant_unique,
            },
            A.variant "SlotPlace" {
                A.field "slot" "MoonOpen.PlaceSlot",
                A.variant_unique,
            },
            A.variant "SlotDomain" {
                A.field "slot" "MoonOpen.DomainSlot",
                A.variant_unique,
            },
            A.variant "SlotRegion" {
                A.field "slot" "MoonOpen.RegionSlot",
                A.variant_unique,
            },
            A.variant "SlotCont" {
                A.field "slot" "MoonOpen.ContSlot",
                A.variant_unique,
            },
            A.variant "SlotFunc" {
                A.field "slot" "MoonOpen.FuncSlot",
                A.variant_unique,
            },
            A.variant "SlotConst" {
                A.field "slot" "MoonOpen.ConstSlot",
                A.variant_unique,
            },
            A.variant "SlotStatic" {
                A.field "slot" "MoonOpen.StaticSlot",
                A.variant_unique,
            },
            A.variant "SlotTypeDecl" {
                A.field "slot" "MoonOpen.TypeDeclSlot",
                A.variant_unique,
            },
            A.variant "SlotItems" {
                A.field "slot" "MoonOpen.ItemsSlot",
                A.variant_unique,
            },
            A.variant "SlotModule" {
                A.field "slot" "MoonOpen.ModuleSlot",
                A.variant_unique,
            },
            A.variant "SlotRegionFrag" {
                A.field "slot" "MoonOpen.RegionFragSlot",
                A.variant_unique,
            },
            A.variant "SlotExprFrag" {
                A.field "slot" "MoonOpen.ExprFragSlot",
                A.variant_unique,
            },
            A.variant "SlotName" {
                A.field "slot" "MoonOpen.NameSlot",
                A.variant_unique,
            },
        },

        A.sum "ModuleNameFacet" {
            A.variant "ModuleNameOpen",
            A.variant "ModuleNameFixed" {
                A.field "module_name" "string",
                A.variant_unique,
            },
        },

        A.product "OpenParam" {
            A.field "key" "string",
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.sum "ValueImport" {
            A.variant "ImportValue" {
                A.field "key" "string",
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ImportGlobalFunc" {
                A.field "key" "string",
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ImportGlobalConst" {
                A.field "key" "string",
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ImportGlobalStatic" {
                A.field "key" "string",
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ImportExtern" {
                A.field "key" "string",
                A.field "symbol" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.product "TypeImport" {
            A.field "key" "string",
            A.field "local_name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "OpenSet" {
            A.field "value_imports" (A.many "MoonOpen.ValueImport"),
            A.field "type_imports" (A.many "MoonOpen.TypeImport"),
            A.field "layouts" (A.many "MoonSem.TypeLayout"),
            A.field "slots" (A.many "MoonOpen.Slot"),
            A.unique,
        },

        A.sum "SourceBinding" {
            A.variant "SourceParamBinding" {
                A.field "param" "MoonOpen.OpenParam",
                A.variant_unique,
            },
            A.variant "SourceValueImportBinding" {
                A.field "import" "MoonOpen.ValueImport",
                A.variant_unique,
            },
            A.variant "SourceExprSlotBinding" {
                A.field "slot" "MoonOpen.ExprSlot",
                A.variant_unique,
            },
            A.variant "SourceFuncSlotBinding" {
                A.field "slot" "MoonOpen.FuncSlot",
                A.variant_unique,
            },
            A.variant "SourceConstSlotBinding" {
                A.field "slot" "MoonOpen.ConstSlot",
                A.variant_unique,
            },
            A.variant "SourceStaticSlotBinding" {
                A.field "slot" "MoonOpen.StaticSlot",
                A.variant_unique,
            },
        },

        A.product "SourceBindingEntry" {
            A.field "binding" "MoonBind.Binding",
            A.field "source" "MoonOpen.SourceBinding",
            A.unique,
        },

        A.product "SourceTypeEntry" {
            A.field "ty" "MoonType.Type",
            A.field "meta_ty" "MoonType.Type",
            A.unique,
        },

        A.product "SourceEnv" {
            A.field "module_name" "string",
            A.field "bindings" (A.many "MoonOpen.SourceBindingEntry"),
            A.field "types" (A.many "MoonOpen.SourceTypeEntry"),
            A.unique,
        },

        A.product "FragId" {
            A.field "key" "string",
            A.field "pretty_name" "string",
            A.unique,
        },

        A.product "UseId" {
            A.field "path" "string",
            A.unique,
        },

        A.sum "ContTarget" {
            A.variant "ContTargetLabel" {
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ContTargetSlot" {
                A.field "slot" "MoonOpen.ContSlot",
                A.variant_unique,
            },
        },

        A.product "ContBinding" {
            A.field "name" "string",
            A.field "target" "MoonOpen.ContTarget",
            A.unique,
        },

        A.product "ParamBinding" {
            A.field "param" "MoonOpen.OpenParam",
            A.field "value" "MoonTree.Expr",
            A.unique,
        },

        A.product "FillSet" {
            A.field "bindings" (A.many "MoonOpen.SlotBinding"),
            A.unique,
        },

        A.product "ExpandEnv" {
            A.field "region_frags" (A.many "MoonOpen.RegionFrag"),
            A.field "expr_frags" (A.many "MoonOpen.ExprFrag"),
            A.field "fills" "MoonOpen.FillSet",
            A.field "conts" (A.many "MoonOpen.ContBinding"),
            A.field "params" (A.many "MoonOpen.ParamBinding"),
            A.field "rebase_prefix" "string",
            A.unique,
        },

        A.product "SealParamEntry" {
            A.field "param" "MoonOpen.OpenParam",
            A.field "index" "number",
            A.unique,
        },

        A.product "SealEnv" {
            A.field "module_name" "string",
            A.field "params" (A.many "MoonOpen.SealParamEntry"),
            A.unique,
        },

        A.product "ExprFrag" {
            A.field "name" "string",
            A.field "params" (A.many "MoonOpen.OpenParam"),
            A.field "open" "MoonOpen.OpenSet",
            A.field "body" "MoonTree.Expr",
            A.field "result" "MoonType.Type",
            A.unique,
        },

        A.product "RegionFrag" {
            A.field "name" "string",
            A.field "params" (A.many "MoonOpen.OpenParam"),
            A.field "conts" (A.many "MoonOpen.ContSlot"),
            A.field "open" "MoonOpen.OpenSet",
            A.field "entry" "MoonTree.EntryControlBlock",
            A.field "blocks" (A.many "MoonTree.ControlBlock"),
            A.unique,
        },

        A.sum "SlotValue" {
            A.variant "SlotValueType" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "SlotValueExpr" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "SlotValuePlace" {
                A.field "place" "MoonTree.Place",
                A.variant_unique,
            },
            A.variant "SlotValueDomain" {
                A.field "domain" "MoonTree.Domain",
                A.variant_unique,
            },
            A.variant "SlotValueRegion" {
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "SlotValueCont" {
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "SlotValueContSlot" {
                A.field "slot" "MoonOpen.ContSlot",
                A.variant_unique,
            },
            A.variant "SlotValueFunc" {
                A.field "func" "MoonTree.Func",
                A.variant_unique,
            },
            A.variant "SlotValueConst" {
                A.field "c" "MoonTree.ConstItem",
                A.variant_unique,
            },
            A.variant "SlotValueStatic" {
                A.field "s" "MoonTree.StaticItem",
                A.variant_unique,
            },
            A.variant "SlotValueTypeDecl" {
                A.field "t" "MoonTree.TypeDecl",
                A.variant_unique,
            },
            A.variant "SlotValueItems" {
                A.field "items" (A.many "MoonTree.Item"),
                A.variant_unique,
            },
            A.variant "SlotValueModule" {
                A.field "module" "MoonTree.Module",
                A.variant_unique,
            },
            A.variant "SlotValueRegionFrag" {
                A.field "frag" "MoonOpen.RegionFrag",
                A.variant_unique,
            },
            A.variant "SlotValueExprFrag" {
                A.field "frag" "MoonOpen.ExprFrag",
                A.variant_unique,
            },
            A.variant "SlotValueName" {
                A.field "text" "string",
                A.variant_unique,
            },
        },

        A.product "SlotBinding" {
            A.field "slot" "MoonOpen.Slot",
            A.field "value" "MoonOpen.SlotValue",
            A.unique,
        },

        A.sum "RewriteRule" {
            A.variant "RewriteType" {
                A.field "from" "MoonType.Type",
                A.field "to" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "RewriteBinding" {
                A.field "from" "MoonBind.Binding",
                A.field "to" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "RewritePlace" {
                A.field "from" "MoonTree.Place",
                A.field "to" "MoonTree.Place",
                A.variant_unique,
            },
            A.variant "RewriteDomain" {
                A.field "from" "MoonTree.Domain",
                A.field "to" "MoonTree.Domain",
                A.variant_unique,
            },
            A.variant "RewriteExpr" {
                A.field "from" "MoonTree.Expr",
                A.field "to" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "RewriteStmt" {
                A.field "from" "MoonTree.Stmt",
                A.field "to" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "RewriteItem" {
                A.field "from" "MoonTree.Item",
                A.field "to" (A.many "MoonTree.Item"),
                A.variant_unique,
            },
        },

        A.product "RewriteSet" {
            A.field "rules" (A.many "MoonOpen.RewriteRule"),
            A.unique,
        },

        A.sum "MetaFact" {
            A.variant "MetaFactSlot" {
                A.field "slot" "MoonOpen.Slot",
                A.variant_unique,
            },
            A.variant "MetaFactParamUse" {
                A.field "param" "MoonOpen.OpenParam",
                A.variant_unique,
            },
            A.variant "MetaFactValueImportUse" {
                A.field "import" "MoonOpen.ValueImport",
                A.variant_unique,
            },
            A.variant "MetaFactLocalValue" {
                A.field "id" "string",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactLocalCell" {
                A.field "id" "string",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactBlockParam" {
                A.field "region_id" "string",
                A.field "block_name" "string",
                A.field "index" "number",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactEntryBlockParam" {
                A.field "region_id" "string",
                A.field "block_name" "string",
                A.field "index" "number",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactGlobalFunc" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactGlobalConst" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactGlobalStatic" {
                A.field "module_name" "string",
                A.field "item_name" "string",
                A.variant_unique,
            },
            A.variant "MetaFactExtern" {
                A.field "symbol" "string",
                A.variant_unique,
            },
            A.variant "MetaFactExprFragUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "MetaFactRegionFragUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "MetaFactRegionFragSlotUse" {
                A.field "slot" "MoonOpen.RegionFragSlot",
                A.variant_unique,
            },
            A.variant "MetaFactExprFragSlotUse" {
                A.field "slot" "MoonOpen.ExprFragSlot",
                A.variant_unique,
            },
            A.variant "MetaFactModuleUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "MetaFactModuleSlotUse" {
                A.field "use_id" "string",
                A.field "slot" "MoonOpen.ModuleSlot",
                A.variant_unique,
            },
            A.variant "MetaFactOpenModuleName",
            A.variant "MetaFactLocalType" {
                A.field "sym" "MoonCore.TypeSym",
                A.variant_unique,
            },
        },

        A.product "MetaFactSet" {
            A.field "facts" (A.many "MoonOpen.MetaFact"),
            A.unique,
        },

        A.sum "ValidationIssue" {
            A.variant "IssueOpenSlot" {
                A.field "slot" "MoonOpen.Slot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledTypeSlot" {
                A.field "slot" "MoonOpen.TypeSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledExprSlot" {
                A.field "slot" "MoonOpen.ExprSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledPlaceSlot" {
                A.field "slot" "MoonOpen.PlaceSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledDomainSlot" {
                A.field "slot" "MoonOpen.DomainSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledRegionSlot" {
                A.field "slot" "MoonOpen.RegionSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledContSlot" {
                A.field "slot" "MoonOpen.ContSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledFuncSlot" {
                A.field "slot" "MoonOpen.FuncSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledConstSlot" {
                A.field "slot" "MoonOpen.ConstSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledStaticSlot" {
                A.field "slot" "MoonOpen.StaticSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledTypeDeclSlot" {
                A.field "slot" "MoonOpen.TypeDeclSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledItemsSlot" {
                A.field "slot" "MoonOpen.ItemsSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledModuleSlot" {
                A.field "slot" "MoonOpen.ModuleSlot",
                A.variant_unique,
            },
            A.variant "IssueUnexpandedExprFragUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "IssueUnexpandedRegionFragUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "IssueUnfilledRegionFragSlot" {
                A.field "slot" "MoonOpen.RegionFragSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledExprFragSlot" {
                A.field "slot" "MoonOpen.ExprFragSlot",
                A.variant_unique,
            },
            A.variant "IssueUnfilledNameSlot" {
                A.field "slot" "MoonOpen.NameSlot",
                A.variant_unique,
            },
            A.variant "IssueUnexpandedModuleUse" {
                A.field "use_id" "string",
                A.variant_unique,
            },
            A.variant "IssueOpenModuleName",
            A.variant "IssueGenericValueImport" {
                A.field "import" "MoonOpen.ValueImport",
                A.variant_unique,
            },
        },

        A.product "ValidationReport" {
            A.field "issues" (A.many "MoonOpen.ValidationIssue"),
            A.unique,
        },
    }
end
