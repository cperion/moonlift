-- Clean MoonMlua schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonMlua" {
        A.sum "IslandKind" {
            A.variant "IslandStruct",
            A.variant "IslandExpose",
            A.variant "IslandFunc",
            A.variant "IslandModule",
            A.variant "IslandRegion",
            A.variant "IslandExpr",
        },

        A.sum "IslandName" {
            A.variant "IslandNamed" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "IslandAnonymous",
            A.variant "IslandMalformedName" {
                A.field "text" "string",
                A.variant_unique,
            },
        },

        A.product "IslandText" {
            A.field "kind" "MoonMlua.IslandKind",
            A.field "name" "MoonMlua.IslandName",
            A.field "source" "MoonSource.SourceSlice",
            A.unique,
        },

        A.sum "Segment" {
            A.variant "LuaOpaque" {
                A.field "occurrence" "MoonSource.SourceOccurrence",
                A.variant_unique,
            },
            A.variant "HostedIsland" {
                A.field "island" "MoonMlua.IslandText",
                A.field "range" "MoonSource.SourceRange",
                A.variant_unique,
            },
            A.variant "MalformedIsland" {
                A.field "kind" "MoonMlua.IslandKind",
                A.field "occurrence" "MoonSource.SourceOccurrence",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "DocumentParts" {
            A.field "document" "MoonSource.DocumentSnapshot",
            A.field "segments" (A.many "MoonMlua.Segment"),
            A.field "anchors" "MoonSource.AnchorSet",
            A.unique,
        },

        A.product "IslandParse" {
            A.field "island" "MoonMlua.IslandText",
            A.field "decls" "MoonHost.HostDeclSet",
            A.field "module" "MoonTree.Module",
            A.field "region_frags" (A.many "MoonOpen.RegionFrag"),
            A.field "expr_frags" (A.many "MoonOpen.ExprFrag"),
            A.field "issues" (A.many "MoonParse.ParseIssue"),
            A.field "anchors" "MoonSource.AnchorSet",
            A.unique,
        },

        A.product "DocumentParse" {
            A.field "parts" "MoonMlua.DocumentParts",
            A.field "combined" "MoonHost.MluaParseResult",
            A.field "islands" (A.many "MoonMlua.IslandParse"),
            A.field "anchors" "MoonSource.AnchorSet",
            A.unique,
        },

        A.product "DocumentAnalysis" {
            A.field "parse" "MoonMlua.DocumentParse",
            A.field "host" "MoonHost.MluaHostPipelineResult",
            A.field "open_report" "MoonOpen.ValidationReport",
            A.field "type_issues" (A.many "MoonTree.TypeIssue"),
            A.field "control_facts" (A.many "MoonTree.ControlFact"),
            A.field "vector_decisions" (A.many "MoonVec.VecLoopDecision"),
            A.field "vector_rejects" (A.many "MoonVec.VecReject"),
            A.field "back_report" "MoonBack.BackValidationReport",
            A.field "anchors" "MoonSource.AnchorSet",
            A.unique,
        },
    }
end
