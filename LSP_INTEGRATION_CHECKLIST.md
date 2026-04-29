# Moonlift LSP integration checklist

This is the complete work checklist for the Moonlift `.mlua` language server.
It follows `LSP_INTEGRATION_DESIGN.md` and is intentionally **not** a
minimal-server checklist, not a V1 checklist, and not a release-phase plan.

The work is complete only when the LSP is integrated as canonical Moonlift
ASDL/PVM compiler work:

```text
DocumentSnapshot
  -> DocumentParts
  -> DocumentParse
  -> DocumentAnalysis
  -> Editor facts
  -> LSP payload ASDL
  -> flat RPC output commands
  -> stdio bytes
```

Lexical hosted-island scanning is allowed only as source segmentation and
source-map production. It is not semantic truth.

---

## Status legend

- `[ ]` not done
- `[x]` done
- `[~]` partially done but not accepted
- `[!]` blocked by an explicit design issue

A checked item must be true in code, tests, and docs.

---

## 0. Architecture guardrails

- [ ] LSP/editor ASDL lives in canonical `moonlift/lua/moonlift/asdl.lua`, not a
      standalone parallel schema.
- [ ] Editor-visible meaning is represented as ASDL values.
- [ ] LSP handlers never compute semantic answers directly from raw strings.
- [ ] Raw JSON/LSP tables do not cross past the RPC decode boundary.
- [ ] Scanner output is source-map data only: segments, ranges, source slices,
      anchors.
- [ ] Semantic answers consume existing Moonlift values:
      `MluaParseResult`, `MluaHostPipelineResult`, `HostDeclSet`,
      `Moon2Tree.Module`, `RegionFrag*`, `ExprFrag*`, host layout/access/view
      facts, open/type/control/vector/backend reports.
- [ ] Workspace state is an ASDL value and changes through pure apply.
- [ ] Runtime lookup tables are disposable indexes over ASDL state, never the
      semantic store.
- [ ] Request/response planning produces ASDL payloads and flat output commands
      before serialization.
- [ ] Final server loop only reads bytes, decodes to ASDL, applies events,
      drains flat commands, serializes bytes, and writes them.
- [ ] `.mlua` belongs to Moonlift LSP; ordinary `.lua` remains for LuaLS or
      other Lua tooling.
- [ ] Tree-sitter, if added, is editor UX only unless it produces the same ASDL
      source facts as `mlua_document_parts`.
- [ ] Rust is not introduced for LSP semantic parsing or cache ownership.

---

## 1. Canonical ASDL schema

### 1.1 `Moon2Source`

- [x] Add `DocUri`.
- [x] Add `DocVersion`.
- [x] Add `LanguageId` variants:
  - [x] `LangMlua`
  - [x] `LangMoonlift`
  - [x] `LangLua`
  - [x] `LangUnknown(name)`
- [x] Add `DocumentSnapshot(uri, version, language, text)`.
- [x] Add `PositionEncoding` variants:
  - [x] `PosUtf8Bytes`
  - [x] `PosUtf16CodeUnits`
  - [x] `PosUtf32Codepoints`
- [x] Add `SourcePos(line, byte_col, utf16_col)`.
- [x] Add `SourceRange(uri, start_offset, stop_offset, start, stop)`.
- [x] Add `TextChange` variants:
  - [x] `ReplaceAll(text)`
  - [x] `ReplaceRange(range, text)`
- [x] Add `DocumentEdit(uri, version, changes)`.
- [x] Add `SourceSlice(text)` for stable content identity.
- [x] Add `SourceOccurrence(slice, range)` for moving range identity.
- [x] Add `AnchorId`.
- [x] Add `Anchor`.
- [x] Add `AnchorKind` variants for all semantic/source roles:
  - [x] document
  - [x] Lua opaque segment
  - [x] hosted island
  - [x] keyword
  - [x] scalar/type name
  - [x] struct name
  - [x] field name/use
  - [x] function/method name/use
  - [x] param/local name
  - [x] binding def/use
  - [x] region name
  - [x] expr fragment name
  - [x] continuation name/use
  - [x] builtin name
  - [x] packed alignment literal
  - [x] diagnostic anchor
- [x] Add `AnchorSpan(anchor, kind, label, range)`.
- [x] Add `AnchorSet(anchors)`.
- [x] Mark cache-key domain types `unique`.
- [x] Validate schema with `test_asdl_define.lua`.

### 1.2 `Moon2Mlua`

- [x] Add `IslandKind` variants:
  - [x] `IslandStruct`
  - [x] `IslandExpose`
  - [x] `IslandFunc`
  - [x] `IslandModule`
  - [x] `IslandRegion`
  - [x] `IslandExpr`
- [x] Add `IslandName` variants:
  - [x] `IslandNamed(name)`
  - [x] `IslandAnonymous`
  - [x] `IslandMalformedName(text)`
- [x] Add `IslandText(kind, name, source)`.
- [x] Add `Segment` variants:
  - [x] `LuaOpaque(occurrence)`
  - [x] `HostedIsland(island, range)`
  - [x] `MalformedIsland(kind, occurrence, reason)`
- [x] Add `DocumentParts(document, segments, anchors)`.
- [x] Add `IslandParse(island, decls, module, region_frags, expr_frags, issues,
      anchors)`.
- [x] Add `DocumentParse(parts, combined, islands, anchors)`.
- [x] Add `DocumentAnalysis(parse, host, open_report, type_issues,
      control_facts, vec_facts, back_report, anchors)`.
- [x] Ensure `DocumentAnalysis` reuses existing semantic ASDL values instead of
      duplicating them.

### 1.3 `Moon2Editor`

- [x] Add server/workspace state values:
  - [x] `ServerMode`
  - [x] `ClientCapability`
  - [x] `WorkspaceRoot`
  - [x] `WorkspaceState`
- [x] Add request/event values:
  - [x] `RpcId`
  - [x] `ClientEvent`
  - [x] `Transition(before, event, after)`
- [x] Add diagnostics:
  - [x] `DiagnosticSeverity`
  - [x] `DiagnosticOrigin`
  - [x] `DiagFromBindingResolution`
  - [x] `DiagnosticFact`
- [x] Add subject model:
  - [x] `Subject`
  - [x] `SubjectPick`
  - [x] `PositionQuery`
- [x] Add symbols:
  - [x] `SymbolKind`
  - [x] `SymbolId`
  - [x] `SymbolFact`
  - [x] `SymbolTree`
- [x] Add binding/navigation facts:
  - [x] `BindingRole`
  - [x] `BindingScopeId`, `BindingScopeKind`, `BindingScopeFact`
  - [x] `ScopedBinding`, `BindingUseSite`, `BindingResolution`, `BindingScopeReport`
  - [x] `BindingFact`
  - [x] `DefinitionResult`
  - [x] `ReferenceResult`
  - [x] `RenameEdit`
  - [x] `RenameResult`
  - [x] `PrepareRenameResult`
- [x] Add hover facts:
  - [x] `MarkupKind`
  - [x] `HoverInfo`
- [x] Add completion facts:
  - [x] `CompletionContext`
  - [x] `CompletionKind`
  - [x] `CompletionItem`
  - [x] `CompletionQuery`
- [x] Add signature-help facts:
  - [x] `SignatureContext`
  - [x] `SignatureParameter`
  - [x] `SignatureInfo`
  - [x] `SignatureHelp`
- [x] Add semantic token facts:
  - [x] `SemanticTokenType`
  - [x] `SemanticTokenModifier`
  - [x] `SemanticTokenSpan`
- [x] Add code action facts:
  - [x] `CodeActionKind`
  - [x] `TextEdit`
  - [x] `WorkspaceEdit`
  - [x] `CodeAction`
- [x] Add folding/selection/inlay facts:
  - [x] `FoldingRange`
  - [x] `SelectionRange`
  - [x] `InlayHint`
- [x] Keep LSP numeric enums out of `Moon2Editor` unless they are true semantic
      facts.

### 1.4 `Moon2Lsp`

- [x] Add protocol position/range/location payload values.
- [x] Add initialize capability/result payload values.
- [x] Add diagnostic report payload values.
- [x] Add hover payload values.
- [x] Add completion list/item payload values.
- [x] Add document symbol payload values.
- [x] Add workspace symbol payload values.
- [x] Add location/reference payload values.
- [x] Add semantic tokens payload values.
- [x] Add workspace edit/text edit payload values.
- [x] Add code action payload values.
- [x] Add folding range payload values.
- [x] Add selection range payload values.
- [x] Add inlay hint payload values.
- [x] Add `Payload` sum type covering every server response/notification payload.
- [x] LSP payload values contain protocol shapes only and do not inspect source
      text.

### 1.5 `Moon2Rpc`

- [x] Add JSON value ASDL if transport JSON is represented internally:
  - [x] null
  - [x] bool
  - [x] number
  - [x] string
  - [x] array
  - [x] object/member
- [x] Add incoming RPC envelope values:
  - [x] request
  - [x] notification
  - [x] invalid
- [x] Add outgoing RPC envelope values:
  - [x] result
  - [x] error
  - [x] notification
- [x] Add flat output commands:
  - [x] `SendMessage(outgoing)`
  - [x] `LogMessage(level, message)`
  - [x] `StopServer`
- [x] Transport types do not reference Moonlift semantic source strings except
      through already-adapted payload values.

---

## 2. Source text and position boundaries

Target files:

```text
lua/moonlift/source_text_apply.lua
lua/moonlift/source_position_index.lua
lua/moonlift/source_anchor_index.lua
```

### 2.1 Text apply

- [x] Implement `source_text_apply` over `DocumentSnapshot` and `DocumentEdit`.
- [x] Support full document replacement.
- [x] Support single range replacement.
- [x] Support multiple ordered range replacements.
- [x] Reject overlapping range edits with explicit ASDL result/diagnostic value.
- [x] Preserve URI/language and update version explicitly.
- [x] Use `pvm.with`/constructor values, never mutating snapshots.
- [x] Add tests:
  - [x] full replacement
  - [x] beginning/middle/end range edits
  - [x] multi-line edit
  - [x] UTF-8 text edit
  - [x] overlapping edits reject
  - [x] stale-version behavior is explicit

### 2.2 Position index

- [x] Implement byte offset -> `SourcePos`.
- [x] Implement `SourcePos` -> byte offset.
- [x] Track UTF-16 code-unit columns for LSP compatibility.
- [x] Track byte columns for LuaJIT/source parser compatibility.
- [x] Handle ASCII, multibyte UTF-8, and invalid byte sequences explicitly.
- [x] Add tests for:
  - [x] LF line endings
  - [x] CRLF line endings if supported
  - [x] empty document
  - [x] final line without newline
  - [x] multibyte characters before target position
  - [x] emoji/surrogate-pair UTF-16 counts
  - [x] offset at EOF

### 2.3 Anchor index

- [x] Implement `AnchorSet -> AnchorIndex` ASDL product.
- [x] Implement lookup by anchor.
- [x] Implement lookup by source position.
- [x] Implement lookup by range intersection.
- [x] Prefer most-specific anchor for position queries.
- [x] Preserve all candidate anchors for diagnostics/debugging.
- [x] Add tests for nested anchors:
  - [x] island -> function -> param
  - [x] struct -> field
  - [x] expose -> target/mode keyword
  - [x] diagnostic over malformed token

---

## 3. Workspace state and apply

Target files:

```text
lua/moonlift/editor_workspace_apply.lua
lua/moonlift/editor_transition.lua
```

- [x] Implement initial `WorkspaceState(ServerCreated, roots={}, docs={}, caps={})`.
- [x] Implement `Apply(state, Initialize(...))`.
- [x] Implement `Apply(state, Initialized)`.
- [x] Implement `Apply(state, Shutdown(...))`.
- [x] Implement `Apply(state, Exit)`.
- [x] Implement `Apply(state, DidOpen(snapshot))`.
- [x] Implement `Apply(state, DidChange(edit))` through `source_text_apply`.
- [x] Implement `Apply(state, DidClose(uri))`.
- [x] Implement `Apply(state, DidSave(uri))`.
- [x] Request events do not mutate documents unless the protocol says so.
- [x] Return `Transition(before,event,after)` for every incoming event.
- [x] Add tests:
  - [x] open/change/close single doc
  - [x] multiple open docs
  - [x] repeated open behavior explicit
  - [x] shutdown/exit behavior explicit
  - [x] request transition preserves state identity where unchanged
  - [x] changed document uses structural sharing for unchanged docs

---

## 4. `.mlua` segmentation and source-map production

Target file:

```text
lua/moonlift/mlua_document_parts.lua
```

- [x] Segment documents into `LuaOpaque`, `HostedIsland`, and `MalformedIsland`.
- [x] Match `host_quote.lua` hosted-island boundaries exactly.
- [x] Recognize top-level hosted islands:
  - [x] `struct`
  - [x] `expose`
  - [x] `func`
  - [x] `module`
  - [x] `region`
  - [x] `expr`
- [x] Recognize module-local hosted forms where currently supported.
- [x] Respect Lua comments and strings while scanning for top-level islands.
- [x] Respect long brackets/comments.
- [x] Respect antiquote splice syntax enough to avoid incorrect island end.
- [x] Distinguish malformed/incomplete island from Lua opaque text.
- [x] Produce `IslandText` keyed by kind/name/source slice without source offsets.
- [x] Produce `SourceOccurrence` and ranges for each segment.
- [x] Produce anchors for:
  - [x] island keyword
  - [x] island name
  - [x] island body range
  - [x] malformed island diagnostic range
- [x] Add tests:
  - [x] simple struct/expose/func/module/region/expr
  - [x] Lua before/between/after islands
  - [x] island inside Lua string ignored
  - [x] island inside Lua comment ignored
  - [x] long bracket string/comment ignored
  - [x] nested `end`-delimited Moonlift func/module forms handled
  - [x] `end`-terminated region/expr handled
  - [x] incomplete island produces `MalformedIsland`
  - [x] changing Lua text before island preserves `IslandText` identity

---

## 5. Island parse and document parse

Target files:

```text
lua/moonlift/mlua_island_parse.lua
lua/moonlift/mlua_document_parse.lua
```

### 5.1 Island parse

- [x] Parse `IslandText` through the existing `.mlua` parser surfaces, not a new
      parser model.
- [x] Produce `IslandParse` with explicit:
  - [x] `HostDeclSet`
  - [x] `Moon2Tree.Module`
  - [x] `RegionFrag*`
  - [x] `ExprFrag*`
  - [x] `ParseIssue*`
  - [x] anchors
- [x] Preserve parser issue ASDL values exactly.
- [x] Add source anchors for declarations produced by the parse.
- [x] Do not include source offsets in parse cache keys.
- [x] Add tests per island kind.
- [ ] Add parse-error tests for incomplete forms.
- [x] Add cache test: same island text at different document offset hits.

### 5.2 Document parse

- [x] Combine island parse products into one `MluaParseResult` equivalent to the
      existing whole-document parser result.
- [x] Preserve declaration order where semantically meaningful.
- [x] Preserve module item order where semantically meaningful.
- [x] Preserve region/expr fragment order where semantically meaningful.
- [x] Combine parse issues with source anchors.
- [x] Keep Lua opaque segments out of semantic parse results.
- [x] Add equivalence tests:
  - [x] current whole-document `mlua_parse.parse` vs segmented parse for valid
        documents
  - [ ] builders/runtime facts vs `.mlua` islands where equivalence already
        exists
  - [x] method syntax: Lua methods remain Lua; Moonlift methods are `func T:name`

---

## 6. Document analysis

Target file:

```text
lua/moonlift/mlua_document_analysis.lua
```

- [x] Consume `DocumentParse`.
- [x] Run existing host pipeline to produce `MluaHostPipelineResult`.
- [x] Include `HostReport` diagnostics.
- [x] Include `HostLayoutEnv`.
- [x] Include `HostFactSet`.
- [x] Include Lua/Terra/C emit plans from host pipeline.
- [x] Run open validation where document parse produces open slots/fragments. (module/open-use surface; standalone fragment params are not reported as open uses)
- [x] Include `Moon2Open.ValidationReport`.
- [x] Run typecheck questions that are meaningful for module/functions/regions.
- [x] Include `Moon2Tree.TypeIssue*`.
- [x] Run control-fact gathering where meaningful.
- [x] Include `Moon2Tree.ControlFact*`.
- [x] Run vector/code-shape fact gathering where meaningful.
- [x] Include `Moon2Vec.VecLoopDecision*` and explicit rejects.
- [x] Run backend validation only for objects that actually lower to backend
      programs.
- [x] Include `Moon2Back.BackValidationReport`.
- [x] Store all results in `DocumentAnalysis` ASDL.
- [x] Do not hide target model, backend selection, or feature toggles in ctx
      tables; represent them as explicit query/config ASDL if needed.
- [ ] Add tests:
  - [x] valid host struct/expose analysis has layout/access/view facts
  - [x] invalid host declarations preserve `HostReport`
  - [x] valid region/expr fragments appear in analysis
  - [ ] open slot issues appear when relevant
  - [x] type issues appear when relevant
  - [x] vector/backend rejects appear when questions are asked

---

## 7. Diagnostics

Target file:

```text
lua/moonlift/editor_diagnostic_facts.lua
```

- [x] Convert `Moon2Parse.ParseIssue` to `DiagnosticFact(DiagFromParse(...))`.
- [x] Convert `Moon2Host.HostIssue` to `DiagnosticFact(DiagFromHost(...))`.
- [x] Convert `Moon2Open.ValidationIssue` to `DiagnosticFact(DiagFromOpen(...))`.
- [x] Convert `Moon2Tree.TypeIssue` to `DiagnosticFact(DiagFromType(...))`.
- [x] Convert `Moon2Back.BackValidationIssue` to `DiagnosticFact(DiagFromBack(...))`.
- [x] Convert unresolved `BindingResolution` values to anchored `DiagnosticFact(DiagFromBindingResolution(...))` diagnostics.
- [x] Keep vector rejects as `DocumentAnalysis.vector_rejects`; do not publish them as LSP diagnostics by default.
- [x] Preserve diagnostic origin ASDL value.
- [x] Assign severity from issue variant through explicit PVM dispatch for host/type/back/binding diagnostics.
- [x] Assign code from issue variant through explicit PVM dispatch for host/type/back/binding diagnostics.
- [x] Attach source anchor through source-map facts.
- [x] Fallback missing-anchor diagnostic to island/document anchor explicitly.
- [x] No diagnostic generated from string matching on messages.
- [ ] Add tests:
  - [x] parse issue diagnostic
  - [x] duplicate decl diagnostic
  - [x] duplicate field diagnostic
  - [x] invalid packed align diagnostic
  - [x] bare bool boundary diagnostic
  - [x] open slot diagnostic
  - [x] type issue diagnostic
  - [x] backend validation diagnostic
  - [x] unresolved binding diagnostic
  - [x] source-anchored invalid binary diagnostic
  - [x] source-anchored expected-type diagnostic where a keyword/name anchor exists
  - [x] explicit backend issue code/message diagnostic
  - [ ] diagnostic origin survives into code-action query

---

## 8. Subjects and position queries

Target file:

```text
lua/moonlift/editor_subject_at.lua
```

- [x] Implement position -> anchor lookup through `AnchorIndex`.
- [x] Implement anchor -> semantic subject classification.
- [ ] Subject variants covered:
  - [x] keyword
  - [x] scalar
  - [ ] type
  - [x] host struct
  - [x] host field
  - [x] host expose
  - [x] host accessor
  - [x] tree function
  - [ ] tree module
  - [x] region fragment
  - [x] expr fragment
  - [ ] binding
  - [ ] builtin
  - [ ] diagnostic
  - [x] missing
- [x] Prefer most-specific semantic subject at nested positions.
- [x] Return `SubjectMiss` explicitly outside Moonlift islands/LSP-known builder
      contexts.
- [ ] Add tests:
  - [x] subject on struct name
  - [x] subject on field name
  - [x] subject on scalar type
  - [x] subject on expose name
  - [x] subject on function/method name
  - [x] subject on region/expr fragment
  - [ ] subject on diagnostic range
  - [x] no subject in Lua opaque text

---

## 9. Symbols

Target file:

```text
lua/moonlift/editor_symbol_facts.lua
```

- [x] Emit symbol facts for `HostDeclStruct`.
- [x] Emit field child symbols for `HostFieldDecl`.
- [x] Emit symbol facts for `HostDeclExpose`.
- [x] Emit symbol facts for `HostDeclAccessor`.
- [x] Emit symbol facts for `Moon2Tree.ItemFunc`.
- [x] Emit symbols for exported vs local functions with detail.
- [x] Emit symbols for methods using owner/name detail.
- [x] Emit symbols for `ItemType` declarations not already represented by host
      declarations.
- [x] Emit symbols for `ItemConst`.
- [x] Emit symbols for `ItemStatic`.
- [x] Emit symbols for `ItemImport`.
- [x] Emit symbols for modules.
- [x] Emit symbols for `RegionFrag`.
- [x] Emit symbols for `ExprFrag`.
- [x] Emit symbols for continuation/block labels where authored.
- [ ] Emit symbols for visible standard-library/builtin declarations where useful.
- [x] Build `SymbolTree` from parent ids.
- [x] Ensure duplicate semantic symbols are merged through explicit ids, not
      string post-filtering.
- [ ] Add tests:
  - [x] struct with fields
  - [x] expose
  - [x] top-level function
  - [x] method function
  - [ ] module-local function/region/expr
  - [ ] constants/statics/imports
  - [x] symbol tree nesting

---

## 10. Bindings, definition, references, highlights, rename

Target files:

```text
lua/moonlift/editor_binding_scope_facts.lua
lua/moonlift/editor_binding_facts.lua
lua/moonlift/editor_definition.lua
lua/moonlift/editor_references.lua
lua/moonlift/editor_rename.lua
```

### 10.1 Binding facts

- [x] Emit binding defs for host structs.
- [x] Emit binding defs for host fields.
- [x] Emit binding defs for exposes/accessors.
- [x] Emit binding defs for function params.
- [x] Emit binding defs for local/entry/control block params.
- [x] Emit source anchors for params, locals, continuations/block labels.
- [x] Emit binding defs for continuations/block labels.
- [x] Emit binding uses for type references.
- [x] Emit binding uses for field references where resolved.
- [x] Emit binding uses for function calls where resolved.
- [x] Emit binding uses for region/expr fragment uses.
- [x] Emit explicit `BindingScopeReport` facts for document/island/function/region/control scopes and scoped local bindings.
- [x] Resolve local/param/block-param uses through lexical visible ranges instead of same-island source-order only.
- [x] Resolve shadowed locals so inner definitions do not leak past their scope and do not capture their own initializer.
- [x] Resolve jump-argument labels to block/entry/continuation parameters and mark those uses as writes.
- [x] Emit read/write role distinctions for places/assignments where available.
- [x] Add tests for binding roles, shadowing, scoped rename, and continuation-parameter jump arguments.

### 10.2 Definition and references

- [x] Implement `SubjectQuery -> DefinitionResult`.
- [x] Implement `ReferenceQuery -> ReferenceResult`.
- [x] Include/exclude declaration according to query context.
- [x] Return explicit miss reason for unsupported subjects.
- [x] Use binding facts/anchors only; do not raw-text search.
- [ ] Add tests:
  - [x] type definition from type use
  - [x] field definition from field access
  - [x] function definition from call/use
  - [x] continuation definition from jump
  - [x] references include all anchored uses
  - [x] same-name continuation labels in one island remain scoped to their definition anchor
  - [x] shadowed local references resolve to the visible lexical binding
  - [x] jump-argument labels resolve to target block/continuation params
  - [x] unrelated same-name strings are ignored

### 10.3 Document highlights

- [x] Implement highlights from current-document reference facts.
- [x] Distinguish read/write/text highlight kind from `BindingRole` facts.
- [x] Add tests for local binding read/write highlights and existing field binding coverage.

### 10.4 Rename

- [x] Implement prepare-rename from `SubjectPick`.
- [x] Reject rename for missing/keyword/diagnostic/unsupported subjects.
- [x] Reject rename if binding facts do not cover every required edit.
- [x] Validate new name by subject kind.
- [x] Produce `RenameEdit*` with source ranges from anchors.
- [ ] Add tests:
  - [x] prepare-rename range
  - [x] rename struct and type uses
  - [x] rename field and field uses
  - [x] rename function/method and uses
  - [x] rename region/expr fragment and uses
  - [ ] reject rename in Lua opaque text
  - [x] reject invalid identifier
  - [x] reject scalar/builtin rename

---

## 11. Hover

Target file:

```text
lua/moonlift/editor_hover.lua
```

- [x] Implement scalar hover from `Moon2Core.Scalar`.
- [ ] Implement type hover from `Moon2Type.Type`.
- [x] Implement host struct hover from `HostStructDecl` + `HostTypeLayout`.
- [x] Include struct repr, size, align, and field count.
- [x] Implement host field hover from `HostFieldDecl` + `HostFieldLayout`.
- [x] Include field offset, size, align, exposed type, storage rep.
- [x] Include bool storage encoding for bool fields.
- [x] Implement expose hover from `HostExposeDecl` + relevant `HostFact*`.
- [ ] Include Lua/Terra/C target availability.
- [ ] Include view descriptor ABI/access plan for `view(T)` exposes.
- [x] Implement accessor hover.
- [ ] Implement function/method hover with params/result/contracts.
- [ ] Implement region fragment hover with params/open slots/continuations.
- [ ] Implement expr fragment hover with params/result/open slots.
- [x] Implement builtin hover for Moonlift standard library entries.
- [ ] Implement diagnostic hover from `DiagnosticFact` origin.
- [x] Return `HoverMissing` explicitly.
- [ ] Add tests for every hover subject variant.

---

## 12. Completion and signature help

Target files:

```text
lua/moonlift/editor_completion_context.lua
lua/moonlift/editor_completion_items.lua
lua/moonlift/editor_signature_help.lua
```

### 12.1 Completion context

- [x] Compute explicit `CompletionContext` from source anchors and parse context.
- [ ] Distinguish:
  - [x] top-level `.mlua` item
  - [ ] module item
  - [ ] struct field declaration
  - [x] type position
  - [ ] expression position
  - [ ] place position
  - [x] expose subject
  - [x] expose target
  - [x] expose mode
  - [ ] region statement
  - [x] continuation arguments
  - [x] builtin path
  - [x] Lua opaque text
  - [x] invalid/incomplete context
- [ ] Add tests for each context.

### 12.2 Completion items

- [x] Top-level completions include hosted island keywords.
- [ ] Module item completions include legal module-local declarations.
- [x] Type completions include scalars, `ptr`, `view`, known structs, aliases.
- [ ] Struct field completions include attrs/storage forms where valid.
- [x] Expose subject completions include known structs, ptr/view forms.
- [x] Expose target completions include Lua/Terra/C/Moonlift targets.
- [x] Expose mode completions include readonly/mutable/checked/unchecked/proxy
      modes where valid.
- [ ] Expr/place completions come from binding facts and visible builtins.
- [ ] Region completions include block labels, continuations, params, jump forms.
- [x] Builtin completions include `moonlift.json`, standard library names, and
      compiled builtin functions where visible.
- [x] Lua opaque text produces no fake Lua completions.
- [x] Completion item documentation comes from semantic facts.
- [ ] Add tests for each completion context.

### 12.3 Signature help

- [ ] Build signature catalog from `Moon2Tree.Func`, externs, host accessors,
      builtins, region/expr fragments.
  - [x] `Moon2Tree.Func`
  - [x] host accessors
  - [x] selected builtins
  - [x] externs
  - [x] region/expr fragments
- [x] Determine active parameter from syntax/anchors.
- [x] Return explicit miss outside known call contexts.
- [ ] Add tests:
  - [x] function call
  - [ ] method call
  - [ ] continuation jump
  - [x] region/expr fragment use
  - [x] builtin call

---

## 13. Semantic tokens

Target file:

```text
lua/moonlift/editor_semantic_tokens.lua
```

- [x] Token facts come from anchors and subjects, not Tree-sitter tokens.
- [x] Classify hosted island keywords.
- [x] Classify scalar/type names.
- [x] Classify struct names.
- [x] Classify field names.
- [x] Classify function/method names.
- [x] Classify params/bindings.
- [x] Classify continuations/block labels.
- [x] Classify builtins.
- [x] Mark declaration/definition modifiers.
- [ ] Mark readonly/mutable/storage modifiers.
- [ ] Mark exported/static modifiers.
- [x] Mark diagnostic/error tokens where anchored.
- [x] Implement full-document token spans.
- [x] Implement range token query by filtering spans.
- [x] Add LSP semantic token legend in capabilities.
- [x] Add adapter to compact LSP integer token data.
- [ ] Add tests:
  - [x] token classification snapshot
  - [x] range filtering
  - [x] stable ordering
  - [x] UTF-16 column conversion

---

## 14. Code actions

Target file:

```text
lua/moonlift/editor_code_actions.lua
```

- [x] Code actions consume `DiagnosticFact` origin values.
- [x] Implement bare boundary bool fix suggestions from
      `HostIssueBareBoolInBoundaryStruct`.
- [x] Implement invalid packed align suggestions from
      `HostIssueInvalidPackedAlign`.
- [x] Implement duplicate field/declaration navigation or rename suggestions.
- [ ] Implement unfilled open slot fill-snippet action when source anchor exists.
- [x] Implement unresolved local declaration quick fix from `DiagFromBindingResolution`.
- [ ] Implement missing/unknown type import or declaration snippet only when facts
      justify it.
- [x] Produce explicit `WorkspaceEdit` ASDL.
- [x] Reject unsupported diagnostics explicitly with no action.
- [ ] Add tests:
  - [x] bool storage fix action
  - [x] packed align fix action
  - [x] duplicate declaration action
  - [x] unresolved local declaration action
  - [ ] open slot action
  - [x] no string-message matching

---

## 15. Folding, selection ranges, inlay hints

Target files:

```text
lua/moonlift/editor_folding_ranges.lua
lua/moonlift/editor_selection_ranges.lua
lua/moonlift/editor_inlay_hints.lua
```

### 15.1 Folding ranges

- [x] Fold hosted islands.
- [ ] Fold module bodies.
- [ ] Fold function bodies.
- [x] Fold region/expr bodies.
- [ ] Fold control blocks where source spans exist.
- [ ] Fold comments only if source segmentation/anchors produce them.
- [x] Add tests for nested folds and range ordering.

### 15.2 Selection ranges

- [x] Build nested selection ranges from source anchors/spans.
- [x] Include token/name -> declaration -> island -> document nesting.
- [ ] Include expression/place/control block nesting where spans exist.
- [x] Add tests for nested selections.

### 15.3 Inlay hints

- [ ] Add result type hints where useful and not redundant.
- [x] Add parameter name hints for calls where semantic target is known.
- [ ] Add storage/layout hints only if requested by explicit config ASDL.
- [x] Add tests for hints and explicit empty result.

---

## 16. LSP payload adaptation

Target files:

```text
lua/moonlift/lsp_payload_adapt.lua
lua/moonlift/lsp_capabilities.lua
```

- [x] Adapt `DiagnosticFact* -> Moon2Lsp.DiagnosticReport`.
- [x] Adapt `HoverInfo -> Moon2Lsp.Hover`.
- [x] Adapt `CompletionItem* -> Moon2Lsp.CompletionList`.
- [x] Adapt `SignatureHelp -> Moon2Lsp.SignatureHelpPayload`.
- [x] Adapt `SymbolTree -> Moon2Lsp.DocumentSymbolList`.
- [x] Adapt workspace symbols from open-document symbol facts.
- [x] Adapt `DefinitionResult -> Location*`.
- [x] Adapt `ReferenceResult -> Location*`.
- [x] Adapt `DocumentHighlight* -> LSP document highlights`.
- [x] Adapt `PrepareRenameResult -> LSP prepare-rename range`.
- [x] Adapt `RenameResult -> WorkspaceEdit` or explicit error payload.
- [x] Adapt `SemanticTokenSpan* -> SemanticTokens`.
- [x] Adapt `CodeAction* -> LSP code action list`.
- [x] Adapt folding/selection/inlay facts.
- [x] Protocol numeric enums live here, not in semantic facts.
- [x] Position conversion uses `SourceRange` UTF-16 columns.
- [ ] Add tests for every adapter.

---

## 17. RPC decode/encode and request mapping

Target files:

```text
lua/moonlift/rpc_json_decode.lua
lua/moonlift/rpc_json_encode.lua
lua/moonlift/rpc_lsp_decode.lua
lua/moonlift/rpc_lsp_encode.lua
```

### 17.1 JSON codec

- [x] Decode JSON-RPC messages to `Moon2Rpc.JsonValue` or direct typed RPC ASDL.
- [x] Encode `Moon2Rpc.Outgoing` to JSON bytes.
- [x] Preserve JSON null explicitly.
- [x] Validate malformed JSON as `RpcInvalid`.
- [x] Do not use Moonlift indexed-tape JSON builtin as semantic source for LSP;
      transport JSON is transport only.
- [ ] Add tests:
  - [x] request with numeric id
  - [x] request with string id
  - [x] notification
  - [x] null values
  - [x] malformed JSON
  - [x] content-length framing sample body

### 17.2 LSP method decode

- [x] Decode `initialize`.
- [x] Decode `initialized`.
- [x] Decode `shutdown`.
- [x] Decode `exit`.
- [x] Decode `textDocument/didOpen`.
- [x] Decode `textDocument/didChange`.
- [x] Decode `textDocument/didClose`.
- [x] Decode `textDocument/didSave`.
- [x] Decode `textDocument/diagnostic` for pull diagnostics.
- [x] Decode `textDocument/hover`.
- [x] Decode `textDocument/definition`.
- [x] Decode `textDocument/references`.
- [x] Decode `textDocument/documentHighlight`.
- [x] Decode `textDocument/documentSymbol`.
- [x] Decode `workspace/symbol`.
- [x] Decode `textDocument/completion`.
- [ ] Decode `completionItem/resolve` if supported.
- [x] Decode `textDocument/signatureHelp`.
- [x] Decode `textDocument/semanticTokens/full`.
- [x] Decode `textDocument/semanticTokens/range`.
- [x] Decode `textDocument/prepareRename`.
- [x] Decode `textDocument/rename`.
- [x] Decode `textDocument/codeAction`.
- [ ] Decode `codeAction/resolve` if supported.
- [x] Decode `textDocument/foldingRange`.
- [x] Decode `textDocument/selectionRange`.
- [x] Decode `textDocument/inlayHint`.
- [x] Unknown methods become explicit ignored/unsupported event values.

### 17.3 LSP encode

- [x] Encode initialize result.
- [x] Encode errors with correct JSON-RPC ids.
- [x] Encode diagnostics notification/report.
- [x] Encode hover.
- [x] Encode completion list.
- [x] Encode document symbols.
- [x] Encode workspace symbols.
- [x] Encode locations.
- [x] Encode document highlights.
- [x] Encode prepare-rename ranges.
- [x] Encode signature help.
- [x] Encode semantic tokens.
- [x] Encode workspace edits.
- [x] Encode code actions.
- [x] Encode folding/selection/inlay payloads.
- [ ] Add golden tests for representative JSON payloads.

---

## 18. Output command planning and final loop

Target files:

```text
lua/moonlift/rpc_out_commands.lua
lua/moonlift/rpc_stdio_loop.lua
lsp.lua
```

### 18.1 Output command planning

- [x] Implement `Transition -> OutCommand*`.
- [x] Initialize request returns capabilities.
- [x] DidOpen plans diagnostics publish/report.
- [x] DidChange plans diagnostics publish/report.
- [x] DidClose clears diagnostics.
- [x] Hover request plans hover result.
- [x] Definition request plans location result.
- [x] References request plans references result.
- [x] Document highlight request plans highlight result.
- [x] Document symbol request plans symbol result.
- [x] Workspace symbol request plans open-document symbol result.
- [x] Completion request plans completion result.
- [x] Signature help request plans signature result.
- [x] Semantic tokens request plans token result.
- [x] Prepare-rename request plans range/null result.
- [x] Rename request plans workspace edit or error.
- [x] Code action request plans actions.
- [x] Folding/selection/inlay requests plan corresponding results.
- [x] Shutdown returns null result and updates state.
- [x] Exit emits `StopServer` only when appropriate.
- [x] Unknown request returns explicit method-not-found or unsupported result.
- [x] Unknown notification emits no semantic side effect unless specified.

### 18.2 Stdio loop

- [x] `lsp.lua` sets package path and delegates to stdio loop only.
- [x] Loop reads `Content-Length` framed messages.
- [x] Loop handles multiple messages.
- [x] Loop drains `OutCommand*` and serializes each send command.
- [x] Loop writes bytes only after ASDL payload encoding.
- [x] Loop logs through `LogMessage` or explicit stderr path.
- [x] Loop stops on `StopServer`.
- [x] Add integration tests with in-memory input/output streams.

---

## 19. Public facade and Neovim docs

- [x] Decide whether `require("moonlift").lsp` should expose LSP construction
      APIs or whether the server remains executable-only.
- [x] If exposed, add `moonlift.lsp` facade backed by ASDL/PVM modules only.
- [ ] Add Neovim config docs for `.mlua` -> Moonlift LSP.
- [x] Add docs stating `.lua` remains LuaLS territory.
- [x] Add docs stating Tree-sitter is optional editor UX.
- [x] Add docs explaining source-map scanner vs semantic facts.
- [x] Add root command example:

```bash
luajit moonlift/lsp.lua
```

- [ ] Add troubleshooting notes:
  - [ ] package path
  - [ ] working directory/root detection
  - [ ] UTF-16 position mismatch
  - [ ] LuaLS should not attach to `.mlua` by default

---

## 20. Tests and acceptance suite

### 20.1 Schema/source tests

- [x] `test_asdl_define.lua` covers new schema.
- [x] `test_source_text_apply.lua`.
- [x] `test_source_position_index.lua`.
- [x] `test_source_anchor_index.lua`.
- [x] `test_editor_workspace_apply.lua`.

### 20.2 `.mlua` source tests

- [x] `test_mlua_document_parts.lua`.
- [x] `test_mlua_island_parse.lua`.
- [x] `test_mlua_document_parse.lua`.
- [x] `test_mlua_document_analysis.lua`.
- [ ] Equivalence tests with existing `mlua_parse.lua` and hosted builders.

### 20.3 Editor semantic tests

- [x] `test_editor_diagnostic_facts.lua`.
- [x] `test_editor_subject_at.lua`.
- [x] `test_editor_symbol_facts.lua`.
- [x] `test_editor_binding_navigation.lua`.
- [x] `test_editor_binding_scopes.lua`.
- [x] `test_editor_binding_facts.lua`. (covered by `test_editor_binding_navigation.lua` and `test_editor_binding_scopes.lua`)
- [x] `test_editor_definition.lua`. (covered by `test_editor_binding_navigation.lua`)
- [x] `test_editor_references.lua`. (covered by `test_editor_binding_navigation.lua`)
- [x] `test_editor_rename.lua`. (covered by `test_editor_binding_navigation.lua`)
- [x] `test_editor_hover.lua`.
- [x] `test_editor_completion_context.lua`.
- [x] `test_editor_completion_items.lua`.
- [x] `test_editor_signature_help.lua`.
- [x] `test_editor_semantic_tokens.lua`.
- [x] `test_editor_code_actions.lua`.
- [x] `test_editor_folding_ranges.lua`. (covered by `test_editor_structure_ranges.lua`)
- [x] `test_editor_selection_ranges.lua`. (covered by `test_editor_structure_ranges.lua`)
- [x] `test_editor_inlay_hints.lua`.

### 20.4 LSP/RPC tests

- [ ] `test_lsp_payload_adapt.lua`.
- [ ] `test_lsp_capabilities.lua`.
- [x] `test_rpc_json_codec.lua` covers decode and encode.
- [ ] `test_rpc_lsp_decode.lua`.
- [ ] `test_rpc_lsp_encode.lua`.
- [ ] `test_rpc_out_commands.lua`.
- [ ] `test_rpc_stdio_loop.lua`.
- [x] `test_lsp_integrated.lua`.
- [x] `test_lsp_navigation_tokens.lua`.
- [x] `test_lsp_fragment_navigation.lua`.
- [x] `test_lsp_code_actions.lua`.
- [x] `test_lsp_signature_help.lua`.
- [x] `test_lsp_diagnostic_pull.lua`.
- [x] `test_lsp_unresolved_diagnostics.lua`.

### 20.5 End-to-end tests

- [x] Open valid `.mlua`, receive empty diagnostics and symbols.
- [x] Open invalid `.mlua`, receive parse diagnostics.
- [x] Edit to fix invalid `.mlua`, diagnostics clear.
- [x] Hover struct/field/type/expose/function/region/builtin.
- [x] Complete top-level/type/expose/region contexts.
- [x] Go to definition and references for struct/field/function/region.
- [x] Workspace symbols from open document facts.
- [x] Rename struct/field/function and verify exact edits.
- [x] Signature help and parameter inlay hints.
- [x] Semantic tokens full and range.
- [x] Code action from host diagnostic.
- [x] Close document clears diagnostics.
- [x] Shutdown/exit sequence stops loop.

---

## 21. Cache diagnostics and performance acceptance

- [ ] Add pvm report checks for unchanged island content moved by Lua text edit.
- [ ] Add pvm report checks for editing one island while unrelated islands hit.
- [ ] Add pvm report checks for host struct field edit invalidating dependent
      layout/access/view facts.
- [ ] Add pvm report checks for hover/completion/symbols reusing analysis facts.
- [ ] Add pvm report checks for source-map-only misses when ranges shift.
- [ ] Add benchmark for didChange + diagnostics on representative `.mlua` file.
- [ ] Add benchmark for hover on warm cache.
- [ ] Add benchmark for completion on warm cache.
- [ ] Add benchmark for semantic tokens on representative file.
- [ ] No manual side cache is accepted unless represented as ASDL index product.

Expected architectural cache properties:

```text
Lua text edit before unchanged island:
  source segmentation/ranges miss
  IslandText identity hit
  island parse hit
  host/layout/editor facts hit where source range is not part of the key

Struct field edit:
  changed IslandText miss
  HostDeclStruct miss
  dependent layout/access/expose hover/diagnostic facts miss
  unrelated islands hit

Position-only request after no edit:
  document analysis hit
  anchor index hit
  requested editor query computes from cached facts
```

---

## 22. Removal/avoidance checklist

- [ ] No `moonlift/lua/moonlift/lsp_asdl.lua` standalone schema.
- [ ] No scanner-only `lsp_symbols.lua` / `lsp_hover.lua` semantics.
- [ ] No JSON-RPC server that stores semantic documents in mutable Lua tables as
      the source of truth.
- [ ] No raw Lua tables as long-lived request/result semantic values.
- [ ] No string tag switching for semantic distinctions that belong in ASDL.
- [ ] No helper cache keyed by URI/version replacing PVM/ASDL identity.
- [ ] No LSP feature implemented before its semantic/editor ASDL result shape is
      defined.
- [ ] No Lua parser ownership attempt for editor semantics.
- [ ] No Tree-sitter semantic dependency.
- [ ] No Rust LSP semantic core.
- [ ] Existing root `lsp/` code is either left as historical Lua LSP prototype or
      mined only for transport tests; it is not imported as Moonlift semantics.

---

## 23. Documentation sync

- [ ] `moonlift/LSP_INTEGRATION_DESIGN.md` stays in sync with schema and file
      names.
- [ ] `moonlift/LSP_INTEGRATION_CHECKLIST.md` stays in sync with actual work.
- [ ] `moonlift/README.md` points to the LSP design and checklist.
- [ ] `moonlift/IMPLEMENTATION_CHECKLIST.md` summarizes LSP status truthfully.
- [ ] `moonlift/SOURCE_GRAMMAR.md` links any grammar/range/source-anchor changes
      that affect `.mlua` syntax.
- [ ] `moonlift/HOST_VIEW_ZERO_COPY_ABI_DESIGN.md` is updated if host facts or
      layout/access semantics change for LSP exposure.
- [ ] `AGENTS.md` is updated only if workflow/contribution rules change.

---

## 24. Final acceptance definition

The LSP integration is accepted only when all of these are true:

- [ ] `.mlua` editor behavior is driven by canonical Moonlift ASDL facts.
- [ ] Every meaningful editor-visible distinction has an ASDL value.
- [ ] Every request maps to explicit query/result ASDL.
- [ ] Every diagnostic has an origin ASDL value.
- [ ] Every hover/completion/navigation answer can be traced to compiler facts.
- [ ] Source ranges are source-map facets, not semantic identity.
- [ ] Workspace updates are pure `Apply(state,event)->state` transitions.
- [ ] The server writes only flat RPC output commands in the final loop.
- [ ] Cache behavior is validated with `pvm.report`-style tests.
- [ ] Neovim can attach Moonlift LSP to `.mlua` without LuaLS needing to parse
      Moonlift island syntax.
- [ ] Docs and checklists match implementation reality.
