-- Clean MoonHost schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonHost" {
        A.sum "HostIssue" {
            A.variant "HostIssueInvalidName" {
                A.field "site" "string",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueExpected" {
                A.field "site" "string",
                A.field "expected" "string",
                A.field "actual" "string",
                A.variant_unique,
            },
            A.variant "HostIssueDuplicateField" {
                A.field "type_name" "string",
                A.field "field_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueDuplicateType" {
                A.field "module_name" "string",
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueDuplicateDecl" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueDuplicateFunc" {
                A.field "module_name" "string",
                A.field "func_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueUnsealedType" {
                A.field "module_name" "string",
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueSealedMutation" {
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueAlreadySealed" {
                A.field "type_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueUnknownBinding" {
                A.field "site" "string",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueInvalidEmitFill" {
                A.field "fragment_name" "string",
                A.field "fill_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueMissingEmitFill" {
                A.field "fragment_name" "string",
                A.field "fill_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueInvalidPackedAlign" {
                A.field "type_name" "string",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "HostIssueBareBoolInBoundaryStruct" {
                A.field "type_name" "string",
                A.field "field_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueArgCount" {
                A.field "site" "string",
                A.field "expected" "number",
                A.field "actual" "number",
                A.variant_unique,
            },
            A.variant "HostIssueSpliceExpected" {
                A.field "splice_id" "string",
                A.field "expected" "string",
                A.field "actual" "string",
                A.variant_unique,
            },
            A.variant "HostIssueSpliceEvalError" {
                A.field "splice_id" "string",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "HostIssueLuaStepError" {
                A.field "step_id" "string",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "HostIssueTemplateParseError" {
                A.field "template_id" "string",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "HostIssueRegionComposeMissingExit" {
                A.field "fragment_name" "string",
                A.field "exit_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueRegionComposeIncompatibleCont" {
                A.field "fragment_name" "string",
                A.field "exit_name" "string",
                A.field "expected" "string",
                A.field "actual" "string",
                A.variant_unique,
            },
            A.variant "HostIssueRegionComposeIncompleteRoute" {
                A.field "fragment_name" "string",
                A.field "exit_name" "string",
                A.variant_unique,
            },
            A.variant "HostIssueRegionComposeContextMismatch" {
                A.field "left" "string",
                A.field "right" "string",
                A.variant_unique,
            },
        },

        A.product "HostReport" {
            A.field "issues" (A.many "MoonHost.HostIssue"),
            A.unique,
        },

        A.product "HostLayoutId" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },

        A.product "HostFieldId" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },

        A.sum "HostEndian" {
            A.variant "HostEndianLittle",
            A.variant "HostEndianBig",
        },

        A.product "HostTargetModel" {
            A.field "pointer_bits" "number",
            A.field "index_bits" "number",
            A.field "endian" "MoonHost.HostEndian",
            A.unique,
        },

        A.sum "HostLayoutKind" {
            A.variant "HostLayoutStruct",
            A.variant "HostLayoutSlice",
            A.variant "HostLayoutArray",
            A.variant "HostLayoutViewDescriptor",
            A.variant "HostLayoutOpaque",
        },

        A.sum "HostOwner" {
            A.variant "HostOwnerBufferView",
            A.variant "HostOwnerHostSession",
            A.variant "HostOwnerBorrowed",
            A.variant "HostOwnerStatic",
            A.variant "HostOwnerOpaque",
        },

        A.sum "HostBoolEncoding" {
            A.variant "HostBoolU8",
            A.variant "HostBoolI32",
            A.variant "HostBoolNative",
        },

        A.sum "HostRepr" {
            A.variant "HostReprC",
            A.variant "HostReprPacked" {
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "HostReprOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "HostFieldAttr" {
            A.variant "HostFieldReadonly",
            A.variant "HostFieldMutable",
            A.variant "HostFieldNoalias",
            A.variant "HostFieldOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "HostStorageRep" {
            A.variant "HostStorageSame",
            A.variant "HostStorageScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "HostStorageBool" {
                A.field "encoding" "MoonHost.HostBoolEncoding",
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "HostStoragePtr" {
                A.field "pointee" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostStorageSlice" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostStorageView" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostStorageOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "HostStructDecl" {
            A.field "id" "MoonHost.HostLayoutId",
            A.field "name" "string",
            A.field "repr" "MoonHost.HostRepr",
            A.field "fields" (A.many "MoonHost.HostFieldDecl"),
            A.unique,
        },

        A.product "HostFieldDecl" {
            A.field "id" "MoonHost.HostFieldId",
            A.field "name" "string",
            A.field "expose_ty" "MoonType.Type",
            A.field "storage" "MoonHost.HostStorageRep",
            A.field "attrs" (A.many "MoonHost.HostFieldAttr"),
            A.unique,
        },

        A.sum "HostAccessorDecl" {
            A.variant "HostAccessorField" {
                A.field "owner_name" "string",
                A.field "name" "string",
                A.field "field_name" "string",
                A.variant_unique,
            },
            A.variant "HostAccessorLua" {
                A.field "owner_name" "string",
                A.field "name" "string",
                A.field "lua_symbol" "string",
                A.variant_unique,
            },
            A.variant "HostAccessorMoonlift" {
                A.field "owner_name" "string",
                A.field "name" "string",
                A.field "func" "MoonTree.Func",
                A.variant_unique,
            },
        },

        A.sum "HostDecl" {
            A.variant "HostDeclStruct" {
                A.field "decl" "MoonHost.HostStructDecl",
                A.variant_unique,
            },
            A.variant "HostDeclExpose" {
                A.field "decl" "MoonHost.HostExposeDecl",
                A.variant_unique,
            },
            A.variant "HostDeclAccessor" {
                A.field "decl" "MoonHost.HostAccessorDecl",
                A.variant_unique,
            },
        },

        A.product "HostDeclSet" {
            A.field "decls" (A.many "MoonHost.HostDecl"),
            A.unique,
        },

        A.sum "HostDeclSource" {
            A.variant "HostDeclSourceSet" {
                A.field "set" "MoonHost.HostDeclSet",
                A.variant_unique,
            },
            A.variant "HostDeclSourceDecls" {
                A.field "decls" (A.many "MoonHost.HostDecl"),
                A.variant_unique,
            },
        },

        A.product "MluaSource" {
            A.field "name" "string",
            A.field "source" "string",
            A.unique,
        },

        A.product "HostValueId" {
            A.field "key" "string",
            A.field "pretty" "string",
            A.unique,
        },

        A.sum "HostValueKind" {
            A.variant "HostValueRegionFrag",
            A.variant "HostValueExprFrag",
            A.variant "HostValueType",
            A.variant "HostValueDecl",
            A.variant "HostValueModule",
            A.variant "HostValueLua",
            A.variant "HostValueSource",
        },

        A.product "HostValueRef" {
            A.field "id" "MoonHost.HostValueId",
            A.field "kind" "MoonHost.HostValueKind",
            A.unique,
        },

        A.product "TemplatePartText" {
            A.field "source" "MoonSource.SourceSlice",
            A.unique,
        },

        A.product "TemplateSplice" {
            A.field "id" "string",
            A.field "lua_source" "MoonSource.SourceSlice",
            A.unique,
        },

        A.sum "TemplatePart" {
            A.variant "TemplateText" {
                A.field "text" "MoonHost.TemplatePartText",
                A.variant_unique,
            },
            A.variant "TemplateSplicePart" {
                A.field "splice" "MoonHost.TemplateSplice",
                A.variant_unique,
            },
        },

        A.product "HostTemplate" {
            A.field "kind_word" "string",
            A.field "parts" (A.many "MoonHost.TemplatePart"),
            A.unique,
        },

        A.sum "HostStep" {
            A.variant "HostStepLua" {
                A.field "id" "string",
                A.field "source" "MoonSource.SourceSlice",
                A.variant_unique,
            },
            A.variant "HostStepIsland" {
                A.field "id" "string",
                A.field "island" "MoonMlua.IslandText",
                A.field "template" "MoonHost.HostTemplate",
                A.variant_unique,
            },
        },

        A.product "HostProgram" {
            A.field "source" "MoonHost.MluaSource",
            A.field "steps" (A.many "MoonHost.HostStep"),
            A.unique,
        },

        A.product "HostSpliceResult" {
            A.field "splice_id" "string",
            A.field "value" "MoonHost.HostValueRef",
            A.unique,
        },

        A.product "HostEvaluatedTemplate" {
            A.field "template" "MoonHost.HostTemplate",
            A.field "splices" (A.many "MoonHost.HostSpliceResult"),
            A.field "issues" (A.many "MoonHost.HostIssue"),
            A.unique,
        },

        A.product "HostEvalResult" {
            A.field "program" "MoonHost.HostProgram",
            A.field "templates" (A.many "MoonHost.HostEvaluatedTemplate"),
            A.field "report" "MoonHost.HostReport",
            A.unique,
        },

        A.product "ProtocolRole" {
            A.field "role" "string",
            A.field "target" "string",
            A.unique,
        },

        A.product "RegionProtocol" {
            A.field "name" "string",
            A.field "roles" (A.many "MoonHost.ProtocolRole"),
            A.unique,
        },

        A.product "FragmentDeps" {
            A.field "region_frags" (A.many "MoonOpen.RegionFrag"),
            A.field "expr_frags" (A.many "MoonOpen.ExprFrag"),
            A.unique,
        },

        A.product "RegionFragMeta" {
            A.field "name" "string",
            A.field "frag" "MoonOpen.RegionFrag",
            A.field "protocol" (A.optional "MoonHost.RegionProtocol"),
            A.field "deps" "MoonHost.FragmentDeps",
            A.unique,
        },

        A.product "MluaParseResult" {
            A.field "decls" "MoonHost.HostDeclSet",
            A.field "module" "MoonTree.Module",
            A.field "region_frags" (A.many "MoonOpen.RegionFrag"),
            A.field "expr_frags" (A.many "MoonOpen.ExprFrag"),
            A.field "issues" (A.many "MoonParse.ParseIssue"),
            A.unique,
        },

        A.product "MluaHostPipelineResult" {
            A.field "parse" "MoonHost.MluaParseResult",
            A.field "report" "MoonHost.HostReport",
            A.field "layout_env" "MoonHost.HostLayoutEnv",
            A.field "facts" "MoonHost.HostFactSet",
            A.field "lua" "MoonHost.HostLuaFfiPlan",
            A.field "terra" "MoonHost.HostTerraPlan",
            A.field "c" "MoonHost.HostCPlan",
            A.unique,
        },

        A.product "MluaRegionTypeResult" {
            A.field "frag" "MoonOpen.RegionFrag",
            A.field "issues" (A.many "MoonTree.TypeIssue"),
            A.unique,
        },

        A.product "MluaLoopExpandResult" {
            A.field "entry" "MoonTree.EntryControlBlock",
            A.field "blocks" (A.many "MoonTree.ControlBlock"),
            A.field "issues" (A.many "MoonTree.TypeIssue"),
            A.unique,
        },

        A.sum "MluaLoopSource" {
            A.variant "MluaLoopControlStmt" {
                A.field "region" "MoonTree.ControlStmtRegion",
                A.variant_unique,
            },
            A.variant "MluaLoopControlExpr" {
                A.field "region" "MoonTree.ControlExprRegion",
                A.variant_unique,
            },
        },

        A.sum "HostFieldRep" {
            A.variant "HostRepScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "HostRepBool" {
                A.field "encoding" "MoonHost.HostBoolEncoding",
                A.field "storage" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "HostRepPtr" {
                A.field "pointee" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostRepRef" {
                A.field "layout" "MoonHost.HostLayoutId",
                A.variant_unique,
            },
            A.variant "HostRepSlice" {
                A.field "elem" "MoonHost.HostFieldRep",
                A.variant_unique,
            },
            A.variant "HostRepView" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostRepStruct" {
                A.field "layout" "MoonHost.HostLayoutId",
                A.variant_unique,
            },
            A.variant "HostRepOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "HostFieldLayout" {
            A.field "id" "MoonHost.HostFieldId",
            A.field "name" "string",
            A.field "cfield" "string",
            A.field "rep" "MoonHost.HostFieldRep",
            A.field "offset" "number",
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.product "HostTypeLayout" {
            A.field "id" "MoonHost.HostLayoutId",
            A.field "name" "string",
            A.field "ctype" "string",
            A.field "kind" "MoonHost.HostLayoutKind",
            A.field "size" "number",
            A.field "align" "number",
            A.field "fields" (A.many "MoonHost.HostFieldLayout"),
            A.unique,
        },

        A.product "HostLayoutEnv" {
            A.field "layouts" (A.many "MoonHost.HostTypeLayout"),
            A.unique,
        },

        A.product "HostCdef" {
            A.field "layout" "MoonHost.HostLayoutId",
            A.field "source" "string",
            A.unique,
        },

        A.product "HostLuaFfiPlan" {
            A.field "module_name" "string",
            A.field "cdefs" (A.many "MoonHost.HostCdef"),
            A.field "access_plans" (A.many "MoonHost.HostAccessPlan"),
            A.unique,
        },

        A.product "HostTerraPlan" {
            A.field "module_name" "string",
            A.field "source" "string",
            A.field "layouts" (A.many "MoonHost.HostTypeLayout"),
            A.field "views" (A.many "MoonHost.HostViewDescriptor"),
            A.unique,
        },

        A.product "HostCPlan" {
            A.field "header_name" "string",
            A.field "source" "string",
            A.field "layouts" (A.many "MoonHost.HostTypeLayout"),
            A.field "views" (A.many "MoonHost.HostViewDescriptor"),
            A.unique,
        },

        A.sum "HostExportAbi" {
            A.variant "HostExportDescriptorPtr" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostExportExpandedScalars" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.sum "HostExposeSubject" {
            A.variant "HostExposeType" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostExposePtr" {
                A.field "pointee" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "HostExposeView" {
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.sum "HostStrideUnit" {
            A.variant "HostStrideElements",
            A.variant "HostStrideBytes",
        },

        A.sum "HostViewAbi" {
            A.variant "HostViewAbiContiguous" {
                A.field "elem_layout" "MoonHost.HostTypeLayout",
                A.variant_unique,
            },
            A.variant "HostViewAbiStrided" {
                A.field "elem_layout" "MoonHost.HostTypeLayout",
                A.field "stride_unit" "MoonHost.HostStrideUnit",
                A.variant_unique,
            },
        },

        A.product "HostViewDescriptor" {
            A.field "id" "MoonHost.HostLayoutId",
            A.field "name" "string",
            A.field "abi" "MoonHost.HostViewAbi",
            A.field "descriptor_layout" "MoonHost.HostTypeLayout",
            A.unique,
        },

        A.sum "HostExposeTarget" {
            A.variant "HostExposeLua",
            A.variant "HostExposeTerra",
            A.variant "HostExposeC",
            A.variant "HostExposeMoonlift",
        },

        A.sum "HostMutability" {
            A.variant "HostReadonly",
            A.variant "HostMutable",
            A.variant "HostInteriorMutable",
        },

        A.sum "HostBoundsPolicy" {
            A.variant "HostBoundsChecked",
            A.variant "HostBoundsUnchecked",
        },

        A.sum "HostProxyKind" {
            A.variant "HostProxyPtr",
            A.variant "HostProxyView",
            A.variant "HostProxyBufferView",
            A.variant "HostProxyTypedRecord",
            A.variant "HostProxyOpaque",
        },

        A.sum "HostProxyCachePolicy" {
            A.variant "HostProxyCacheNone",
            A.variant "HostProxyCacheLazy",
            A.variant "HostProxyCacheEager",
        },

        A.sum "HostMaterializePolicy" {
            A.variant "HostMaterializeProjectedFields",
            A.variant "HostMaterializeFullCopy",
            A.variant "HostMaterializeBorrowedView",
        },

        A.sum "HostExposeMode" {
            A.variant "HostExposeProxy" {
                A.field "kind" "MoonHost.HostProxyKind",
                A.field "cache" "MoonHost.HostProxyCachePolicy",
                A.field "mutability" "MoonHost.HostMutability",
                A.field "bounds" "MoonHost.HostBoundsPolicy",
                A.variant_unique,
            },
            A.variant "HostExposeEagerTable" {
                A.field "policy" "MoonHost.HostMaterializePolicy",
                A.variant_unique,
            },
            A.variant "HostExposeScalar" {
                A.field "rep" "MoonHost.HostFieldRep",
                A.variant_unique,
            },
            A.variant "HostExposeOpaque" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "HostExposeAbi" {
            A.variant "HostExposeAbiDefault",
            A.variant "HostExposeAbiPointer",
            A.variant "HostExposeAbiDescriptor",
            A.variant "HostExposeAbiDataLenStride",
            A.variant "HostExposeAbiExpandedScalars",
            A.variant "HostExposeAbiOpaque" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "HostExposeFacet" {
            A.field "target" "MoonHost.HostExposeTarget",
            A.field "abi" "MoonHost.HostExposeAbi",
            A.field "mode" "MoonHost.HostExposeMode",
            A.unique,
        },

        A.product "HostExposeDecl" {
            A.field "subject" "MoonHost.HostExposeSubject",
            A.field "public_name" "string",
            A.field "facets" (A.many "MoonHost.HostExposeFacet"),
            A.unique,
        },

        A.sum "HostLifetime" {
            A.variant "HostLifetimeStatic",
            A.variant "HostLifetimeOwned",
            A.variant "HostLifetimeBorrowed" {
                A.field "owner_name" "string",
                A.variant_unique,
            },
            A.variant "HostLifetimeGeneration" {
                A.field "session_id" "number",
                A.field "generation" "number",
                A.variant_unique,
            },
            A.variant "HostLifetimeExternal" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "HostAccessSubject" {
            A.variant "HostAccessRecord" {
                A.field "layout" "MoonHost.HostTypeLayout",
                A.variant_unique,
            },
            A.variant "HostAccessPtr" {
                A.field "layout" "MoonHost.HostTypeLayout",
                A.variant_unique,
            },
            A.variant "HostAccessView" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
        },

        A.sum "HostAccessKey" {
            A.variant "HostAccessField" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "HostAccessIndex",
            A.variant "HostAccessLen",
            A.variant "HostAccessData",
            A.variant "HostAccessStride",
            A.variant "HostAccessMethod" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "HostAccessPairs",
            A.variant "HostAccessIpairs",
            A.variant "HostAccessToTable",
        },

        A.sum "HostAccessOp" {
            A.variant "HostAccessDirectField" {
                A.field "field" "MoonHost.HostFieldLayout",
                A.variant_unique,
            },
            A.variant "HostAccessDecodeBool" {
                A.field "field" "MoonHost.HostFieldLayout",
                A.variant_unique,
            },
            A.variant "HostAccessEncodeBool" {
                A.field "field" "MoonHost.HostFieldLayout",
                A.variant_unique,
            },
            A.variant "HostAccessViewIndex" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostAccessViewFieldAt" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.field "field" "MoonHost.HostFieldLayout",
                A.variant_unique,
            },
            A.variant "HostAccessViewLen" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostAccessViewData" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostAccessViewStride" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostAccessPointerCast" {
                A.field "layout" "MoonHost.HostTypeLayout",
                A.variant_unique,
            },
            A.variant "HostAccessIterateFields" {
                A.field "layout" "MoonHost.HostLayoutId",
                A.variant_unique,
            },
            A.variant "HostAccessMaterializeTable" {
                A.field "subject" "MoonHost.HostAccessSubject",
                A.variant_unique,
            },
            A.variant "HostAccessReject" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "HostAccessEntry" {
            A.field "key" "MoonHost.HostAccessKey",
            A.field "op" "MoonHost.HostAccessOp",
            A.unique,
        },

        A.product "HostAccessPlan" {
            A.field "subject" "MoonHost.HostAccessSubject",
            A.field "entries" (A.many "MoonHost.HostAccessEntry"),
            A.unique,
        },

        A.product "HostViewPlan" {
            A.field "layout" "MoonHost.HostTypeLayout",
            A.field "owner" "MoonHost.HostOwner",
            A.field "expose" "MoonHost.HostExposeMode",
            A.field "access" "MoonHost.HostAccessPlan",
            A.unique,
        },

        A.sum "HostProducerKind" {
            A.variant "HostProducerLowLevelMoonlift",
            A.variant "HostProducerLuaFfi",
            A.variant "HostProducerRustTypedRecordMemory",
            A.variant "HostProducerExternal",
        },

        A.product "HostProducerPlan" {
            A.field "name" "string",
            A.field "kind" "MoonHost.HostProducerKind",
            A.field "outputs" (A.many "MoonHost.HostTypeLayout"),
            A.unique,
        },

        A.sum "HostLayoutFact" {
            A.variant "HostFactTypeLayout" {
                A.field "layout" "MoonHost.HostTypeLayout",
                A.variant_unique,
            },
            A.variant "HostFactCdef" {
                A.field "cdef" "MoonHost.HostCdef",
                A.variant_unique,
            },
            A.variant "HostFactField" {
                A.field "owner" "MoonHost.HostLayoutId",
                A.field "field" "MoonHost.HostFieldLayout",
                A.variant_unique,
            },
            A.variant "HostFactViewDescriptor" {
                A.field "descriptor" "MoonHost.HostViewDescriptor",
                A.variant_unique,
            },
            A.variant "HostFactExpose" {
                A.field "public_name" "string",
                A.field "layout" "MoonHost.HostLayoutId",
                A.field "facet" "MoonHost.HostExposeFacet",
                A.variant_unique,
            },
            A.variant "HostFactAccessPlan" {
                A.field "plan" "MoonHost.HostAccessPlan",
                A.variant_unique,
            },
            A.variant "HostFactViewPlan" {
                A.field "plan" "MoonHost.HostViewPlan",
                A.variant_unique,
            },
            A.variant "HostFactLuaFfi" {
                A.field "plan" "MoonHost.HostLuaFfiPlan",
                A.variant_unique,
            },
            A.variant "HostFactTerra" {
                A.field "plan" "MoonHost.HostTerraPlan",
                A.variant_unique,
            },
            A.variant "HostFactC" {
                A.field "plan" "MoonHost.HostCPlan",
                A.variant_unique,
            },
            A.variant "HostFactProducer" {
                A.field "plan" "MoonHost.HostProducerPlan",
                A.variant_unique,
            },
        },

        A.product "HostFactSet" {
            A.field "facts" (A.many "MoonHost.HostLayoutFact"),
            A.unique,
        },

        A.sum "HostLayoutReject" {
            A.variant "HostRejectJsonInRust",
            A.variant "HostRejectDynamicObjectArena" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "HostRejectUnknownFieldKind" {
                A.field "kind" "string",
                A.variant_unique,
            },
            A.variant "HostRejectInvalidLayout" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "HostRejectBareBoolInBoundaryStruct" {
                A.field "type_name" "string",
                A.field "field_name" "string",
                A.variant_unique,
            },
            A.variant "HostRejectInvalidPackedAlign" {
                A.field "type_name" "string",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "HostRejectConflictingCdef" {
                A.field "layout" "MoonHost.HostLayoutId",
                A.variant_unique,
            },
        },
    }
end
