-- Clean MoonSource schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonSource" {
        A.product "DocUri" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DocVersion" {
            A.field "value" "number",
            A.unique,
        },

        A.sum "LanguageId" {
            A.variant "LangMlua",
            A.variant "LangMoonlift",
            A.variant "LangLua",
            A.variant "LangUnknown" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "DocumentSnapshot" {
            A.field "uri" "MoonSource.DocUri",
            A.field "version" "MoonSource.DocVersion",
            A.field "language" "MoonSource.LanguageId",
            A.field "text" "string",
            A.unique,
        },

        A.sum "PositionEncoding" {
            A.variant "PosUtf8Bytes",
            A.variant "PosUtf16CodeUnits",
            A.variant "PosUtf32Codepoints",
        },

        A.product "SourcePos" {
            A.field "line" "number",
            A.field "byte_col" "number",
            A.field "utf16_col" "number",
            A.unique,
        },

        A.product "SourceRange" {
            A.field "uri" "MoonSource.DocUri",
            A.field "start_offset" "number",
            A.field "stop_offset" "number",
            A.field "start" "MoonSource.SourcePos",
            A.field "stop" "MoonSource.SourcePos",
            A.unique,
        },

        A.sum "TextChange" {
            A.variant "ReplaceAll" {
                A.field "text" "string",
                A.variant_unique,
            },
            A.variant "ReplaceRange" {
                A.field "range" "MoonSource.SourceRange",
                A.field "text" "string",
                A.variant_unique,
            },
        },

        A.product "DocumentEdit" {
            A.field "uri" "MoonSource.DocUri",
            A.field "version" "MoonSource.DocVersion",
            A.field "changes" (A.many "MoonSource.TextChange"),
            A.unique,
        },

        A.product "SourceSlice" {
            A.field "text" "string",
            A.unique,
        },

        A.product "SourceOccurrence" {
            A.field "slice" "MoonSource.SourceSlice",
            A.field "range" "MoonSource.SourceRange",
            A.unique,
        },

        A.product "AnchorId" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "AnchorKind" {
            A.variant "AnchorDocument",
            A.variant "AnchorLuaOpaque",
            A.variant "AnchorHostedIsland",
            A.variant "AnchorIslandBody",
            A.variant "AnchorKeyword",
            A.variant "AnchorScalarType",
            A.variant "AnchorStructName",
            A.variant "AnchorFieldName",
            A.variant "AnchorFieldUse",
            A.variant "AnchorFunctionName",
            A.variant "AnchorFunctionUse",
            A.variant "AnchorMethodName",
            A.variant "AnchorParamName",
            A.variant "AnchorLocalName",
            A.variant "AnchorBindingDef",
            A.variant "AnchorBindingUse",
            A.variant "AnchorRegionName",
            A.variant "AnchorExprName",
            A.variant "AnchorContinuationName",
            A.variant "AnchorContinuationUse",
            A.variant "AnchorBuiltinName",
            A.variant "AnchorPackedAlign",
            A.variant "AnchorDiagnostic",
            A.variant "AnchorExposeName",
            A.variant "AnchorModuleName",
            A.variant "AnchorOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "Anchor" {
            A.field "id" "MoonSource.AnchorId",
            A.field "kind" "MoonSource.AnchorKind",
            A.field "label" "string",
            A.unique,
        },

        A.product "AnchorSpan" {
            A.field "id" "MoonSource.AnchorId",
            A.field "kind" "MoonSource.AnchorKind",
            A.field "label" "string",
            A.field "range" "MoonSource.SourceRange",
            A.unique,
        },

        A.product "AnchorSet" {
            A.field "anchors" (A.many "MoonSource.AnchorSpan"),
            A.unique,
        },

        A.product "SourceLineSpan" {
            A.field "line" "number",
            A.field "start_offset" "number",
            A.field "stop_offset" "number",
            A.field "next_offset" "number",
            A.unique,
        },

        A.product "PositionIndex" {
            A.field "document" "MoonSource.DocumentSnapshot",
            A.field "lines" (A.many "MoonSource.SourceLineSpan"),
            A.unique,
        },

        A.sum "SourceApplyIssue" {
            A.variant "SourceIssueWrongDocument" {
                A.field "expected" "MoonSource.DocUri",
                A.field "actual" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "SourceIssueStaleVersion" {
                A.field "expected_after" "MoonSource.DocVersion",
                A.field "actual" "MoonSource.DocVersion",
                A.variant_unique,
            },
            A.variant "SourceIssueInvalidRange" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "SourceIssueOverlappingRanges" {
                A.field "previous" "MoonSource.SourceRange",
                A.field "current" "MoonSource.SourceRange",
                A.variant_unique,
            },
            A.variant "SourceIssueMixedReplaceAll",
        },

        A.sum "SourceApplyResult" {
            A.variant "SourceApplyOk" {
                A.field "document" "MoonSource.DocumentSnapshot",
                A.variant_unique,
            },
            A.variant "SourceApplyRejected" {
                A.field "document" "MoonSource.DocumentSnapshot",
                A.field "issues" (A.many "MoonSource.SourceApplyIssue"),
                A.variant_unique,
            },
        },

        A.sum "SourcePositionResult" {
            A.variant "SourcePositionHit" {
                A.field "pos" "MoonSource.SourcePos",
                A.variant_unique,
            },
            A.variant "SourcePositionMiss" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "SourceOffsetResult" {
            A.variant "SourceOffsetHit" {
                A.field "offset" "number",
                A.variant_unique,
            },
            A.variant "SourceOffsetMiss" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "AnchorIndex" {
            A.field "set" "MoonSource.AnchorSet",
            A.field "anchors" (A.many "MoonSource.AnchorSpan"),
            A.unique,
        },

        A.sum "AnchorQuery" {
            A.variant "AnchorQueryPosition" {
                A.field "index" "MoonSource.AnchorIndex",
                A.field "uri" "MoonSource.DocUri",
                A.field "offset" "number",
                A.variant_unique,
            },
            A.variant "AnchorQueryRange" {
                A.field "index" "MoonSource.AnchorIndex",
                A.field "range" "MoonSource.SourceRange",
                A.variant_unique,
            },
            A.variant "AnchorQueryId" {
                A.field "index" "MoonSource.AnchorIndex",
                A.field "id" "MoonSource.AnchorId",
                A.variant_unique,
            },
        },

        A.sum "AnchorLookupResult" {
            A.variant "AnchorLookup" {
                A.field "anchors" (A.many "MoonSource.AnchorSpan"),
                A.variant_unique,
            },
        },
    }
end
