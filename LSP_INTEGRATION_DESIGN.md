# Moonlift LSP integration design

This is the complete architectural design for integrating an `.mlua` language
server into Moonlift. It is not a milestone plan and it is not a reduced
prototype target.

Terminology note: this document avoids release-style "phases". When it says
**PVM boundary**, it means a `pvm.phase(...)` cache/execution boundary in the
compiler-pattern sense, not a staged delivery plan.

The design rule is the same as the rest of Moonlift:

```text
if the editor observes it, requests it, caches it, invalidates it, or displays it,
it must be an ASDL value.
```

The LSP is therefore not a sidecar parser and not a scanner-driven adapter. It
is another consumer of the existing Moonlift ASDL semantic stack:

```text
DocumentSnapshot
  -> MluaDocumentParts
  -> MluaParseResult / island parse facts
  -> HostDeclSet + Moon2Tree.Module + RegionFrag* + ExprFrag*
  -> HostReport + HostLayoutEnv + HostFactSet
  -> binding/type/open/control/vector/backend reject facts where requested
  -> editor facts
  -> LSP protocol payloads
  -> flat JSON-RPC output commands
```

The only role of lexical island recognition is to produce source ranges and
content slices. Semantic answers come from the original Moonlift ASDL values.

The detailed work checklist for this design is `LSP_INTEGRATION_CHECKLIST.md`.

---

## 1. Ownership model

Moonlift owns `.mlua` files.

```text
.lua  -> ordinary Lua tooling such as lua_ls
.mlua -> moonlift-lsp
```

The Moonlift LSP does not attempt to become LuaLS. Lua text inside `.mlua` is
modeled as opaque staging text unless it participates in hosted Moonlift facts
through explicit ASDL-producing surfaces. This follows the language model:

```text
.mlua = LuaJIT staging text + Moonlift hosted islands
```

LuaJIT remains the runtime parser/executor for Lua syntax. The LSP statically
understands hosted Moonlift islands and the semantic ASDL they produce.

Tree-sitter may be used by Neovim for highlight/injection/fold UX, but it is not
the semantic source for the LSP. Rust is not part of the LSP parser/semantic
core. Rust remains the backend/runtime implementation language where Moonlift
already uses it.

---

## 2. Canonical ASDL integration

The LSP schema belongs in `moonlift/lua/moonlift/asdl.lua`, not in a separate
parallel `lsp_asdl.lua` universe. It should be added as canonical modules that
reuse existing `Moon2Core`, `Moon2Type`, `Moon2Open`, `Moon2Tree`, `Moon2Host`,
`Moon2Vec`, and `Moon2Back` values.

Proposed modules:

```text
Moon2Source  -- document snapshots, changes, spans, anchors, source slices
Moon2Mlua    -- .mlua segmentation/source-map facts over hosted islands
Moon2Editor  -- editor-semantic facts independent of the LSP wire protocol
Moon2Lsp     -- LSP protocol-level request/response payload ASDL
Moon2Rpc     -- JSON-RPC envelope and flat outbound command ASDL
```

`Moon2Editor` is intentionally separate from `Moon2Lsp`: hover, symbols,
diagnostics, references, rename, completions, semantic tokens, and code actions
are semantic/editor facts first. LSP JSON payloads are an adapter product.

---

## 3. Source ASDL

### 3.1 Documents and text edits

Documents are immutable snapshots. Edits are events that produce new snapshots.

```asdl
module Moon2Source {
    DocUri = (string text) unique
    DocVersion = (number value) unique

    LanguageId = LangMlua
               | LangMoonlift
               | LangLua
               | LangUnknown(string name) unique

    DocumentSnapshot = (
        Moon2Source.DocUri uri,
        Moon2Source.DocVersion version,
        Moon2Source.LanguageId language,
        string text
    ) unique

    PositionEncoding = PosUtf8Bytes
                     | PosUtf16CodeUnits
                     | PosUtf32Codepoints

    SourcePos = (
        number line,
        number byte_col,
        number utf16_col
    ) unique

    SourceRange = (
        Moon2Source.DocUri uri,
        number start_offset,
        number stop_offset,
        Moon2Source.SourcePos start,
        Moon2Source.SourcePos stop
    ) unique

    TextChange = ReplaceAll(string text) unique
               | ReplaceRange(Moon2Source.SourceRange range, string text) unique

    DocumentEdit = (
        Moon2Source.DocUri uri,
        Moon2Source.DocVersion version,
        Moon2Source.TextChange* changes
    ) unique
}
```

The internal canonical position is byte-offset based with cached UTF-16 columns
for LSP conversion. The semantic boundaries key on document/source values, not
on protocol JSON tables.

### 3.2 Stable source slices vs moving occurrences

A central cache requirement is that semantic analysis of an unchanged island
must hit even when earlier Lua staging text changes and shifts offsets.
Therefore content identity and occurrence/range identity are separate.

```asdl
module Moon2Source {
    SourceSlice = (string text) unique
    SourceOccurrence = (
        Moon2Source.SourceSlice slice,
        Moon2Source.SourceRange range
    ) unique
}
```

PVM boundaries that parse/typecheck an island key on `SourceSlice` or a richer
`MluaIslandText`, not on the moving file offset. Source ranges are facets used
for editor payloads.

### 3.3 Anchors

Every editor feature needs stable semantic handles. Ranges alone are not enough.

```asdl
module Moon2Source {
    AnchorId = (string text) unique

    AnchorKind = AnchorDoc
               | AnchorLuaOpaque
               | AnchorIsland
               | AnchorKeyword
               | AnchorTypeName
               | AnchorStructName
               | AnchorFieldName
               | AnchorFieldUse
               | AnchorFuncName
               | AnchorFuncUse
               | AnchorParamName
               | AnchorLocalName
               | AnchorBindingUse
               | AnchorBindingDef
               | AnchorRegionName
               | AnchorExprName
               | AnchorContinuationName
               | AnchorContinuationUse
               | AnchorBuiltinName
               | AnchorPackedAlign
               | AnchorDiagnostic

    Anchor = (
        Moon2Source.DocUri uri,
        Moon2Source.AnchorId id
    ) unique

    AnchorSpan = (
        Moon2Source.Anchor anchor,
        Moon2Source.AnchorKind kind,
        string label,
        Moon2Source.SourceRange range
    ) unique

    AnchorSet = (Moon2Source.AnchorSpan* anchors) unique
}
```

Anchors are facts emitted by parsing/source-map boundaries. Semantic values do
not gain mutable range fields; source mapping is a separate fact stream.

---

## 4. `.mlua` source model

### 4.1 Segments

The `.mlua` document is split into Lua staging segments and hosted Moonlift
islands. Both are explicit ASDL values.

```asdl
module Moon2Mlua {
    IslandKind = IslandStruct
               | IslandExpose
               | IslandFunc
               | IslandModule
               | IslandRegion
               | IslandExpr

    IslandName = IslandNamed(string name) unique
               | IslandAnonymous
               | IslandMalformedName(string text) unique

    IslandText = (
        Moon2Mlua.IslandKind kind,
        Moon2Mlua.IslandName name,
        Moon2Source.SourceSlice source
    ) unique

    Segment = LuaOpaque(Moon2Source.SourceOccurrence occurrence) unique
            | HostedIsland(Moon2Mlua.IslandText island, Moon2Source.SourceRange range) unique
            | MalformedIsland(Moon2Mlua.IslandKind kind, Moon2Source.SourceOccurrence occurrence, string reason) unique

    DocumentParts = (
        Moon2Source.DocumentSnapshot document,
        Moon2Mlua.Segment* segments,
        Moon2Source.AnchorSpan* anchors
    ) unique
}
```

The segmentation boundary must match the lexical island rules used by
`host_quote.lua`; otherwise runtime and editor disagree about what `.mlua`
means. The scanner is still not a semantic parser: it produces `Segment`,
`IslandText`, and `AnchorSpan` facts only.

### 4.2 Parse products

Existing `Moon2Host.MluaParseResult` remains the semantic parse product:

```text
MluaParseResult = (
  HostDeclSet decls,
  Moon2Tree.Module module,
  Moon2Open.RegionFrag* region_frags,
  Moon2Open.ExprFrag* expr_frags,
  Moon2Parse.ParseIssue* issues
)
```

The LSP design extends it with source-map facts rather than replacing it.

```asdl
module Moon2Mlua {
    IslandParse = (
        Moon2Mlua.IslandText island,
        Moon2Host.HostDeclSet decls,
        Moon2Tree.Module module,
        Moon2Open.RegionFrag* region_frags,
        Moon2Open.ExprFrag* expr_frags,
        Moon2Parse.ParseIssue* issues,
        Moon2Source.AnchorSpan* anchors
    ) unique

    DocumentParse = (
        Moon2Mlua.DocumentParts parts,
        Moon2Host.MluaParseResult combined,
        Moon2Mlua.IslandParse* islands,
        Moon2Source.AnchorSpan* anchors
    ) unique
}
```

The combined parse result keeps the current compiler path intact. Per-island
parse products give cache locality and source-map precision.

---

## 5. Semantic analysis product

The editor does not invent a separate semantic document. It assembles editor
facts from compiler facts.

```asdl
module Moon2Mlua {
    DocumentAnalysis = (
        Moon2Mlua.DocumentParse parse,
        Moon2Host.MluaHostPipelineResult host,
        Moon2Open.ValidationReport open_report,
        Moon2Tree.TypeIssue* type_issues,
        Moon2Tree.ControlFact* control_facts,
        Moon2Vec.VecLoopDecision* vector_decisions,
        Moon2Vec.VecReject* vector_rejects,
        Moon2Back.BackValidationReport back_report,
        Moon2Source.AnchorSet anchors
    ) unique
}
```

`mlua_document_analysis.lua` now runs the host pipeline, module open
validation, module typecheck, control fact gathering, vector loop
decision/reject production, and backend validation when the typed module is
suitable for lowering. Some fields remain empty when the corresponding compiler
question is not meaningful for a document. They are still explicit result
shapes. There is no hidden `ctx` table controlling whether
layout/type/vector/backend checks are run.

The host pipeline remains the central hosted-value semantic product:

```text
HostDeclSet
  -> HostReport
  -> HostLayoutEnv
  -> HostFactSet
  -> HostLuaFfiPlan / HostTerraPlan / HostCPlan
```

LSP features consume these facts directly.

---

## 6. Workspace and event ASDL

### 6.1 State

```asdl
module Moon2Editor {
    ServerMode = ServerCreated
               | ServerInitialized
               | ServerShutdownRequested
               | ServerExited

    ClientCapability = ClientUtf16Positions
                     | ClientDiagnosticPull
                     | ClientSemanticTokens
                     | ClientWorkspaceFolders
                     | ClientDynamicRegistration(string name) unique

    WorkspaceRoot = (string uri) unique

    WorkspaceState = (
        Moon2Editor.ServerMode mode,
        Moon2Editor.WorkspaceRoot* roots,
        Moon2Source.DocumentSnapshot* open_docs,
        Moon2Editor.ClientCapability* capabilities
    ) unique
}
```

Open documents are ASDL values. There are no mutable side maps as the semantic
state. Runtime tables may index them for speed, but those indexes are derived
and disposable.

### 6.2 Events

```asdl
module Moon2Editor {
    RpcId = RpcIdNumber(number value) unique
          | RpcIdString(string value) unique
          | RpcIdNull

    ClientEvent = Initialize(Moon2Editor.RpcId id, Moon2Editor.WorkspaceRoot* roots, Moon2Editor.ClientCapability* capabilities) unique
                | Initialized
                | Shutdown(Moon2Editor.RpcId id) unique
                | Exit
                | DidOpen(Moon2Source.DocumentSnapshot document) unique
                | DidChange(Moon2Source.DocumentEdit edit) unique
                | DidClose(Moon2Source.DocUri uri) unique
                | DidSave(Moon2Source.DocUri uri) unique
                | RequestHover(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos) unique
                | RequestDefinition(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos) unique
                | RequestReferences(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos, boolean include_decl) unique
                | RequestDocumentSymbols(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | RequestWorkspaceSymbols(Moon2Editor.RpcId id, string query) unique
                | RequestCompletion(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos) unique
                | RequestSignatureHelp(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos) unique
                | RequestSemanticTokensFull(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | RequestSemanticTokensRange(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourceRange range) unique
                | RequestPrepareRename(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos) unique
                | RequestRename(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos pos, string new_name) unique
                | RequestCodeAction(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourceRange range) unique
                | RequestFoldingRange(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | RequestSelectionRange(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourcePos* positions) unique
                | RequestInlayHint(Moon2Editor.RpcId id, Moon2Source.DocUri uri, Moon2Source.SourceRange range) unique
                | InvalidEvent(Moon2Editor.RpcId id, string reason) unique

    Transition = (
        Moon2Editor.WorkspaceState before,
        Moon2Editor.ClientEvent event,
        Moon2Editor.WorkspaceState after
    ) unique
}
```

`Apply(state, event) -> state` is pure and structural. Request responses are not
side effects hidden in `Apply`; they are commands derived from `Transition`.

---

## 7. PVM boundary graph

This is a boundary graph, not a release sequence.

```text
Client JSON bytes
  -> Moon2Rpc.Incoming
  -> Moon2Editor.ClientEvent
  -> Apply(WorkspaceState, ClientEvent) -> WorkspaceState
  -> Moon2Editor.Transition
  -> Moon2Rpc.OutCommand*
  -> JSON-RPC bytes
```

Document semantic graph:

```text
DocumentSnapshot
  -> DocumentParts
  -> DocumentParse
  -> DocumentAnalysis
  -> DiagnosticFact*
  -> SymbolFact*
  -> BindingFact*
  -> HoverResult / CompletionList / DefinitionResult / RenameResult / ...
  -> LSP payload ASDL
```

Required PVM boundaries:

| Boundary | Question | Input | Output |
|---|---|---|---|
| `source_apply_change` | What snapshot results from these text changes? | `DocumentSnapshot`, `DocumentEdit` | `DocumentSnapshot` |
| `mlua_document_parts` | Where are Lua opaque segments and hosted islands? | `DocumentSnapshot` | `DocumentParts` |
| `mlua_island_parse` | What Moonlift facts does this island text author? | `IslandText` | `IslandParse` |
| `mlua_document_parse` | What combined compiler parse result does the document author? | `DocumentParts` | `DocumentParse` |
| `mlua_document_analysis` | What host/layout/open/type/control/vector/backend facts follow? | `DocumentParse` | `DocumentAnalysis` |
| `editor_anchor_index` | Which anchors/ranges are available for position queries? | `DocumentAnalysis` | `AnchorIndex` |
| `editor_subject_at` | What semantic subject is at this source position? | `PositionQuery` | `SubjectPick` |
| `editor_diagnostic_facts` | What editor diagnostics exist? | `DocumentAnalysis` | `DiagnosticFact*` |
| `editor_symbol_facts` | What symbols are declared? | `DocumentAnalysis` | `SymbolFact*` |
| `editor_binding_facts` | What defs/uses/references exist? | `DocumentAnalysis` | `BindingFact*` |
| `editor_completion_context` | What completion context is at this position? | `PositionQuery` | `CompletionContext` |
| `editor_completion_items` | What completions are valid? | `CompletionQuery` | `CompletionItem*` |
| `editor_hover` | What hover info is available? | `SubjectQuery` | `HoverResult` |
| `editor_definition` | Where is this subject defined? | `SubjectQuery` | `DefinitionResult` |
| `editor_references` | Where is this subject used? | `ReferenceQuery` | `ReferenceResult` |
| `editor_rename` | What edits perform this rename? | `RenameQuery` | `RenameResult` |
| `editor_semantic_tokens` | What semantically classified tokens exist? | `SemanticTokenQuery` | `SemanticTokenSpan*` |
| `editor_code_actions` | What edits repair or refactor diagnostics? | `CodeActionQuery` | `CodeAction*` |
| `lsp_payload` | How does an editor fact become LSP protocol ASDL? | typed editor result | `Moon2Lsp.Payload` |
| `rpc_out_commands` | What bytes should the server write? | `Transition` | `Moon2Rpc.OutCommand*` |

Handlers return triplets. Whole-document products are assemblies over fact
streams, not mutable caches.

---

## 8. Editor semantic facts

### 8.1 Diagnostics

Diagnostics are derived from existing issue/report ASDL values.

```asdl
module Moon2Editor {
    DiagnosticSeverity = DiagError
                       | DiagWarning
                       | DiagInfo
                       | DiagHint

    DiagnosticOrigin = DiagFromParse(Moon2Parse.ParseIssue issue) unique
                     | DiagFromHost(Moon2Host.HostIssue issue) unique
                     | DiagFromOpen(Moon2Open.ValidationIssue issue) unique
                     | DiagFromType(Moon2Tree.TypeIssue issue) unique
                     | DiagFromBack(Moon2Back.BackValidationIssue issue) unique
                     | DiagFromVectorReject(Moon2Vec.VecReject reject) unique
                     | DiagFromBindingResolution(Moon2Editor.BindingResolution resolution) unique
                     | DiagFromSource(Moon2Source.SourceApplyIssue issue) unique
                     | DiagFromTransport(string code, string message) unique

    DiagnosticFact = (
        Moon2Editor.DiagnosticSeverity severity,
        Moon2Editor.DiagnosticOrigin origin,
        string code,
        string message,
        Moon2Source.SourceRange range
    ) unique
}
```

No diagnostic is just a string. The origin remains inspectable, so code actions
and hover can link back to the real compiler issue. Type and backend diagnostic
codes/messages are assigned by variant dispatch, and type ranges use source-map
operator/keyword/name anchors where available. Unresolved local/value uses
come from `BindingResolution` facts, so their ranges and quick fixes are driven
by scoped binding analysis rather than message matching. Optimization-planning facts
such as `VecReject*` stay in `DocumentAnalysis` and are not published as LSP
diagnostics by default; otherwise ordinary non-vectorizable code would show
noisy informational diagnostics.

### 8.2 Subjects

All position-based features first resolve a subject.

```asdl
module Moon2Editor {
    Subject = SubjectMissing
            | SubjectKeyword(string name) unique
            | SubjectScalar(Moon2Core.Scalar scalar) unique
            | SubjectType(Moon2Type.Type ty) unique
            | SubjectHostStruct(Moon2Host.HostStructDecl decl) unique
            | SubjectHostField(Moon2Host.HostStructDecl owner, Moon2Host.HostFieldDecl field) unique
            | SubjectHostExpose(Moon2Host.HostExposeDecl decl) unique
            | SubjectHostAccessor(Moon2Host.HostAccessorDecl decl) unique
            | SubjectFunc(Moon2Tree.Func func) unique
            | SubjectModule(Moon2Tree.Module module) unique
            | SubjectRegionFrag(Moon2Open.RegionFrag frag) unique
            | SubjectExprFrag(Moon2Open.ExprFrag frag) unique
            | SubjectBinding(Moon2Bind.Binding binding) unique
            | SubjectContinuation(Moon2Source.AnchorId scope, Moon2Tree.BlockLabel label) unique
            | SubjectBuiltin(string name) unique
            | SubjectDiagnostic(Moon2Editor.DiagnosticFact diagnostic) unique

    SubjectPick = SubjectHit(Moon2Editor.Subject subject, Moon2Source.Anchor anchor) unique
                | SubjectMiss

    PositionQuery = (
        Moon2Mlua.DocumentAnalysis analysis,
        Moon2Source.SourcePos position
    ) unique
}
```

For continuation/block labels, `SubjectContinuation.scope` is the defining
anchor id when a definition anchor is known. Uses resolve to that same defining
anchor id before references/rename/highlight are computed, so two same-named
`loop` labels in one hosted island do not collapse into one reference set.

Hover, definition, references, rename, highlighting, and completion context all
consume `SubjectPick` or an explicit query value derived from it.

### 8.3 Symbols

```asdl
module Moon2Editor {
    SymbolKind = SymFile
               | SymModule
               | SymStruct
               | SymField
               | SymFunction
               | SymMethod
               | SymParameter
               | SymVariable
               | SymConstant
               | SymRegion
               | SymExprFragment
               | SymContinuation
               | SymBuiltin

    SymbolId = (string text) unique

    SymbolFact = (
        Moon2Editor.SymbolId id,
        Moon2Editor.SymbolId parent,
        Moon2Editor.SymbolKind kind,
        string name,
        string detail,
        Moon2Editor.Subject subject,
        Moon2Source.Anchor decl_anchor
    ) unique

    SymbolTree = (Moon2Editor.SymbolFact* roots) unique
}
```

Symbol facts are emitted from:

- `HostDeclStruct` and `HostFieldDecl`
- `HostDeclExpose`
- `HostDeclAccessor`
- `Moon2Tree.ItemFunc`, `ItemConst`, `ItemStatic`, `ItemType`, `ItemImport`
- `RegionFrag` and `ExprFrag`
- continuation/block labels where authored
- standard-library/builtin facts where visible

### 8.4 Bindings, references, and rename

```asdl
module Moon2Editor {
    BindingRole = BindingDef
                | BindingUse
                | BindingRead
                | BindingWrite
                | BindingCall
                | BindingTypeUse

    BindingScopeId = (string text) unique
    BindingScopeKind = BindingScopeDocument
                     | BindingScopeIsland
                     | BindingScopeFunction
                     | BindingScopeRegion
                     | BindingScopeExpr
                     | BindingScopeControlBlock
                     | BindingScopeBranch
                     | BindingScopeModule
                     | BindingScopeOpaque(string name) unique

    BindingScopeFact = (BindingScopeId id, BindingScopeId parent, BindingScopeKind kind, Moon2Source.SourceRange range) unique
    ScopedBinding = (Moon2Bind.Binding binding, BindingScopeId scope, Moon2Source.SourceRange visible_range, Moon2Source.AnchorSpan anchor) unique
    BindingUseSite = (Moon2Source.AnchorSpan anchor, BindingRole role, BindingScopeId scope) unique
    BindingResolution = BindingResolved(BindingUseSite use, ScopedBinding binding) unique
                      | BindingUnresolved(BindingUseSite use, string reason) unique
    BindingScopeReport = (BindingScopeFact* scopes, ScopedBinding* bindings, BindingResolution* resolutions) unique

    BindingFact = (
        Moon2Editor.SymbolId id,
        Moon2Editor.BindingRole role,
        Moon2Editor.Subject subject,
        Moon2Source.AnchorSpan anchor
    ) unique

    DefinitionResult = DefinitionHit(Moon2Editor.Subject subject, Moon2Source.SourceRange* ranges) unique
                     | DefinitionMiss(string reason) unique

    ReferenceResult = ReferenceHit(Moon2Editor.Subject subject, Moon2Source.SourceRange* ranges) unique
                    | ReferenceMiss(string reason) unique

    RenameEdit = (Moon2Source.SourceRange range, string new_text) unique
    RenameResult = RenameOk(Moon2Editor.RenameEdit* edits) unique
                 | RenameRejected(string reason) unique
    PrepareRenameResult = PrepareRenameOk(Moon2Source.SourceRange range, string placeholder) unique
                        | PrepareRenameRejected(string reason) unique
}
```

Prepare-rename and rename are only valid for subjects whose binding facts prove
all affected spans. Local and parameter binding facts are downstream of the
explicit `BindingScopeReport`: scope ranges define visibility, `ScopedBinding`
facts define authored definitions, and `BindingResolution` facts answer each
read/write use. No rename walks raw text looking for matching strings.

### 8.5 Hover

```asdl
module Moon2Editor {
    MarkupKind = MarkupPlainText
               | MarkupMarkdown

    HoverInfo = HoverMissing
              | HoverScalar(Moon2Core.Scalar scalar, string markdown) unique
              | HoverType(Moon2Type.Type ty, string markdown) unique
              | HoverHostStruct(Moon2Host.HostStructDecl decl, Moon2Host.HostTypeLayout layout, string markdown) unique
              | HoverHostField(Moon2Host.HostStructDecl owner, Moon2Host.HostFieldDecl field, Moon2Host.HostFieldLayout layout, string markdown) unique
              | HoverExpose(Moon2Host.HostExposeDecl expose, Moon2Host.HostFact* facts, string markdown) unique
              | HoverFunc(Moon2Tree.Func func, string markdown) unique
              | HoverRegion(Moon2Open.RegionFrag frag, string markdown) unique
              | HoverExpr(Moon2Open.ExprFrag frag, string markdown) unique
              | HoverBuiltin(string library, string name, string markdown) unique
              | HoverDiagnostic(Moon2Editor.DiagnosticFact diagnostic, string markdown) unique
}
```

Host hover should expose the valuable facts we already compute: repr, size,
align, field offsets, bool storage encoding, view descriptor ABI, access plans,
and target emit-plan availability.

### 8.6 Completion

Completion context is explicit.

```asdl
module Moon2Editor {
    CompletionContext = CtxTopLevel
                      | CtxModuleItem
                      | CtxStructField
                      | CtxTypePosition
                      | CtxExprPosition
                      | CtxPlacePosition
                      | CtxExposeSubject
                      | CtxExposeTarget
                      | CtxExposeMode
                      | CtxRegionStmt
                      | CtxContinuationArgs
                      | CtxBuiltinPath
                      | CtxLuaOpaque
                      | CtxInvalid(string reason) unique

    CompletionKind = CompleteKeyword
                   | CompleteType
                   | CompleteStruct
                   | CompleteField
                   | CompleteFunction
                   | CompleteMethod
                   | CompleteModule
                   | CompleteRegion
                   | CompleteExprFragment
                   | CompleteBuiltin
                   | CompleteSnippet

    CompletionItem = (
        string label,
        Moon2Editor.CompletionKind kind,
        string detail,
        string documentation,
        string sort_text,
        string insert_text,
        Moon2Editor.Subject subject
    ) unique

    CompletionQuery = (
        Moon2Mlua.DocumentAnalysis analysis,
        Moon2Source.SourcePos position,
        Moon2Editor.CompletionContext context
    ) unique
}
```

`CtxLuaOpaque` deliberately produces no Moonlift semantic completions unless the
position is inside a known hosted island or explicit Moonlift builder context.
Moonlift does not fake Lua completions.

### 8.7 Signature help

Signature help is split into an explicit source-call context and a semantic
signature catalog. The call context may inspect source nesting to identify the
callee and active parameter, but the returned signatures come from ASDL compiler
facts and builtin-library facts.

```asdl
module Moon2Editor {
    SignatureContext = SignatureCall(string callee, number active_parameter,
                                     Moon2Source.SourceRange callee_range) unique
                     | SignatureNoCall(string reason) unique

    SignatureParameter = (string label, string documentation) unique
    SignatureInfo = (string label, string documentation,
                     Moon2Editor.SignatureParameter* params) unique
    SignatureHelp = SignatureHelp(Moon2Editor.SignatureInfo* signatures,
                                  number active_signature,
                                  number active_parameter) unique
                  | SignatureHelpMissing(string reason) unique
}
```

Current catalog entries include `Moon2Tree.Func`, `Moon2Tree.ExternFunc`, host
accessors, region/expr fragments, and selected public builtins such as
`moonlift.json.decode`.

### 8.8 Semantic tokens

```asdl
module Moon2Editor {
    SemanticTokenType = TokNamespace
                      | TokType
                      | TokStruct
                      | TokField
                      | TokFunction
                      | TokMethod
                      | TokParameter
                      | TokVariable
                      | TokKeyword
                      | TokComment
                      | TokString
                      | TokNumber
                      | TokOperator
                      | TokBuiltin
                      | TokDiagnostic

    SemanticTokenModifier = TokDecl
                          | TokDef
                          | TokReadonly
                          | TokMutable
                          | TokStatic
                          | TokExport
                          | TokUnsafe
                          | TokDeprecated
                          | TokError

    SemanticTokenSpan = (
        Moon2Source.SourceRange range,
        Moon2Editor.SemanticTokenType token_type,
        Moon2Editor.SemanticTokenModifier* modifiers,
        Moon2Editor.Subject subject
    ) unique
}
```

Tokens come from parsed source anchors and semantic subjects. They are not a
Tree-sitter token stream.

### 8.9 Code actions

```asdl
module Moon2Editor {
    CodeActionKind = ActionQuickFix
                   | ActionRefactor
                   | ActionSource

    TextEdit = (Moon2Source.SourceRange range, string new_text) unique
    WorkspaceEdit = (Moon2Editor.TextEdit* edits) unique

    CodeAction = (
        string title,
        Moon2Editor.CodeActionKind kind,
        Moon2Editor.DiagnosticFact* diagnostics,
        Moon2Editor.WorkspaceEdit edit
    ) unique
}
```

Examples that must be fact-driven:

- bare boundary `bool` -> explicit `bool8` / `bool32` suggestion from
  `HostIssueBareBoolInBoundaryStruct`
- invalid packed align -> suggested legal alignments from
  `HostIssueInvalidPackedAlign`
- duplicate declaration/field -> jump to duplicates and possible rename edits
- unfilled open slot -> create fill snippet from `Moon2Open.ValidationIssue`

---

## 9. LSP protocol ASDL

Protocol payloads are downstream. They preserve enough shape to serialize
without re-answering semantic questions.

```asdl
module Moon2Lsp {
    LspPosition = (number line, number character) unique
    LspRange = (Moon2Lsp.LspPosition start, Moon2Lsp.LspPosition stop) unique
    LspLocation = (string uri, Moon2Lsp.LspRange range) unique

    Diagnostic = (Moon2Lsp.LspRange range, number severity, string source, string code, string message) unique
    DiagnosticReport = (string uri, number version, Moon2Lsp.Diagnostic* diagnostics) unique

    Markup = MarkupPlain(string text) unique
           | MarkupMarkdown(string markdown) unique
    Hover = HoverHit(Moon2Lsp.Markup contents, Moon2Lsp.LspRange range) unique
          | HoverMiss

    CompletionItem = (string label, number kind, string detail, string documentation, string sort_text, string insert_text) unique
    CompletionList = (boolean is_incomplete, Moon2Lsp.CompletionItem* items) unique

    DocumentSymbol = (string name, string detail, number kind, Moon2Lsp.LspRange range, Moon2Lsp.LspRange selection_range, Moon2Lsp.DocumentSymbol* children) unique
    DocumentSymbolList = (Moon2Lsp.DocumentSymbol* symbols) unique
    WorkspaceSymbol = (string name, string detail, number kind, Moon2Lsp.LspLocation location, string container_name) unique

    SignatureParameterPayload = (string label, string documentation) unique
    SignatureInformationPayload = (string label, string documentation, Moon2Lsp.SignatureParameterPayload* params) unique
    SignatureHelpPayload = (Moon2Lsp.SignatureInformationPayload* signatures, number active_signature, number active_parameter) unique
    SemanticTokens = (number* data) unique
    DocumentHighlight = (Moon2Lsp.LspRange range, number kind) unique
    PrepareRename = (Moon2Lsp.LspRange range, string placeholder) unique
    WorkspaceEdit = (string uri, Moon2Lsp.TextEdit* edits) unique
    TextEdit = (Moon2Lsp.LspRange range, string new_text) unique

    Payload = PayloadNull
            | PayloadInitialize(Moon2Lsp.InitializeResult value) unique
            | PayloadDiagnostics(Moon2Lsp.DiagnosticReport value) unique
            | PayloadHover(Moon2Lsp.Hover value) unique
            | PayloadCompletion(Moon2Lsp.CompletionList value) unique
            | PayloadDocumentSymbols(Moon2Lsp.DocumentSymbolList value) unique
            | PayloadWorkspaceSymbols(Moon2Lsp.WorkspaceSymbol* value) unique
            | PayloadSignatureHelp(Moon2Lsp.SignatureHelpPayload value) unique
            | PayloadLocations(Moon2Lsp.LspLocation* values) unique
            | PayloadDocumentHighlights(Moon2Lsp.DocumentHighlight* values) unique
            | PayloadPrepareRename(Moon2Lsp.PrepareRename value) unique
            | PayloadSemanticTokens(Moon2Lsp.SemanticTokens value) unique
            | PayloadWorkspaceEdit(Moon2Lsp.WorkspaceEdit* value) unique
            | PayloadCodeActions(Moon2Lsp.CodeAction* actions) unique
}
```

`Moon2Lsp` is allowed to know LSP numeric enums. It is not allowed to inspect
Moonlift source strings or redo semantic classification.

---

## 10. JSON-RPC transport ASDL and final loop

```asdl
module Moon2Rpc {
    JsonValue = JsonNull
              | JsonBool(boolean value) unique
              | JsonNumber(number value) unique
              | JsonString(string value) unique
              | JsonArray(Moon2Rpc.JsonValue* values) unique
              | JsonObject(Moon2Rpc.JsonMember* members) unique
    JsonMember = (string key, Moon2Rpc.JsonValue value) unique

    Incoming = RpcRequest(Moon2Editor.RpcId id, string method, Moon2Rpc.JsonValue params) unique
             | RpcIncomingNotification(string method, Moon2Rpc.JsonValue params) unique
             | RpcInvalid(string reason) unique

    Outgoing = RpcResult(Moon2Editor.RpcId id, Moon2Lsp.Payload payload) unique
             | RpcError(Moon2Editor.RpcId id, number code, string message) unique
             | RpcOutgoingNotification(string method, Moon2Lsp.Payload payload) unique

    OutCommand = SendMessage(Moon2Rpc.Outgoing message) unique
               | LogMessage(string level, string message) unique
               | StopServer
}
```

The stdio server is a final loop over flat commands:

```text
for command in rpc_out_commands(transition) do
  if SendMessage then serialize JSON-RPC and write bytes
  if LogMessage then write stderr/log sink
  if StopServer then break
end
```

JSON encoding/decoding is transport-level. It does not become a Moonlift JSON
semantic subsystem and does not reuse the Moonlift indexed-tape JSON builtin for
editor protocol meaning.

---

## 11. Request behavior

Each LSP method is specified by ASDL query and result values.

| LSP method | ASDL query | Semantic source |
|---|---|---|
| `initialize` | `Initialize` event | server capability constants + client capabilities |
| `textDocument/didOpen` | `DidOpen(DocumentSnapshot)` | state apply, then diagnostics command |
| `textDocument/didChange` | `DidChange(DocumentEdit)` | pure text edit apply, then diagnostics command |
| `textDocument/didClose` | `DidClose(DocUri)` | state apply, clear diagnostics command |
| `textDocument/diagnostic` | diagnostic query | `DiagnosticFact*` |
| `textDocument/publishDiagnostics` | outbound command | `DiagnosticFact* -> Lsp DiagnosticReport` |
| `textDocument/documentSymbol` | symbol query | `SymbolFact* -> SymbolTree` |
| `textDocument/workspaceSymbol` | workspace symbol query | workspace-wide `SymbolFact*` |
| `textDocument/hover` | `SubjectQuery` | `SubjectPick -> HoverInfo` |
| `textDocument/definition` | `SubjectQuery` | `BindingFact*`, symbol facts, anchors |
| `textDocument/references` | `ReferenceQuery` | `BindingFact*` |
| `textDocument/documentHighlight` | `ReferenceQuery` | `BindingFact*` in current document |
| `textDocument/completion` | `CompletionQuery` | explicit `CompletionContext` + semantic envs |
| `textDocument/signatureHelp` | `SignatureQuery` | function/extern/accessor facts and active arg context |
| `textDocument/semanticTokens/full` | token query | anchors + semantic subjects |
| `textDocument/semanticTokens/range` | token range query | full token facts filtered by source range |
| `textDocument/prepareRename` | rename prepare query | subject + binding facts |
| `textDocument/rename` | rename query | binding facts -> explicit text edits |
| `textDocument/codeAction` | code action query | diagnostics with origin values |
| `textDocument/foldingRange` | fold query | island ranges, module/region/control block ranges |
| `textDocument/selectionRange` | selection query | anchor nesting and source tree spans |
| `textDocument/inlayHint` | inlay query | typed params/results where explicit enough |

Unsupported requests must return explicit `Rejected`/empty ASDL results, not
throw ad-hoc errors.

---

## 12. File organization

Implementation files should mirror ASDL modules and questions. Avoid vague names
like `helpers.lua`, `utils.lua`, or scanner-only semantic modules.

Canonical files:

```text
lua/moonlift/source_text_apply.lua
lua/moonlift/source_position_index.lua
lua/moonlift/source_anchor_index.lua

lua/moonlift/mlua_document_parts.lua
lua/moonlift/mlua_island_parse.lua
lua/moonlift/mlua_document_parse.lua
lua/moonlift/mlua_document_analysis.lua

lua/moonlift/editor_diagnostic_facts.lua
lua/moonlift/editor_symbol_facts.lua
lua/moonlift/editor_binding_facts.lua
lua/moonlift/editor_subject_at.lua
lua/moonlift/editor_hover.lua
lua/moonlift/editor_completion_context.lua
lua/moonlift/editor_completion_items.lua
lua/moonlift/editor_definition.lua
lua/moonlift/editor_references.lua
lua/moonlift/editor_rename.lua
lua/moonlift/editor_semantic_tokens.lua
lua/moonlift/editor_code_actions.lua
lua/moonlift/editor_folding_ranges.lua
lua/moonlift/editor_selection_ranges.lua
lua/moonlift/editor_inlay_hints.lua

lua/moonlift/lsp_payload_adapt.lua
lua/moonlift/lsp_capabilities.lua

lua/moonlift/rpc_json_decode.lua
lua/moonlift/rpc_json_encode.lua
lua/moonlift/rpc_lsp_decode.lua
lua/moonlift/rpc_lsp_encode.lua
lua/moonlift/rpc_out_commands.lua
lua/moonlift/rpc_stdio_loop.lua

lsp.lua
```

`lsp.lua` is only the executable entrypoint. The semantic design lives in the
ASDL/PVM modules above.

Existing root `lsp/` code may be mined for JSON-RPC framing tests or adapter
ideas, but its Lua semantic model is not the Moonlift LSP semantic core.

---

## 13. Cache and invalidation design

Required cache behavior:

- editing Lua opaque text before an unchanged island changes document ranges but
  preserves `IslandText` identity, so island parse/type/layout analysis hits;
- editing inside one function/region invalidates that body/island and downstream
  facts, not unrelated hosted declarations;
- editing a host struct invalidates dependent layout/access/exposure facts by
  ASDL identity, not by manual dependency maps;
- diagnostics/symbols/hover/completion reuse parsed semantic facts through PVM
  cache hits;
- moving unchanged text should miss source-map/range facts but hit content
  semantics.

Expected `pvm.report` checks:

```text
Document edit before island:
  mlua_document_parts: miss
  mlua_island_parse(unchanged island): hit
  host layout for unchanged HostStructDecl: hit
  editor symbols: partial miss only for changed source ranges

Struct field edit:
  affected IslandText parse: miss
  HostDeclStruct identity: miss
  dependent HostLayoutEnv / HostFactSet / hovers / diagnostics: miss
  unrelated islands and facts: hit
```

Manual side caches are not part of the design. Performance indexes may be built
as ASDL products such as `AnchorIndex`, `SymbolIndex`, or `BindingIndex`.

---

## 14. Neovim integration

Neovim config should attach Moonlift LSP to `.mlua` and keep LuaLS for `.lua`.

```lua
vim.filetype.add({
  extension = {
    mlua = "mlua",
    moon = "moonlift",
  },
})

vim.lsp.config("moonlift", {
  cmd = { "luajit", "moonlift/lsp.lua" },
  filetypes = { "mlua", "moonlift" },
  root_markers = { "moonlift", ".git" },
})

vim.lsp.enable("moonlift")
```

LuaLS remains configured for ordinary Lua files:

```lua
vim.lsp.config("lua_ls", {
  filetypes = { "lua" },
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { checkThirdParty = false },
    },
  },
})
```

If `.mlua` later gets optional Tree-sitter support, it must be editor UX only
unless it produces the same ASDL source facts as `mlua_document_parts`.

---

## 15. Test and acceptance matrix

These are architectural acceptance requirements, not staged feature cuts.

### ASDL definition

- `lua/moonlift/asdl.lua` defines `Moon2Source`, `Moon2Mlua`, `Moon2Editor`,
  `Moon2Lsp`, and `Moon2Rpc` in the canonical context.
- LSP/editor schema uses existing `Moon2Host`, `Moon2Tree`, `Moon2Open`,
  `Moon2Type`, `Moon2Vec`, and `Moon2Back` values where semantic meaning already
  exists.

### Source/apply

- full text edit and range edit produce `DocumentSnapshot` through pure apply;
- UTF-16 protocol positions round-trip through byte-offset source positions;
- unchanged island content keeps identity when preceding Lua text changes.

### `.mlua` semantic integration

- document segmentation matches `host_quote.lua` hosted-island boundaries;
- `.mlua` parse result still produces `HostDeclSet`, `Moon2Tree.Module`,
  `RegionFrag*`, and `ExprFrag*`;
- source anchors map semantic declarations/uses back to ranges;
- host validation/layout/access/view facts are available to editor hovers and
  diagnostics.

### Diagnostics

- parse issues become diagnostics with parse-origin values;
- host declaration issues become diagnostics with host-origin values;
- open/type/control/vector/backend rejects become diagnostics when those compiler
  questions are asked;
- code actions consume diagnostic origin values, not message strings.

### Symbols and navigation

- document symbols include structs, fields, exposes, functions, methods,
  modules, regions, expr fragments, consts/statics/imports, continuation labels;
- go-to definition and references use binding/source anchor facts;
- rename succeeds only when binding facts cover every edit.

### Hover and completion

- scalar/type hover comes from `Moon2Core` / `Moon2Type` facts;
- host struct/field hover includes layout facts such as repr, size, align,
  offset, and bool storage encoding;
- view/expose hover includes descriptor/access/ABI facts;
- completion contexts are explicit ASDL values and distinguish top-level,
  module item, type position, expose target/mode, region statement,
  continuation args, and Lua opaque contexts.

### Semantic tokens and editor structure

- semantic tokens use source anchors plus semantic subjects;
- folding ranges come from hosted islands and block/module/region spans;
- selection ranges come from nested source spans/anchors.

### Transport

- JSON-RPC decode produces `Moon2Rpc.Incoming`;
- LSP decode produces `Moon2Editor.ClientEvent`;
- state update is `Apply(state,event)->state`;
- outbound bytes are produced only by draining flat `Moon2Rpc.OutCommand` values.

---

## 16. PVM design note

Source ASDL:

- Existing types affected:
  - `Moon2Host.MluaSource`, `MluaParseResult`, `MluaHostPipelineResult`
  - `Moon2Host.HostDeclSet`, `HostReport`, `HostLayoutEnv`, `HostFactSet`
  - `Moon2Tree.Module`, `Item`, `Func`, `TypeDecl`, `Control*Region`
  - `Moon2Open.RegionFrag`, `ExprFrag`, validation reports
  - `Moon2Parse.ParseIssue`, `Moon2Tree.TypeIssue`, backend/vector rejects
- New types needed:
  - `Moon2Source`: documents, edits, ranges, source slices, anchors
  - `Moon2Mlua`: segments, island text, document parse/analysis source facets
  - `Moon2Editor`: diagnostics, subjects, symbols, bindings, hovers,
    completions, rename/code-action/token facts
  - `Moon2Lsp`: protocol payload ASDL
  - `Moon2Rpc`: JSON-RPC envelopes and flat output commands
- User-authored fields:
  - document URI/version/text/language
  - text edit ranges and replacement text
  - `.mlua` hosted island text as authored
- Derived fields excluded:
  - parse trees, layout facts, symbol indexes, diagnostics, protocol payloads,
    source position indexes, semantic token integer arrays

Events / Apply:

- Event variants needed:
  - initialize/initialized/shutdown/exit
  - didOpen/didChange/didClose/didSave
  - hover/definition/references/documentSymbol/workspaceSymbol/completion/
    signatureHelp/semanticTokens/rename/codeAction/folding/selection/inlay
- Pure state transition:
  - `Apply(WorkspaceState, ClientEvent) -> WorkspaceState`
  - `Transition(before,event,after)` is the ASDL value used for response command
    planning
- State fields changed through `pvm.with`:
  - server mode
  - roots/capabilities
  - open document snapshot list

PVM boundaries:

- Boundary name: `mlua_document_parts`
  - Question answered: what source segments/islands are authored?
  - Input type: `DocumentSnapshot`
  - Output facts/result shape: `DocumentParts`
  - Cache key: document snapshot; semantic subkeys are `IslandText`
  - Extra args: none
- Boundary name: `mlua_island_parse`
  - Question answered: what ASDL facts does an island author?
  - Input type: `IslandText`
  - Output: `IslandParse`
  - Cache key: island kind/name/source slice
  - Extra args: none
- Boundary name: `mlua_document_analysis`
  - Question answered: what compiler facts exist for the document?
  - Input type: `DocumentParse`
  - Output: `DocumentAnalysis`
  - Cache key: parse result and explicit compiler-question values
  - Extra args: explicit target model if requested
- Boundary name: `editor_subject_at`
  - Question answered: what semantic subject is under a position?
  - Input: `PositionQuery`
  - Output: `SubjectPick`
  - Cache key: analysis + source position
- Boundary name: `editor_*` feature boundaries
  - Question answered: one editor feature each
  - Input: explicit query ASDL
  - Output: typed editor result ASDL
- Boundary name: `rpc_out_commands`
  - Question answered: what flat outbound commands follow this transition?
  - Input: `Transition`
  - Output: `OutCommand*`

Field classification:

- Code-shaping fields:
  - island kind
  - hosted declaration variants
  - type/open/tree/back/vector issue variants
  - completion context variants
  - subject variants
  - request/event variants
- Payload fields:
  - URI, version, source text, source ranges, labels, markdown, replacement text
- Dead fields to remove:
  - scanner-only `name/kind` strings used as semantic truth
  - raw JSON request tables past the decode boundary
  - protocol numeric enums inside semantic/editor facts
  - hidden runtime maps as semantic state

Execution:

- Flat fact/command type:
  - `Moon2Rpc.OutCommand`
- Push/pop stack state:
  - JSON-RPC framing loop owns byte IO only
  - semantic state is `WorkspaceState`
- Final loop behavior:
  - read JSON-RPC bytes
  - decode to ASDL event
  - apply state
  - drain `rpc_out_commands(Transition)`
  - serialize/write commands

Diagnostics:

- Expected `pvm.report` reuse:
  - unchanged island content hits island parse and downstream semantic analysis
  - moving source ranges misses source-map facts only
  - unrelated islands hit across edits
- Possible cache failure modes:
  - including offsets in island parse keys
  - using raw scanner strings as semantic facts
  - hiding document store in mutable tables
  - computing protocol payloads directly from parse strings
  - conflating Lua opaque text with Moonlift source facts
