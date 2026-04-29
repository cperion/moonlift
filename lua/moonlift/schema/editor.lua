-- Clean MoonEditor schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonEditor" {
        A.sum "ServerMode" {
            A.variant "ServerCreated",
            A.variant "ServerInitializing",
            A.variant "ServerReady",
            A.variant "ServerShutdownRequested",
            A.variant "ServerStopped",
        },

        A.sum "ClientCapability" {
            A.variant "ClientCapability" {
                A.field "name" "string",
                A.field "value" "string",
                A.variant_unique,
            },
        },

        A.product "WorkspaceRoot" {
            A.field "uri" "MoonSource.DocUri",
            A.unique,
        },

        A.product "WorkspaceState" {
            A.field "mode" "MoonEditor.ServerMode",
            A.field "roots" (A.many "MoonEditor.WorkspaceRoot"),
            A.field "capabilities" (A.many "MoonEditor.ClientCapability"),
            A.field "open_docs" (A.many "MoonSource.DocumentSnapshot"),
            A.unique,
        },

        A.sum "RpcId" {
            A.variant "RpcIdNone",
            A.variant "RpcIdNumber" {
                A.field "value" "number",
                A.variant_unique,
            },
            A.variant "RpcIdString" {
                A.field "value" "string",
                A.variant_unique,
            },
        },

        A.product "PositionQuery" {
            A.field "uri" "MoonSource.DocUri",
            A.field "version" "MoonSource.DocVersion",
            A.field "pos" "MoonSource.SourcePos",
            A.unique,
        },

        A.product "RangeQuery" {
            A.field "uri" "MoonSource.DocUri",
            A.field "version" "MoonSource.DocVersion",
            A.field "range" "MoonSource.SourceRange",
            A.unique,
        },

        A.product "ReferenceQuery" {
            A.field "position" "MoonEditor.PositionQuery",
            A.field "include_declaration" "boolean",
            A.unique,
        },

        A.product "RenameQuery" {
            A.field "position" "MoonEditor.PositionQuery",
            A.field "new_name" "string",
            A.unique,
        },

        A.product "CodeActionQuery" {
            A.field "range" "MoonEditor.RangeQuery",
            A.field "diagnostics" (A.many "MoonEditor.DiagnosticFact"),
            A.unique,
        },

        A.sum "ClientEvent" {
            A.variant "ClientInitialize" {
                A.field "id" "MoonEditor.RpcId",
                A.field "roots" (A.many "MoonEditor.WorkspaceRoot"),
                A.field "capabilities" (A.many "MoonEditor.ClientCapability"),
                A.variant_unique,
            },
            A.variant "ClientInitialized",
            A.variant "ClientShutdown" {
                A.field "id" "MoonEditor.RpcId",
                A.variant_unique,
            },
            A.variant "ClientExit",
            A.variant "ClientDidOpen" {
                A.field "document" "MoonSource.DocumentSnapshot",
                A.variant_unique,
            },
            A.variant "ClientDidChange" {
                A.field "edit" "MoonSource.DocumentEdit",
                A.variant_unique,
            },
            A.variant "ClientDidClose" {
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientDidSave" {
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientHover" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientDefinition" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientReferences" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.ReferenceQuery",
                A.variant_unique,
            },
            A.variant "ClientDocumentHighlight" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientDocumentSymbol" {
                A.field "id" "MoonEditor.RpcId",
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientWorkspaceSymbol" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "string",
                A.variant_unique,
            },
            A.variant "ClientDiagnostic" {
                A.field "id" "MoonEditor.RpcId",
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientCompletion" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientSignatureHelp" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientSemanticTokensFull" {
                A.field "id" "MoonEditor.RpcId",
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientSemanticTokensRange" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.RangeQuery",
                A.variant_unique,
            },
            A.variant "ClientPrepareRename" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.PositionQuery",
                A.variant_unique,
            },
            A.variant "ClientRename" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.RenameQuery",
                A.variant_unique,
            },
            A.variant "ClientCodeAction" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.CodeActionQuery",
                A.variant_unique,
            },
            A.variant "ClientFoldingRange" {
                A.field "id" "MoonEditor.RpcId",
                A.field "uri" "MoonSource.DocUri",
                A.variant_unique,
            },
            A.variant "ClientSelectionRange" {
                A.field "id" "MoonEditor.RpcId",
                A.field "positions" (A.many "MoonEditor.PositionQuery"),
                A.variant_unique,
            },
            A.variant "ClientInlayHint" {
                A.field "id" "MoonEditor.RpcId",
                A.field "query" "MoonEditor.RangeQuery",
                A.variant_unique,
            },
            A.variant "ClientUnsupported" {
                A.field "id" "MoonEditor.RpcId",
                A.field "method" "string",
                A.variant_unique,
            },
            A.variant "ClientIgnoredNotification" {
                A.field "method" "string",
                A.variant_unique,
            },
        },

        A.product "Transition" {
            A.field "before" "MoonEditor.WorkspaceState",
            A.field "event" "MoonEditor.ClientEvent",
            A.field "after" "MoonEditor.WorkspaceState",
            A.unique,
        },

        A.sum "DiagnosticSeverity" {
            A.variant "DiagnosticError",
            A.variant "DiagnosticWarning",
            A.variant "DiagnosticInformation",
            A.variant "DiagnosticHint",
        },

        A.sum "DiagnosticOrigin" {
            A.variant "DiagFromParse" {
                A.field "issue" "MoonParse.ParseIssue",
                A.variant_unique,
            },
            A.variant "DiagFromHost" {
                A.field "issue" "MoonHost.HostIssue",
                A.variant_unique,
            },
            A.variant "DiagFromOpen" {
                A.field "issue" "MoonOpen.ValidationIssue",
                A.variant_unique,
            },
            A.variant "DiagFromType" {
                A.field "issue" "MoonTree.TypeIssue",
                A.variant_unique,
            },
            A.variant "DiagFromBack" {
                A.field "issue" "MoonBack.BackValidationIssue",
                A.variant_unique,
            },
            A.variant "DiagFromVectorReject" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
            A.variant "DiagFromBindingResolution" {
                A.field "resolution" "MoonEditor.BindingResolution",
                A.variant_unique,
            },
            A.variant "DiagFromSource" {
                A.field "issue" "MoonSource.SourceApplyIssue",
                A.variant_unique,
            },
            A.variant "DiagFromTransport" {
                A.field "code" "string",
                A.field "message" "string",
                A.variant_unique,
            },
        },

        A.product "DiagnosticFact" {
            A.field "severity" "MoonEditor.DiagnosticSeverity",
            A.field "origin" "MoonEditor.DiagnosticOrigin",
            A.field "code" "string",
            A.field "message" "string",
            A.field "range" "MoonSource.SourceRange",
            A.unique,
        },

        A.sum "Subject" {
            A.variant "SubjectKeyword" {
                A.field "text" "string",
                A.variant_unique,
            },
            A.variant "SubjectScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "SubjectType" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "SubjectHostStruct" {
                A.field "decl" "MoonHost.HostStructDecl",
                A.variant_unique,
            },
            A.variant "SubjectHostField" {
                A.field "owner" "MoonHost.HostStructDecl",
                A.field "field" "MoonHost.HostFieldDecl",
                A.variant_unique,
            },
            A.variant "SubjectHostExpose" {
                A.field "decl" "MoonHost.HostExposeDecl",
                A.variant_unique,
            },
            A.variant "SubjectHostAccessor" {
                A.field "decl" "MoonHost.HostAccessorDecl",
                A.variant_unique,
            },
            A.variant "SubjectTreeFunc" {
                A.field "func" "MoonTree.Func",
                A.variant_unique,
            },
            A.variant "SubjectTreeModule" {
                A.field "module" "MoonTree.Module",
                A.variant_unique,
            },
            A.variant "SubjectRegionFrag" {
                A.field "frag" "MoonOpen.RegionFrag",
                A.variant_unique,
            },
            A.variant "SubjectExprFrag" {
                A.field "frag" "MoonOpen.ExprFrag",
                A.variant_unique,
            },
            A.variant "SubjectBinding" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "SubjectContinuation" {
                A.field "scope" "MoonSource.AnchorId",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "SubjectBuiltin" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "SubjectDiagnostic" {
                A.field "diagnostic" "MoonEditor.DiagnosticFact",
                A.variant_unique,
            },
            A.variant "SubjectMissing" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "SubjectPick" {
            A.field "query" "MoonEditor.PositionQuery",
            A.field "anchors" (A.many "MoonSource.AnchorSpan"),
            A.field "subject" "MoonEditor.Subject",
            A.unique,
        },

        A.sum "SymbolKind" {
            A.variant "SymFile",
            A.variant "SymModule",
            A.variant "SymNamespace",
            A.variant "SymPackage",
            A.variant "SymClass",
            A.variant "SymMethod",
            A.variant "SymProperty",
            A.variant "SymField",
            A.variant "SymConstructor",
            A.variant "SymEnum",
            A.variant "SymInterface",
            A.variant "SymFunction",
            A.variant "SymVariable",
            A.variant "SymConstant",
            A.variant "SymString",
            A.variant "SymNumber",
            A.variant "SymBoolean",
            A.variant "SymArray",
            A.variant "SymObject",
            A.variant "SymKey",
            A.variant "SymNull",
            A.variant "SymEnumMember",
            A.variant "SymStruct",
            A.variant "SymEvent",
            A.variant "SymOperator",
            A.variant "SymTypeParameter",
        },

        A.product "SymbolId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "SymbolFact" {
            A.field "id" "MoonEditor.SymbolId",
            A.field "parent" "MoonEditor.SymbolId",
            A.field "name" "string",
            A.field "kind" "MoonEditor.SymbolKind",
            A.field "detail" "string",
            A.field "range" "MoonSource.SourceRange",
            A.field "selection_range" "MoonSource.SourceRange",
            A.field "subject" "MoonEditor.Subject",
            A.unique,
        },

        A.product "SymbolTree" {
            A.field "symbols" (A.many "MoonEditor.SymbolFact"),
            A.unique,
        },

        A.sum "BindingRole" {
            A.variant "BindingDef",
            A.variant "BindingUse",
            A.variant "BindingRead",
            A.variant "BindingWrite",
            A.variant "BindingCall",
            A.variant "BindingTypeUse",
        },

        A.product "BindingScopeId" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "BindingScopeKind" {
            A.variant "BindingScopeDocument",
            A.variant "BindingScopeIsland",
            A.variant "BindingScopeFunction",
            A.variant "BindingScopeRegion",
            A.variant "BindingScopeExpr",
            A.variant "BindingScopeControlBlock",
            A.variant "BindingScopeBranch",
            A.variant "BindingScopeModule",
            A.variant "BindingScopeOpaque" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "BindingScopeFact" {
            A.field "id" "MoonEditor.BindingScopeId",
            A.field "parent" "MoonEditor.BindingScopeId",
            A.field "kind" "MoonEditor.BindingScopeKind",
            A.field "range" "MoonSource.SourceRange",
            A.unique,
        },

        A.product "ScopedBinding" {
            A.field "binding" "MoonBind.Binding",
            A.field "scope" "MoonEditor.BindingScopeId",
            A.field "visible_range" "MoonSource.SourceRange",
            A.field "anchor" "MoonSource.AnchorSpan",
            A.unique,
        },

        A.product "BindingUseSite" {
            A.field "anchor" "MoonSource.AnchorSpan",
            A.field "role" "MoonEditor.BindingRole",
            A.field "scope" "MoonEditor.BindingScopeId",
            A.unique,
        },

        A.sum "BindingResolution" {
            A.variant "BindingResolved" {
                A.field "use" "MoonEditor.BindingUseSite",
                A.field "binding" "MoonEditor.ScopedBinding",
                A.variant_unique,
            },
            A.variant "BindingUnresolved" {
                A.field "use" "MoonEditor.BindingUseSite",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "BindingScopeReport" {
            A.field "scopes" (A.many "MoonEditor.BindingScopeFact"),
            A.field "bindings" (A.many "MoonEditor.ScopedBinding"),
            A.field "resolutions" (A.many "MoonEditor.BindingResolution"),
            A.unique,
        },

        A.product "BindingFact" {
            A.field "id" "MoonEditor.SymbolId",
            A.field "role" "MoonEditor.BindingRole",
            A.field "subject" "MoonEditor.Subject",
            A.field "anchor" "MoonSource.AnchorSpan",
            A.unique,
        },

        A.sum "DefinitionResult" {
            A.variant "DefinitionHit" {
                A.field "subject" "MoonEditor.Subject",
                A.field "ranges" (A.many "MoonSource.SourceRange"),
                A.variant_unique,
            },
            A.variant "DefinitionMiss" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "ReferenceResult" {
            A.variant "ReferenceHit" {
                A.field "subject" "MoonEditor.Subject",
                A.field "ranges" (A.many "MoonSource.SourceRange"),
                A.variant_unique,
            },
            A.variant "ReferenceMiss" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "DocumentHighlightKind" {
            A.variant "HighlightText",
            A.variant "HighlightRead",
            A.variant "HighlightWrite",
        },

        A.product "DocumentHighlight" {
            A.field "range" "MoonSource.SourceRange",
            A.field "kind" "MoonEditor.DocumentHighlightKind",
            A.unique,
        },

        A.product "RenameEdit" {
            A.field "range" "MoonSource.SourceRange",
            A.field "new_text" "string",
            A.unique,
        },

        A.sum "RenameResult" {
            A.variant "RenameOk" {
                A.field "edits" (A.many "MoonEditor.RenameEdit"),
                A.variant_unique,
            },
            A.variant "RenameRejected" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "PrepareRenameResult" {
            A.variant "PrepareRenameOk" {
                A.field "range" "MoonSource.SourceRange",
                A.field "placeholder" "string",
                A.variant_unique,
            },
            A.variant "PrepareRenameRejected" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "MarkupKind" {
            A.variant "MarkupPlainText",
            A.variant "MarkupMarkdown",
        },

        A.sum "HoverInfo" {
            A.variant "HoverInfo" {
                A.field "kind" "MoonEditor.MarkupKind",
                A.field "value" "string",
                A.field "range" "MoonSource.SourceRange",
                A.variant_unique,
            },
            A.variant "HoverMissing" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "CompletionContext" {
            A.variant "CompletionTopLevel",
            A.variant "CompletionModuleItem",
            A.variant "CompletionStructField",
            A.variant "CompletionTypePosition",
            A.variant "CompletionExprPosition",
            A.variant "CompletionPlacePosition",
            A.variant "CompletionExposeSubject",
            A.variant "CompletionExposeTarget",
            A.variant "CompletionExposeMode",
            A.variant "CompletionRegionStatement",
            A.variant "CompletionContinuationArgs",
            A.variant "CompletionBuiltinPath",
            A.variant "CompletionLuaOpaque",
            A.variant "CompletionInvalid" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "CompletionKind" {
            A.variant "CompletionText",
            A.variant "CompletionMethod",
            A.variant "CompletionFunction",
            A.variant "CompletionConstructor",
            A.variant "CompletionField",
            A.variant "CompletionVariable",
            A.variant "CompletionClass",
            A.variant "CompletionInterface",
            A.variant "CompletionModule",
            A.variant "CompletionProperty",
            A.variant "CompletionUnit",
            A.variant "CompletionValue",
            A.variant "CompletionEnum",
            A.variant "CompletionKeyword",
            A.variant "CompletionSnippet",
            A.variant "CompletionColor",
            A.variant "CompletionFile",
            A.variant "CompletionReference",
            A.variant "CompletionFolder",
            A.variant "CompletionEnumMember",
            A.variant "CompletionConstant",
            A.variant "CompletionStruct",
            A.variant "CompletionEvent",
            A.variant "CompletionOperator",
            A.variant "CompletionTypeParameter",
        },

        A.product "CompletionQuery" {
            A.field "position" "MoonEditor.PositionQuery",
            A.field "context" "MoonEditor.CompletionContext",
            A.unique,
        },

        A.product "CompletionItem" {
            A.field "label" "string",
            A.field "kind" "MoonEditor.CompletionKind",
            A.field "detail" "string",
            A.field "documentation" "string",
            A.field "insert_text" "string",
            A.unique,
        },

        A.sum "SignatureContext" {
            A.variant "SignatureCall" {
                A.field "callee" "string",
                A.field "active_parameter" "number",
                A.field "callee_range" "MoonSource.SourceRange",
                A.variant_unique,
            },
            A.variant "SignatureNoCall" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "SignatureParameter" {
            A.field "label" "string",
            A.field "documentation" "string",
            A.unique,
        },

        A.product "SignatureInfo" {
            A.field "label" "string",
            A.field "documentation" "string",
            A.field "params" (A.many "MoonEditor.SignatureParameter"),
            A.unique,
        },

        A.sum "SignatureHelp" {
            A.variant "SignatureHelp" {
                A.field "signatures" (A.many "MoonEditor.SignatureInfo"),
                A.field "active_signature" "number",
                A.field "active_parameter" "number",
                A.variant_unique,
            },
            A.variant "SignatureHelpMissing" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "SemanticTokenType" {
            A.variant "TokNamespace",
            A.variant "TokType",
            A.variant "TokClass",
            A.variant "TokEnum",
            A.variant "TokInterface",
            A.variant "TokStruct",
            A.variant "TokTypeParameter",
            A.variant "TokParameter",
            A.variant "TokVariable",
            A.variant "TokProperty",
            A.variant "TokEnumMember",
            A.variant "TokEvent",
            A.variant "TokFunction",
            A.variant "TokMethod",
            A.variant "TokMacro",
            A.variant "TokKeyword",
            A.variant "TokModifier",
            A.variant "TokComment",
            A.variant "TokString",
            A.variant "TokNumber",
            A.variant "TokRegexp",
            A.variant "TokOperator",
            A.variant "TokDecorator",
        },

        A.sum "SemanticTokenModifier" {
            A.variant "TokModDeclaration",
            A.variant "TokModDefinition",
            A.variant "TokModReadonly",
            A.variant "TokModStatic",
            A.variant "TokModDeprecated",
            A.variant "TokModAbstract",
            A.variant "TokModAsync",
            A.variant "TokModModification",
            A.variant "TokModDocumentation",
            A.variant "TokModDefaultLibrary",
            A.variant "TokModMutable",
            A.variant "TokModExported",
            A.variant "TokModStorage",
            A.variant "TokModDiagnostic",
        },

        A.product "SemanticTokenSpan" {
            A.field "range" "MoonSource.SourceRange",
            A.field "token_type" "MoonEditor.SemanticTokenType",
            A.field "modifiers" (A.many "MoonEditor.SemanticTokenModifier"),
            A.unique,
        },

        A.sum "CodeActionKind" {
            A.variant "CodeActionQuickFix",
            A.variant "CodeActionRefactor",
            A.variant "CodeActionSource",
            A.variant "CodeActionOrganizeImports",
        },

        A.product "TextEdit" {
            A.field "range" "MoonSource.SourceRange",
            A.field "new_text" "string",
            A.unique,
        },

        A.product "WorkspaceEdit" {
            A.field "edits" (A.many "MoonEditor.TextEdit"),
            A.unique,
        },

        A.product "CodeAction" {
            A.field "title" "string",
            A.field "kind" "MoonEditor.CodeActionKind",
            A.field "diagnostics" (A.many "MoonEditor.DiagnosticFact"),
            A.field "edit" "MoonEditor.WorkspaceEdit",
            A.unique,
        },

        A.product "FoldingRange" {
            A.field "range" "MoonSource.SourceRange",
            A.field "kind" "string",
            A.unique,
        },

        A.product "SelectionRange" {
            A.field "range" "MoonSource.SourceRange",
            A.field "parents" (A.many "MoonSource.SourceRange"),
            A.unique,
        },

        A.product "InlayHint" {
            A.field "pos" "MoonSource.SourcePos",
            A.field "label" "string",
            A.field "kind" "string",
            A.unique,
        },
    }
end
