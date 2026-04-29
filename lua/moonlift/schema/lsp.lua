-- Clean MoonLsp schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonLsp" {
        A.product "ProtocolPosition" {
            A.field "line" "number",
            A.field "character" "number",
            A.unique,
        },

        A.product "ProtocolRange" {
            A.field "start" "MoonLsp.ProtocolPosition",
            A.field "stop" "MoonLsp.ProtocolPosition",
            A.unique,
        },

        A.product "Location" {
            A.field "uri" "MoonSource.DocUri",
            A.field "range" "MoonLsp.ProtocolRange",
            A.unique,
        },

        A.product "InitializeResult" {
            A.field "server_name" "string",
            A.field "position_encoding" "string",
            A.field "capabilities_json" "string",
            A.unique,
        },

        A.product "DiagnosticPayload" {
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "severity" "number",
            A.field "code" "string",
            A.field "message" "string",
            A.unique,
        },

        A.product "DiagnosticReport" {
            A.field "uri" "MoonSource.DocUri",
            A.field "version" "MoonSource.DocVersion",
            A.field "diagnostics" (A.many "MoonLsp.DiagnosticPayload"),
            A.unique,
        },

        A.product "DiagnosticDocumentReport" {
            A.field "kind" "string",
            A.field "items" (A.many "MoonLsp.DiagnosticPayload"),
            A.unique,
        },

        A.sum "Hover" {
            A.variant "Hover" {
                A.field "kind" "MoonEditor.MarkupKind",
                A.field "value" "string",
                A.field "range" "MoonLsp.ProtocolRange",
                A.variant_unique,
            },
            A.variant "HoverNull",
        },

        A.product "CompletionPayload" {
            A.field "label" "string",
            A.field "kind" "number",
            A.field "detail" "string",
            A.field "documentation" "string",
            A.field "insert_text" "string",
            A.unique,
        },

        A.product "CompletionList" {
            A.field "incomplete" "boolean",
            A.field "items" (A.many "MoonLsp.CompletionPayload"),
            A.unique,
        },

        A.product "DocumentSymbolPayload" {
            A.field "name" "string",
            A.field "detail" "string",
            A.field "kind" "number",
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "selection_range" "MoonLsp.ProtocolRange",
            A.field "children" (A.many "MoonLsp.DocumentSymbolPayload"),
            A.unique,
        },

        A.product "WorkspaceSymbolPayload" {
            A.field "name" "string",
            A.field "detail" "string",
            A.field "kind" "number",
            A.field "location" "MoonLsp.Location",
            A.field "container_name" "string",
            A.unique,
        },

        A.product "SignatureParameterPayload" {
            A.field "label" "string",
            A.field "documentation" "string",
            A.unique,
        },

        A.product "SignatureInformationPayload" {
            A.field "label" "string",
            A.field "documentation" "string",
            A.field "params" (A.many "MoonLsp.SignatureParameterPayload"),
            A.unique,
        },

        A.product "SignatureHelpPayload" {
            A.field "signatures" (A.many "MoonLsp.SignatureInformationPayload"),
            A.field "active_signature" "number",
            A.field "active_parameter" "number",
            A.unique,
        },

        A.product "SemanticTokens" {
            A.field "data" (A.many "number"),
            A.unique,
        },

        A.product "DocumentHighlightPayload" {
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "kind" "number",
            A.unique,
        },

        A.product "PrepareRenamePayload" {
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "placeholder" "string",
            A.unique,
        },

        A.product "TextEditPayload" {
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "new_text" "string",
            A.unique,
        },

        A.product "WorkspaceEditPayload" {
            A.field "uri" "MoonSource.DocUri",
            A.field "edits" (A.many "MoonLsp.TextEditPayload"),
            A.unique,
        },

        A.product "CodeActionPayload" {
            A.field "title" "string",
            A.field "kind" "string",
            A.field "diagnostics" (A.many "MoonLsp.DiagnosticPayload"),
            A.field "edits" (A.many "MoonLsp.WorkspaceEditPayload"),
            A.unique,
        },

        A.product "FoldingRangePayload" {
            A.field "start_line" "number",
            A.field "start_character" "number",
            A.field "end_line" "number",
            A.field "end_character" "number",
            A.field "kind" "string",
            A.unique,
        },

        A.product "SelectionRangePayload" {
            A.field "range" "MoonLsp.ProtocolRange",
            A.field "parents" (A.many "MoonLsp.SelectionRangePayload"),
            A.unique,
        },

        A.product "InlayHintPayload" {
            A.field "position" "MoonLsp.ProtocolPosition",
            A.field "label" "string",
            A.field "kind" "string",
            A.unique,
        },

        A.sum "Payload" {
            A.variant "PayloadNull",
            A.variant "PayloadInitialize" {
                A.field "result" "MoonLsp.InitializeResult",
                A.variant_unique,
            },
            A.variant "PayloadDiagnostics" {
                A.field "report" "MoonLsp.DiagnosticReport",
                A.variant_unique,
            },
            A.variant "PayloadDiagnosticDocumentReport" {
                A.field "report" "MoonLsp.DiagnosticDocumentReport",
                A.variant_unique,
            },
            A.variant "PayloadHover" {
                A.field "hover" "MoonLsp.Hover",
                A.variant_unique,
            },
            A.variant "PayloadCompletion" {
                A.field "completion" "MoonLsp.CompletionList",
                A.variant_unique,
            },
            A.variant "PayloadDocumentSymbols" {
                A.field "symbols" (A.many "MoonLsp.DocumentSymbolPayload"),
                A.variant_unique,
            },
            A.variant "PayloadWorkspaceSymbols" {
                A.field "symbols" (A.many "MoonLsp.WorkspaceSymbolPayload"),
                A.variant_unique,
            },
            A.variant "PayloadSignatureHelp" {
                A.field "help" "MoonLsp.SignatureHelpPayload",
                A.variant_unique,
            },
            A.variant "PayloadLocations" {
                A.field "locations" (A.many "MoonLsp.Location"),
                A.variant_unique,
            },
            A.variant "PayloadDocumentHighlights" {
                A.field "highlights" (A.many "MoonLsp.DocumentHighlightPayload"),
                A.variant_unique,
            },
            A.variant "PayloadPrepareRename" {
                A.field "result" "MoonLsp.PrepareRenamePayload",
                A.variant_unique,
            },
            A.variant "PayloadSemanticTokens" {
                A.field "tokens" "MoonLsp.SemanticTokens",
                A.variant_unique,
            },
            A.variant "PayloadWorkspaceEdit" {
                A.field "edits" (A.many "MoonLsp.WorkspaceEditPayload"),
                A.variant_unique,
            },
            A.variant "PayloadCodeActions" {
                A.field "actions" (A.many "MoonLsp.CodeActionPayload"),
                A.variant_unique,
            },
            A.variant "PayloadFoldingRanges" {
                A.field "ranges" (A.many "MoonLsp.FoldingRangePayload"),
                A.variant_unique,
            },
            A.variant "PayloadSelectionRanges" {
                A.field "ranges" (A.many "MoonLsp.SelectionRangePayload"),
                A.variant_unique,
            },
            A.variant "PayloadInlayHints" {
                A.field "hints" (A.many "MoonLsp.InlayHintPayload"),
                A.variant_unique,
            },
            A.variant "PayloadError" {
                A.field "code" "string",
                A.field "message" "string",
                A.variant_unique,
            },
        },
    }
end
