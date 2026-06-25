# Lalin Debugger — Architecture Exploration 
Design a debugger for Lalin that leverages explicit typed block/jump control flow, named transitions, and ASDL-backed compiler metadata to provide a fundamentally new debugging experience — state machine navigation, transition inspection, semantic breakpoints, and reverse-step through predecessor chains.
**Started**: 2026-05-21 19:36:54
---

## Scout Output — 2026-05-21 19:38:42

I now have a comprehensive picture of the entire codebase. Here is my full scout report.

---

## Files Retrieved

### Schema Definitions (Control Flow & Type Representations)

1. **`lua/lalin/schema/tree.lua`** (full, 588 lines) — The LalinTree ASDL schema. Defines the complete AST: `ControlStmtRegion`, `ControlExprRegion`, `EntryControlBlock`, `ControlBlock`, `BlockLabel`, `BlockParam`, `EntryBlockParam`, `JumpArg`, `StmtJump`, `StmtYieldVoid`, `StmtYieldValue`, `StmtReturnVoid`, `StmtReturnValue`, `StmtTrap`, `StmtSwitch`. Also defines `ControlFact` enum with detailed facts: `ControlFactEntryBlock`, `ControlFactBlock`, `ControlFactJump`, `ControlFactJumpArg`, `ControlFactYieldVoid`, `ControlFactYieldValue`, `ControlFactReturn`, `ControlFactBackedge`, `ControlFactVariantSwitch`, `ControlFactEntryParam`, `ControlFactBlockParam`.

2. **`lua/lalin/schema/sem.lua`** (full, 101 lines) — LalinSem schema. Defines `FieldRef`, `FlowClass` (FlowUnknown, FlowFallsThrough, FlowJumps, FlowYields, FlowReturns, FlowTerminates), `ConstValue`, `TypeLayout`, `LayoutEnv`.

3. **`lua/lalin/schema/back.lua`** (full, 670 lines) — LalinBack schema. The flat backend command language: `CmdCreateBlock`, `CmdSwitchToBlock`, `CmdSealBlock`, `CmdAppendBlockParam`, `CmdBindEntryParams`, `CmdJump`, `CmdBrIf`, `CmdSwitchInt`, `CmdReturnVoid`, `CmdReturnValue`, `CmdTrap`, `CmdBeginFunc`, `CmdFinishFunc`, `CmdFinalizeModule`. Also defines `BackFlow` (FallsThrough/Terminates), `BackProvenance` types, `BackValidationIssue`, `BackInspectionReport`, `BackDiagnosticsReport`.

4. **`lua/lalin/schema/source.lua`** (full, 243 lines) — LalinSource schema. All source tracking types: `DocUri`, `DocumentSnapshot`, `SourcePos`, `SourceRange`, `AnchorId`, `AnchorKind` (15 variants including `AnchorRegionName`, `AnchorContinuationName`, `AnchorContinuationUse`, `AnchorFunctionName`, `AnchorBindingDef`, `AnchorBindingUse`, `AnchorKeyword`), `AnchorSpan`, `AnchorSet`, `AnchorIndex`, `PositionIndex`, `SourceLineSpan`.

5. **`lua/lalin/schema/editor.lua`** (full, 406 lines) — LalinEditor schema. The full LSP surface: `Subject` (SubjectContinuation, SubjectTreeFunc, SubjectBinding, SubjectRegionFrag, etc.), `SymbolFact`, `BindingFact`, `BindingScopeFact`, `ScopedBinding`, `SubjectPick`, `DefinitionResult`, `ReferenceResult`, `DiagnosticFact`, `DiagnosticOrigin`, `HoverInfo`.

6. **`lua/lalin/schema/lsp.lua`** (full, 160 lines) — LalinLsp schema. Protocol-level types: `ProtocolPosition`, `ProtocolRange`, `Location`, `DiagnosticPayload`, `Hover`, `CompletionList`, `DocumentSymbolPayload`, `SemanticTokens`.

7. **`lua/lalin/schema/pvm_surface.lua`** (full, 133 lines) — LalinPvmSurface schema for PVM phase definitions. `Producer` variants include `ProducerEmpty`, `ProducerOnce`, `ProducerConcat`, `ProducerCallPhase`, `ProducerChildren`, `ProducerLet`, `ProducerIf`.

### Provenance & Source Tracking

8. **`lua/lalin/back_provenance.lua`** (full, 105 lines) — **Critical for debugger**. `BackProvenanceMap`: reverse index from BackCmd position to source AST span. Constructed during lowering. Methods: `new()`, `record(cmd_start, cmd_end, source_range, doc_uri, name)`, `resolve(cmd_index)`, `resolve_entry(cmd_index)`, `resolve_range(start_idx, end_idx)`. Stores entries with either a fully-resolved `SourceSpan` or a `name` for later resolution via anchor index.

9. **`lua/lalin/error/span.lua`** (full, 235 lines) — `SourceSpan` type with construction (`from_source_range`, `from_offsets`, `from_token`, `from_source_text`), queries (`is_point`, `contains`, `overlaps`), and rendering (`render_snippet`, `render_multi_snippet`).

10. **`lua/lalin/error/span_resolvers.lua`** (full, 575 lines) — Static registry of per-phase span resolver functions. Each phase (parse, host, open, binding, typecheck, backend, link, vec) has a dedicated resolver. The `backend_resolver` uses the provenance map to resolve backend command indices to source spans. It tries: (1) direct span lookup via `provenance:resolve(index)`, (2) name-based resolution via anchor index, (3) named entity fields.

11. **`lua/lalin/source_position_index.lua`** (140 lines) — Builds position index from document text. Maps between byte offsets and line/column positions. Used everywhere for LSP position resolution.

12. **`lua/lalin/source_anchor_index.lua`** (111 lines) — Builds sorted index of anchors from `AnchorSet`. Supports lookup by position, range, or id. Anchors sorted by start_offset, then specificity (narrower ranges are more specific).

### Backend Infrastructure

13. **`lua/lalin/tree_to_back.lua`** (2625+ lines) — **The central lowering pass**. Tree-to-back translation. Creates `BackProvenance.new()` in `with_module_context()` (line 2541). Records provenance at item granularity (line 2604): `lower_context.provenance:record(start_idx, end_idx, nil, nil, name)`. Currently records only item-level names, NOT per-statement or per-block spans. PVM phases: `func_to_back`, `extern_to_back`, `item_to_back`, `module_to_back`.

14. **`lua/lalin/tree_control_to_back.lua`** (417 lines) — **Critical for debugger**. Lowers `ControlStmtRegion` and `ControlExprRegion` to flat `BackCmd[]`. Creates blocks with `CmdCreateBlock`, `CmdAppendBlockParam`. Generates `CmdJump` between blocks, `CmdBrIf` for if-else, `CmdSwitchInt` for switch. Generates `BackBackBlockId` with structured naming: `"ctl:{nonce}:{region_id}:{label_name}"` — this naming convention preserves semantic information across the lowering. Entry jump becomes `CmdJump(entry_block, args)`. Each block exits with `CmdSealBlock`.

15. **`lua/lalin/frontend_pipeline.lua`** (250 lines) — Batch compilation pipeline. `parse_and_lower` creates analysis context, builds anchors from scan tokens, calls `lower_module`. Attaches provenance to `analysis_ctx.back_provenance`. Key: anchors track every keyword, name, operator as `AnchorSpan` with precise byte ranges.

16. **`lua/lalin/back_jit.lua`** (150 lines) — Lua→Rust FFI bridge. `Jit:compile(program)` encodes program to binary wire format, sends to Rust via FFI. Returns `Artifact` with `getpointer(func)`, `getbytes`, `disasm`, `hexbytes`. No debug info or source mapping in the FFI layer.

17. **`lua/lalin/back_inspect.lua`** (55 lines) — Inspection of `BackProgram`. Counts command kinds, extracts memory/address/alias/pointer offset inspection records. Does NOT include any provenance or source mapping.

18. **`lua/lalin/back_diagnostics.lua`** (28 lines) — Combines inspection, vector decisions, and disassembly into a `BackDiagnosticsReport`. Calls `Jit:compile(program)` and then `artifact:disasm(func)` for native disassembly.

### LSP/Editor Infrastructure

19. **`lsp.lua`** — LSP server entry point.

20. **`lua/lalin/lsp_capabilities.lua`** — LSP capabilities JSON: supports hover, documentSymbol, diagnostics (pull), completion, signatureHelp, definition, references, documentHighlight, rename, codeAction, foldingRange, selectionRange, inlayHint, semanticTokens.

21. **`lua/lalin/rpc_lsp_decode.lua`**, **`lua/lalin/rpc_lsp_encode.lua`** — JSON-RPC message codec.

22. **`lua/lalin/rpc_stdio_loop.lua`** — STDIO event loop for LSP.

23. **`lua/lalin/editor_subject_at.lua`** (120 lines) — Picks the semantic subject at a source position. Resolves anchors to subjects: `SubjectContinuation`, `SubjectTreeFunc`, `SubjectBinding`, `SubjectRegionFrag`, `SubjectKeyword`, etc. This is the semantic "what is at this cursor position" query.

24. **`lua/lalin/editor_definition.lua`** (63 lines) — Goto-definition via binding facts.

25. **`lua/lalin/editor_references.lua`** — Find references.

26. **`lua/lalin/editor_hover.lua`** — Hover information.

27. **`lua/lalin/editor_symbol_facts.lua`** (145 lines) — Document symbols: functions, types, regions, expr fragments, continuations. Emits `SymbolFact` with ID, parent, name, kind, range. Continuation labels become `SymEvent` kind.

28. **`lua/lalin/editor_binding_facts.lua`** (260 lines) — Binding resolution: def sites, use sites, scopes.

29. **`lua/lalin/editor_semantic_tokens.lua`** — Semantic token highlighting.

30. **`lua/lalin/editor_document_highlight.lua`** — Document highlights.

31. **`lua/lalin/editor_rename.lua`** — Rename support.

32. **`lua/lalin/editor_code_actions.lua`** — Code actions.

33. **`lua/lalin/editor_folding_ranges.lua`** — Folding ranges.

34. **`lua/lalin/editor_selection_ranges.lua`** — Selection ranges.

35. **`lua/lalin/editor_inlay_hints.lua`** — Type inlay hints.

36. **`lua/lalin/editor_completion_context.lua`** — Completion context.

37. **`lua/lalin/editor_completion_items.lua`** — Completion items.

38. **`lua/lalin/editor_signature_help.lua`** — Signature help.

### PVM Framework

39. **`lua/lalin/pvm.lua`** (1200+ lines) — The recording phase virtual machine. Core primitives: `pvm.phase(name, handlers, opts)` creates recording boundaries. Phases auto-cache: on hit, replay cached array; on miss, run recording triplet that lazily evaluates and commits to cache on full drain. `pvm.one()`, `pvm.drain()`, `pvm.drain_into()` are terminals. `args_cache` option controls caching behavior (`"full"`, `"last"`, `"none"`). Phase objects also expose uncached terminals for compiler execution paths.

### Rust Backend (Cranelift)

40. **`src/lib.rs`** (240 lines) — JIT and object emission. `Jit::compile_binary(payload)` decodes wire format and emits native code. `Artifact::getpointer_by_name(name)` retrieves function pointers. No debug info support — no DWARF, no source mapping.

41. **`src/decode.rs`** (600+ lines) — Binary wire format decoder. Reads Flatline v4 encoded `BackCmd[]` into Cranelift IR. Block structure: creates Cranelift blocks, appends params, emits `jump`, `brif`, `switch`, `return`, `trap`. Trap emits `TrapCode::unwrap_user(1)` — a user-defined trap code (could be used as breakpoint mechanism).

42. **`src/wire_tags.rs`** (250 lines) — Wire tag definitions for 130+ command types. Control flow tags: `Jump (170)`, `Brif (171)`, `SwitchInt (172)`, `ReturnVoid (173)`, `ReturnValue (174)`, `Trap (175)`. Structural: `CreateBlock (1)`, `SwitchToBlock (2)`, `AppendBlockParam (3)`, `CreateStackSlot (4)`.

43. **`src/ffi.rs`** (200 lines) — C FFI exports: `lalin_jit_new`, `lalin_jit_free`, `lalin_jit_symbol`, `lalin_jit_compile_binary`, `lalin_artifact_getpointer`, `lalin_artifact_free`. No debugging or inspection APIs.

### Existing Debug Tests & Benchmarks

44. **`benchmarks/debug_fib_phi.lua`** — Debug benchmark that manually lowers a fib function, prints the body commands, and runs via DynASM JIT. Inspects the flat BackCmd[].

45. **`benchmarks/debug_fib_phi2.lua`** — Debug benchmark that traces phi lowering (DynASM path). Shows before/after command lists.

---

## Key Code Excerpts

### Control Flow in LalinTree (tree.lua)

```lua
-- A region with explicit blocks and typed transitions
A.product "ControlStmtRegion" {
    A.field "region_id" "string",
    A.field "entry" "LalinTree.EntryControlBlock",
    A.field "blocks" (A.many "LalinTree.ControlBlock"),
}

-- A jump between blocks
A.product "JumpArg" {
    A.field "name" "string",
    A.field "value" "LalinTree.Expr",
}

-- Control fact documenting every edge
A.variant "ControlFactJump" {
    A.field "region_id" "string",
    A.field "from_label" "LalinTree.BlockLabel",
    A.field "to_label" "LalinTree.BlockLabel",
}

A.variant "ControlFactBackedge" {
    A.field "region_id" "string",
    A.field "from_label" "LalinTree.BlockLabel",
    A.field "to_label" "LalinTree.BlockLabel",
}
```

### Backend Block IDs (tree_control_to_back.lua)

```lua
-- Block IDs encode region, label, and purpose
local function block_id(nonce, region_id, label)
    return Back.BackBlockId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name)
end

local function value_id(nonce, region_id, label, name)
    return Back.BackValId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name .. ":" .. name)
end

-- The text-based IDs are human-readable and encode semantic info
-- "ctl:1:fib_loop:loop:i" → block 1, region fib_loop, block label "loop", param "i"
```

### Provenance Recording (tree_to_back.lua)

```lua
-- Currently records only at ITEM granularity
local function item_name(item) ... end

-- In lower_module_direct:
for i = 1, #module.items do
    start_idx = #cmds + 1
    append_all(cmds, lower_item_direct(module.items[i]).cmds)
    end_idx = #cmds
    if start_idx <= end_idx and lower_context.provenance then
        local name = item_name(module.items[i])
        if name then
            lower_context.provenance:record(start_idx, end_idx, nil, nil, name)
        end
    end
end
```

### LSP Subject Continuation (editor_subject_at.lua)

```lua
-- A continuation is resolved from an anchor
local function continuation_subject_for_anchor(analysis, anchor)
    local subject = fact_subject_for_anchor(analysis, anchor, function(candidate)
        return pvm.classof(candidate) == E.SubjectContinuation
    end)
    if subject then return subject end
    local island = enclosing_island(analysis, anchor)
    return E.SubjectContinuation(island and island.id or S.AnchorId("document"),
                                 Tr.BlockLabel(anchor.label))
end
```

### Symbol Facts for Continuation Labels (editor_symbol_facts.lua)

```lua
-- Continuation labels (block/entry names) become document symbols
elseif a.kind == S.AnchorContinuationName then
    emit("control.label." .. a.id.text, ROOT, a.label,
         E.SymEvent, "control label", a.range, a.range,
         E.SubjectContinuation(a.id, Tr.BlockLabel(a.label)))
```

### Trap Code Generation (tree_to_back.lua + decode.rs)

```lua
-- In tree_to_back.lua, StmtTrap generates CmdTrap
[Tr.StmtTrap] = function(_, env)
    return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates))
end
```

```rust
// In decode.rs, CmdTrap becomes Cranelift trap
t if t == WireTag::Trap as u32 => {
    ctx.builder.ins().trap(TrapCode::unwrap_user(1));
}
```

---

## Relationships

### Data Flow: Source → Debug Info

```
Source text
    │
    ▼ Parse
LalinTree.Module (AST with StmtJump, StmtYield, ControlStmtRegion, etc.)
    │  ▲ Anchors built in frontend_pipeline.lua: each token gets AnchorSpan
    │  ▲  with byte range, kind (AnchorContinuationName, AnchorFunctionName, etc.)
    ▼
Typecheck → LalinTree.Module (typed)
    ▼
Layout → LalinTree.Module (memory layouts resolved)
    ▼
tree_to_back.lua: Lower → BackCmd[]
    │  ▲ Creates BackProvenance (currently item-level only)
    │  ▲ Block IDs encode: "ctl:{nonce}:{region_id}:{block_label}"
    │  ▲ Value IDs encode: "ctl:{nonce}:{region_id}:{block_label}:{param_name}"
    ▼
back_validate.lua: Validation → BackValidationIssue[]
    │  ▲ Resolved via span_resolvers.lua backend_resolver using provenance
    ▼
back_command_binary.lua: Encode → binary wire format
    ▼
back_jit.lua: FFI → Rust lalin_jit_compile_binary
    ▼
decode.rs: Decode → Cranelift IR
    │  ▲ Block→EBB, Jump→jump, BrIf→brif, SwitchInt→switch
    │  ▲ Trap→TrapCode::unwrap_user(1)
    ▼
Cranelift finalize → native machine code
```

### Key Architectural Observation: The Debug Info Gap

There is a **gap** in the provenance chain:

1. **Anchors** (in `analysis.anchors`) track every token → `AnchorSpan` with exact byte ranges. This is the richest source mapping, built during scanning.

2. **BackProvenance** is built during lowering but currently records ONLY at item level (`item_name(module.items[i])`), not at per-statement or per-block granularity. The `record()` call at line 2604 only passes a `name`, no `source_range`.

3. **Control flow labels** (`BlockLabel.name`) are preserved as text in BackBlockIds (`"ctl:1:read_loop:loop"`) which is human-readable but not machine-resolvable back to source spans.

4. **The Rust side** gets none of this — the binary wire format has no metadata for source mapping.

5. **LSP already has** `SubjectContinuation`, `AnchorContinuationName`, `AnchorContinuationUse` — the semantic types for navigating block labels are already in the editor schema.

### PVM Phase Caching for Debugger

- Phases are memoization boundaries (`args_cache: "full"`, `"last"`, or `"none"`)
- A debugger could hook into phase boundaries: re-run specific phases with modified inputs
- Currently used: `"full"` (e.g., editor definition, subject_at), `"last"` (control stmt lowering)
- On cache hit: zero work; on miss: recording triplet populates cache as side effect

---

## Observations

1. **Explicit naming everywhere is the debugger's superpower.** Every block has a label (`BlockLabel.name`), every jump has arguments (`JumpArg`), every region has a `region_id`. Block IDs in the backend are human-readable strings encoding region and label. This is richer than anything in conventional debuggers.

2. **The provenance gap is the single biggest opportunity.** Currently `back_provenance.lua` records only item-level ranges. To support per-block/per-jump source mapping, the `record()` calls in `tree_to_back.lua` and `tree_control_to_back.lua` would need to pass source ranges for each block, jump, yield, and return statement.

3. **Cranelift's `TrapCode::unwrap_user(1)`** is already generated for `StmtTrap`. This could be used as a breakpoint mechanism — insert `CmdTrap` at desired locations, and handle the trap signal. The user trap code (1) is arbitrary and could encode breakpoint IDs.

4. **AnchorContinuationName** anchors exist for every `block` and `entry` keyword in source. Combined with the existing `SubjectContinuation` editor type, the LSP already has the semantic vocabulary for block navigation — it's just not connected to a runtime debugger.

5. **The LSP capabilities are rich** but purely static (hover, goto-def, references, symbols, semantic tokens). There is no runtime debugging capability. The existing infrastructure (RPC, STDIO loop, JSON codec, editor transition state machine) could host debug adapter protocol (DAP) messages alongside LSP.

6. **PVM as debugger hook.** Since every phase is a cache boundary, a debugger could intercept `pvm.phase` by wrapping the handlers: on miss, pause execution and present the AST node to the user. The recording triplet mechanism already supports laziness — a "step through compilation" debugger is architecturally feasible.

7. **Reverse-step is structurally available.** `ControlFactJump` records `from_label` and `to_label`. By following predecessor chains through the ControlFact set, a debugger can enumerate all paths that reach a given block — enabling reverse-step without any runtime recording.

8. **No interactive REPL or step execution mode exists.** `lalin run --call main file.mlua` compiles and runs — no interactive pause. The pipeline is batch-only.

9. **The Rust side has zero debug info.** No Cranelift `ValueLabel` assignments, no `debug_collected_types`, no DWARF output. All debug knowledge lives in Lua ASDL types and provenance maps. A debugger would need to either: (a) keep all debugging logic in Lua, hooking program counter → command index → provenance → source span, or (b) extend the binary wire format with debug metadata that Rust passes through to Cranelift's debug infrastructure.

10. **Semantic breakpoints** are natural in the Lalin paradigm. Instead of "break at line 42", a user could say "break when block `loop` is entered with `i > 5`" or "break on transition from `read_block` to `done`". The `ControlFact` system already knows every edge.

11. **The `FlowClass` enum** (`FlowJumps`, `FlowYields`, `FlowReturns`, `FlowFallsThrough`, `FlowTerminates`) in the sem schema provides statement-level flow classification that a debugger could use to understand control flow without parsing.

12. **BackProvenance already supports `resolve_range()`** which merges multiple entries to produce the encompassing span. This is exactly what a debugger needs to map from native PC range back to a source region.

## Knowledge-builder Output — 2026-05-21 19:40:55

Now I have a thorough understanding of the codebase. Here are my second-order observations.

---

## What Matters Most for This Problem

The debugger design must reconcile three fundamental tensions:

1. **The provenance gap is not uniform** — it affects different debugging features in qualitatively different ways. Breakpoints need it moderately (where in source did this code come from), variable inspection needs it critically (this value has what name and type), and reverse-step needs it structurally (predecessor chains are already there, just not connected).

2. **The architecture has two parallel universes** — the Lua ASDL side (rich, semantic, connected) and the Rust Cranelift side (dumb, fast, zero metadata). The debugger's fundamental design question is where to locate the debugging intelligence, not whether to have it.

3. **Lalin's explicit control flow is both the problem and the answer** — it creates a debugging paradigm that no traditional debugger can offer, but it also means conventional debugger assumptions (step-over, step-into, line-granularity) don't map naturally.

---

## Non-Obvious Observations

### 1. The Provenance Gap Has a Hidden Asymmetry

The scout noted that BackProvenance records at item-level only, but the *type* of provenance that's missing differs by feature:

- **Breakpoints**: Need `(native PC range → source line/column)`. Current item-level entries give `(cmd_range → function_name)`, which is almost useless for line breakpoints. But the human-readable BackBlockIds (`"ctl:1:fib_loop:loop"`) encode block labels that could be hashed to source positions via the anchor index. This is *finer-grained than items but less precise than spans* — a "medium-fidelity" provenance that exists today but isn't formalized.

- **Variable inspection**: Needs `(BackValId → Binding → Type + SourceRange)`. The BackValId naming scheme (`"ctl:1:fib_loop:loop:i"`) embeds the variable name and its containing block, which is enough to cross-reference against the binding facts in the editor schema. This means variable inspection provenance is **already structurally available, just not in a queryable format** — you'd need a reverse index from BackValId to Binding, which doesn't exist.

- **Stepping**: Needs the finest granularity — every individual `BackCmd` must map to a source range. This is where the gap is most severe, because item-level provenance gives you a function scope but no way to determine *which* CmdJump corresponds to *which* `jump` keyword in source. The `tree_control_to_back.lua` lowering code creates the CmdJump at line 171 (`cmds[#cmds + 1] = Back.CmdJump(target.block, args)`) but never records the source position of the `jump` keyword.

- **Reverse-step through predecessors**: Paradoxically, this is the *least* affected by the provenance gap. The ControlFact system already knows every edge (`ControlFactJump(from_label, to_label)`), and the backend block IDs preserve region/label structure. Reverse-step is a pure graph traversal problem — you don't need source positions, you need CFG structure, which is already explicit in the ASDL.

### 2. The PVM Cache as a Debugger Architecture

The PVM caching system (pvm.lua) has a property the scout didn't notice that fundamentally changes what a "step-through-compilation" debugger looks like:

Each phase is a *recording triplet* that caches its entire output on full drain. A debugger that hooks into phase boundaries would have a *dual view*: it could either intercept the recording process (watch the compiler build its output incrementally) OR inspect the cached output after the fact (examine the tree after typechecking, before lowering).

But the critical insight is this: **misses in one phase trigger misses in dependent phases**, and the PVM fuses adjacent misses into a single pass. If you pause at a phase boundary, you're not just pausing one computation — you're preventing the fused trace from being created, which means *all* downstream phases recompute from scratch. The overhead of "step through compilation" is O(n * m) where n is the number of phase boundaries and m is the recomputation cost.

The `args_cache` option (`"full"`, `"last"`, `"none"`) matters here. Phases with `args_cache = "full"` cache by all arguments, so replaying with the same inputs is a hash lookup. Phases with `args_cache = "last"` only cache the last invocation — re-running with different args always misses. A debugger that modifies state between phases would break the "last" cache assumption silently.

### 3. The Wire Format as a Debug Metadata Channel (or Not)

The binary wire format is a Flatline v4 stream of 4-byte-aligned slot arrays. Every command is `[tag:u32, slot0:u32, slot1:u32, ...]`. The decoder (`decode.rs`) reads through these linearly, constructing Cranelift IR.

Key observation: **the wire format has no concept of "section" or "metadata"**. There's no container structure, no optional sections, no key-value pairs. Adding debug metadata would require either:

1. **New tags** — e.g., `CmdSourceLoc(tag=200, source_offset)` that the Lua encoder inserts between Cmds and the Rust decoder stores in a side table. This is the simplest approach but breaks the "one tag per Cranelift operation" invariant.

2. **A parallel metadata stream** — a separate byte sequence alongside the function body that maps command indices to offsets. But the decoder doesn't keep command indices — it processes tags sequentially and discards position info.

3. **Encoding offsets into block/value IDs** — the human-readable IDs are currently discarded during encoding (`renumber()` assigns fresh numeric IDs). But if the numeric IDs were synthesized to encode source information (e.g., top bits encode region_id), they'd be preserved through the Rust side without any format change.

Option 3 is worth examining: the Lua `renumber()` function currently assigns sequential u32s to each textual ID. If instead it encoded block identity into the numeric range (e.g., region 1 blocks = 1000-1999, region 2 blocks = 2000-2999), the Rust side would get block identity for free. But Cranelift doesn't expose this to the generated code in any useful way — blocks are ephemeral within the function builder.

### 4. The Continuation Name Bridge Between LSP and Debugger

This is the most important architectural bridge that's already built but unused:

- `AnchorContinuationName` is a source anchor kind (1 of 15) that fires on every `block` and `entry` keyword
- `SubjectContinuation(anchor_id, BlockLabel(label))` is the semantic subject for any cursor position on a block name
- `SymEvent` is the document symbol kind for continuation labels (treated as events, not functions)
- BackBlockIds preserve the same label names in the backend

This means: **the LSP already knows how to answer "at this cursor position, which block/region am I in?"**, and the backend knows blocks by the same name. The missing piece is a cross-reference from backend command index to continuation anchor. If this cross-reference existed, a debugger could answer "which block is currently executing?" from the native PC level in O(log n) time — far richer than any traditional debugger's "which function are we in?"

### 5. The Implicit Invariant: Every Block Path Must Terminate

The `tree_control_to_back.lua` lowering explicitly checks that every control block body has terminating flow:

```lua
if flow ~= Back.BackTerminates then
    unsupported_stmt(body_env, body_cmds, "control block can fall through without jump/yield/return")
end
```

This invariant has a profound consequence for debugging: **the CFG is guaranteed to be well-structured in a way that general-purpose CFGs are not**. There are no implicit fall-through paths, no exception edges, no implicit returns. The graph is a DAG (or a set of explicit cycles via backedges). This means:

- Predecessor chains are always finite and enumerable
- There are no "phantom" paths that the debugger didn't know about
- Backedge detection (the `ControlFactBackedge` fact) explicitly annotates cycles — the debugger can distinguish loop iteration from sequential execution without heuristics

The `ControlFactBackedge` variant is particularly important: it fires when a jump target equals the entry label of the region (re-entry loop) or the block's own label (self-loop). This is the *only* way control flow cycles. A debugger that detects backedge transitions could implement "step over loop iteration" natively — no frame counting, no breakpoint patching.

### 6. FlowClass Is Not What It Seems

The scout noted `FlowClass` (`FlowJumps`, `FlowYields`, `FlowReturns`, `FlowFallsThrough`, `FlowTerminates`) in the sem schema. But look more closely at where it's used:

- In `tree_control_to_back.lua`, the lowering only checks `Back.BackTerminates` vs `Back.BackFallsThrough` — the coarser backend flow enum.
- `FlowClass` is declared in the sem schema but is ONLY used in `StmtHeader.StmtFlow` — it's attached as a statement header annotation during typechecking.
- This means `FlowClass` decorates *source-level statements*, not backend commands. It's available *after typechecking but before lowering*.

The implication: `FlowClass` enables statement-level debugging in the *typechecked AST*, not in the backend. A debugger that operates at the AST level (step through typechecked statements) can use `FlowClass` to know what kind of control transfer each statement performs WITHOUT consulting the backend. This is a completely different debugging model from native-code debugging — it's a "structured stepping" model where the debugger traverses the LalinTree AST and uses `FlowClass` to determine what to do after each statement.

Concretely:
- A `StmtFlow(FlowJumps)` statement is a `jump` — stepping "over" it means following the jump to the target block in the same region.
- A `StmtFlow(FlowYields)` statement is a `yield` — stepping "over" means exiting the region.
- A `StmtFlow(FlowFallsThrough)` statement is something like a `let` or `var` — stepping "over" means moving to the next statement in the same block.

This "structured AST debugging" is architecturally distinct from "native PC debugging" and could exist independently — much like how the LSP's symbol navigation exists independently of runtime execution.

### 7. The Batch-Only Pipeline Has a Hidden Constraint

The scout noted "no interactive step/run/pause mode." But the constraint is deeper than just "not implemented yet":

The pipeline is `parse → typecheck → layout → lower → validate → encode → JIT`. Each step is synchronous and completes before the next starts. The Rust JIT (`compile_binary`) is a single FFI call that compiles the entire wire format in one shot.

For an interactive debugger, you need to either:
1. **Insert traps before compilation** — modify the `BackCmd[]` array to include `CmdTrap` at breakpoint positions, then compile. But you can't modify and recompile without re-running the entire pipeline.
2. **Insert traps after compilation but before execution** — this requires modifying native code in memory, which Cranelift's JIT doesn't support (no `set_trap` API, no relocation).
3. **Use signal handling on deployed code** — since `CmdTrap` generates `TrapCode::unwrap_user(1)`, and Cranelift JIT modules can register trap handlers, you could catch the trap signal, inspect state, and resume. But Cranelift's JIT doesn't support single-stepping or state inspection at trap sites.

Option 1 is the most viable but means: **every breakpoint requires a full recompile**. This is expensive but potentially acceptable if the PVM cache makes partial recompilation fast (only the lowering and later phases rerun if editing hasn't changed the AST).

### 8. The ControlFactSet as a Debugger Database

The `ControlFactSet` (produced by `tree_control_facts.lua`) is structured as a flat list of `ControlFact` variants documenting every edge in a region. But it has a key architectural property that makes it act like a debugger database:

```lua
Tr.ControlFactJump(region_id, from_label, stmt.target)
Tr.ControlFactJumpArg(region_id, from_label, stmt.target, args[i].name, expr_ty(args[i].value))
Tr.ControlFactBackedge(region_id, from_label, stmt.target)
```

These facts are **immutable, deduplicated, and indexed by region**. They form a complete static analysis of the control flow graph. A debugger could:

- Query: "what blocks can transition to block X?" → filter `ControlFactJump` by `to_label`
- Query: "what values flow into block X's parameter Y?" → filter `ControlFactJumpArg` by `to_label + name`
- Query: "is this transition a backedge (loop)?" → check for `ControlFactBackedge`

But crucially: **the ControlFactSet is computed during typechecking, not during lowering**. It's attached to the `ControlDecisionReducible` verdict. This means it exists before the backend is involved at all. A debugger that operates at the AST level could use the ControlFactSet without ever touching the backend provenance map.

This creates two tiers of debugger capability:
- **Tier 1** (AST-level, no execution): Navigation, block inspection, transition tracing, semantic breakpoint conditions — all from ControlFactSet + anchors
- **Tier 2** (Native-level, with execution): Hit counters, PC mapping, runtime value inspection — requires provenance + trap handling

### 9. The Jump-First Model Changes "What Does It Mean to Step?"

In conventional debuggers, "step over" means: execute the current line and stop at the next line in the same function. "Step into" means: if the current line contains a function call, stop at the first line of that function.

In Lalin, these concepts don't map cleanly:

- There are no nested calls in control flow — `jump` and `yield` are top-level, not inside expressions (well, `jump` is a statement, not an expression).
- "Step over" a `jump loop(i = i + 1, acc = acc + n)` means: evaluate the jump arguments (`i + 1`, `acc + n`) and then transition to block `loop` with the new parameter values. This is NOT the same as "advance to next statement" — you're re-entering the same syntactic block with different values.
- "Step into" doesn't exist for control flow — there's nothing to "enter" because `jump` doesn't call a function, it transfers to another block in the same region.
- "Step out" of a region means following a `yield` or `return` to the enclosing context.

The jump-first model replaces the call-stack-based stepping model with a **state-machine navigation** model. The relevant debugger primitives would be:
- **"Advance one transition"**: execute one `jump`, one `yield`, or one `return`
- **"Advance one evaluation"**: complete evaluation of jump arguments and bind them to the target block's parameters
- **"Complete block"**: run through all statements in the current block until a terminating statement (jump/yield/return)
- **"Complete region"**: follow transitions until a yield or return exits the region

These are fundamentally different from PC-based stepping because the unit of execution is the *block transition*, not the *instruction*.

### 10. The LSP Already Is (Half of) a Debugger

Compare what the LSP provides vs. what a debugger needs:

| LSP Feature | Debugger Equivalent |
|---|---|
| `SubjectContinuation(anchor_id, label)` | "Which block is at cursor?" |
| `SymbolFact(_, SymEvent, "control label", range)` | "List all blocks in this function" |
| `ControlFactJump(region, from, to)` | "Predecessor/successor query" |
| `AnchorContinuationName` anchor at block keyword | "Source position of block definition" |
| `editor_subject_at(position)` | "What semantic object is at this PC?" |
| `editor_definition(label)` | "Where is this block definition?" |
| `editor_references(label)` | "What jumps target this block?" |
| `HoverInfo` via binding facts | "What type/value is this variable?" |
| `DiagnosticFact` with source ranges | "What errors exist at this PC?" |

The LSP already answers every static query a debugger would ask *about the source and the program structure*. What it can't answer is:
- Native PC → source mapping (provenance gap)
- Runtime values (no execution)
- Symbolic values at block entry (requires runtime or simulation)

This means: **a static debugger (source navigation, breakpoint definition, state machine visualization) is already 80% built**. The remaining 20% is the provenance cross-reference and the execution engine.

### 11. The Cranelift Debug Info Vacuum Is More Complete Than It Looks

The `grep` for `ValueLabel`, `debug_collected_types`, and `source_loc` in `src/` returned zero results. This isn't just "no debug info" — it's **no debug infrastructure at all**:

- No `cranelift_codegen::ir::ValueLabel` assignments (which would let you name SSA values for debuggers)
- No `debug_collector` or `DebugInfo` in the compile pipeline
- No `source_loc` metadata on Cranelift instructions
- No `disasm` output with source annotations
- No `DWARF` section in object output

The `opt_level` is set to `"speed"` in `lib.rs`, which is the Cranelift setting that most aggressively optimizes away debug info. Cranelift has debugging APIs (`debug_collected_types`, `ValueLabel`, `source_location` metadata), but they're all disabled by default and require explicit opt-in.

Adding debug info to the Cranelift backend means:
1. Passing source locations through the decoder (`decode.rs`)
2. Calling `set_source_location()` on Cranelift instructions
3. Assigning `ValueLabel` to Cranelift values
4. Setting `opt_level` to `"speed_and_size"` or a debug mode
5. Potentially collecting debug info via Cranelift's `DebugInfo` collector

Each of these is individually straightforward but collectively they add complexity to the wire format, the decoder, and the JIT pipeline — and they all slow down compilation.

### 12. The Nonce-as-Identity Pattern Creates a Debugger Query Problem

In `tree_control_to_back.lua`, every region gets a unique `nonce` (a monotonically increasing counter):

```lua
local nonce_env, nonce_id = base.env_next_block(env, "ctl.region")
local nonce = nonce_id.text
```

This nonce is embedded in every BackBlockId and BackValId for the region. It's used to ensure uniqueness when multiple regions would otherwise have blocks with the same label name.

For debugging, the nonce is both essential and problematic:
- **Essential**: Without it, you couldn't distinguish block "loop" in two different functions
- **Problematic**: The nonce is a compile artifact with no source correlation. There's no way to go from "nonce=7" back to "the third function in the module" without the provenance map

But more subtly: the nonce identifies the *region lowering*, not the *region*. If the same region is lowered twice (e.g., across PVM cache invalidations), it gets a *different* nonce. This means BackBlockIds from different compilation sessions are incomparable — you can't persist them across debugger sessions.

### 13. The Backedge Fact Creates a "Natural Loop" Debugging Primitive

`ControlFactBackedge` fires when a jump target equals the *entry label* of a region. This is Lalin's equivalent of "looping back to the start":

```lua
if labels_equal(stmt.target, from_label) or labels_equal(stmt.target, entry_label) then
    facts[#facts + 1] = Tr.ControlFactBackedge(region_id, from_label, stmt.target)
end
```

This has a surprising implication for debugging: **backedge detection is syntactic, not heuristic**. A conventional debugger has to use PC range comparisons or loop detection heuristics to determine if a particular branch is a backedge. Lalin's debugger knows statically, from the ASDL, whether any particular `jump` is a backedge.

This enables a "loop iteration counter" primitive with zero runtime cost:
- Before execution: scan ControlFactSet for `ControlFactBackedge` → these are the only re-entrant transitions
- At runtime: increment a counter whenever a backedge transition happens
- Semantic breakpoint: "break when backedge `loop→loop` has fired 10 times"

No conventional debugger can do this without either (a) sampling heuristics or (b) expensive event filtering.

### 14. The Three Representations Create a Triangulation Problem

There are three representations of control flow in the system, and a debugger must reconcile all three:

| Representation | Where | Granularity | Key Identifiers |
|---|---|---|---|
| **LalinTree** (AST) | After typecheck | Statements + blocks | `BlockLabel(name)`, `region_id` |
| **ControlFactSet** | After typecheck | Edges + params | Same labels, annotated with facts |
| **BackCmd[]** | After lowering | Flat commands | `BackBlockId("ctl:nonce:region:label")` |

The AST representation has `BlockLabel(name)` with no nonce. The backend representation has `BackBlockId("ctl:1:region:label")` with a nonce. The ControlFactSet uses the AST labels.

A debugger that wants to map a native PC back to a source position must:
1. Map PC → command index (via something — currently nothing exists for this)
2. Map command index → BackBlockId (via the flat command stream — which doesn't record block identity for individual commands either)
3. Map BackBlockId → BlockLabel (textually straightforward: strip the nonce and prefix)
4. Map BlockLabel → source range (via anchor index)

Step 2 is the real problem: `CmdCreateBlock` and `CmdJump` reference blocks by BackBlockId, but the intervening commands (arithmetic, loads, stores) have no block annotation. They *execute inside* a block, but there's no mapping from "these 50 commands are inside block X."

This means: **even with a perfect provenance map, you can't determine which source block a random arithmetic command belongs to** unless you also track block boundaries through the lowering.

---

## Knowledge Gaps

1. **How do other jump-first languages (BIR, MLIR regions) handle debugging?** I know Rust's MIR has a similar block-based structure. Looking at how LLVM debug info handles basic-block-level metadata would be informative — specifically, does LLVM emit DWARF at the basic block level, and if so, how do debuggers use it? I need to understand what's standard practice.

2. **Can Cranelift's trap handler inspect registers/stack at the trap site?** The `TrapCode::unwrap_user(1)` generates a `ud2` or equivalent. On x86-64, this triggers SIGILL. A signal handler could inspect registers via `ucontext_t`. But does Cranelift's JITModule expose any API for this, or would it be manual signal handling? This needs investigation of Cranelift's trap handling infrastructure.

3. **What does the PVM's `args_cache = "last"` mean for stateful debugging?** If the debugger modifies something (e.g., inserts a trap command) and re-lowers, does the `args_cache = "last"` phase return stale results? The cache key is the argument identity — would adding a CmdTrap change the argument identity? This needs code reading in `pvm.lua` around the cache key computation.

## Approach-proposer Output — 2026-05-21 19:43:06

Based on the comprehensive scout and knowledge-builder analysis, here are three genuinely distinct architectural approaches for a Lalin debugger.

---

### Approach A: The Semantic Block-Trace Debugger

**Core philosophy**: Debug at the block transition level, not the instruction level — the jump-first model makes blocks the natural unit of execution, and existing ASDL metadata already describes the entire state machine.

**Architecture overview**:
- **Intelligence**: Lives entirely in Lua. The debugger is a Lua module that sits between the lowered `BackCmd[]` and the Rust JIT.
- **Data flow**: `BackCmd[]` → debugger instruments with `CmdTrap` at block entries → Rust JIT compiles → signal handler catches traps → returns to Lua → Lua inspects block and its parameters → user decides next action → Lua sends "resume" command → Rust continues
- **Key insight**: The debugger never needs to understand native PC addresses. It works at the `BackBlockId` level, which already encodes `"ctl:{nonce}:{region}:{block}"`. The trap handler simply returns "which block just fired" to Lua, and Lua does everything else.

**Stepping model** — Block transitions as primitives:
- **Step block**: Execute one block from entry to its terminating jump/yield/return. Stop at the *target* block boundary (before executing it).
- **Step into region**: When hitting a `yield` that exits to a parent region, follow the continuation into the parent region's next block.
- **Step out of region**: Continue executing until the current region exits via yield or return.
- **Step over loop iteration**: `ControlFactBackedge` tells us which jumps are loop repeats. "Step over loop" means continue until a non-backedge jump fires.
- **Continue**: Resume until next breakpoint.

**Breakpoint model** — Semantic conditions on block labels:
- Breakpoints are *not* source line—based. They are block-label—based: `break on block "loop" in region "fib"`.
- Conditional: `break on block "loop" when param i > 100`.
- The debugger stores a table of `{nonce, region, block_label, condition_fn}`. Before each trap resume, it checks conditions in Lua.
- To set a breakpoint: the debugger re-lowers the program with an extra `CmdTrap` inserted at the target block's first command. PVM caches make this fast — only the lowering and later phases rerun.
- To clear a breakpoint: re-lower without the `CmdTrap`. Same PVM cache benefit.

**Provenance model**:
- Two-level provenance that the scout noted as missing:
  1. **Block-level**: In `tree_control_to_back.lua`, record a `BackProvenance` entry for each `CmdCreateBlock` → `BlockLabel` → source anchor. This is a single `record()` call per block.
  2. **Parameter-level**: Extend `BackValId` to carry `BlockParam.name` (already there textually: `"ctl:1:fib:loop:i"`). Build a reverse index from these names to `Binding` facts from the editor schema.
- The Rust side needs zero provenance knowledge. It just catches traps and reports the running function's PC. Lua resolves PC → block via the sorted command index (binary search on the `BackCmd[]` array, using the block boundary map).

**LSP integration**:
- Tight integration: the existing LSP already provides `SubjectContinuation`, `AnchorContinuationName`, and `ControlFact` queries. The debugger adds a DAP server (Debug Adapter Protocol) as a second JSON-RPC handler alongside the LSP server in the same STDIO loop.
- The DAP `"setBreakpoints"` request translates: source line → anchors → `AnchorContinuationName` → `BlockLabel` → region ID → sets breakpoint in the debugger's condition table.
- The DAP `"stackTrace"` request returns the current block chain (which regions contain which blocks), not a call stack. This is semantically different — it's a "breadcrumb trail" of block transitions, not function calls.
- Variable inspection uses `HoverInfo`-equivalent: block params → binding facts → type info → runtime value (from trap-register dump, mapped via block param layout).

**What it enables that other approaches can't**:
- **Semantic queries at breakpoints**: Because conditions are Lua closures evaluated in Lua, a user can write `break when i > fib(n-1)` — full Lua expressiveness, not just simple expression evaluation.
- **State machine visualization**: The debugger can dump the entire current region's CFG with the current block highlighted, using the ControlFactSet. This is a natural UI that no traditional debugger offers.
- **Zero Rust changes for debug info**: The Rust side needs exactly one new API: `trap_handler(callback)` that fires on `TrapCode::unwrap_user(1)` and can resume execution. That's ~20 lines of Rust.

**What it sacrifices or leaves hard**:
- **Performance under stepping**: Every block transition triggers a trap → Lua round-trip. For a tight loop (`jump loop(i = i + 1)`), this is a block boundary every ~4 instructions. Stepping through a 1M iteration loop would be 1M trap round-trips — unusable.
- **No PC-level debugging**: Can't step through individual arithmetic instructions. If a `let` binding computation is wrong, you can't pinpoint which sub-expression failed. You only know which block failed.
- **Single-threaded**: The trap handler suspends the entire JIT. Concurrent Lalin execution would need per-thread trap state.
- **Recompilation cost for breakpoints**: Even with PVM caches, each breakpoint add/remove forces re-lowering, re-encoding, re-JIT. For rapid toggle (hit breakpoint, disable it, continue), this is slow.

**Rough implementation cost**:

| Phase | Files | Cost |
|-------|-------|------|
| 1. Block-level provenance | `tree_control_to_back.lua` — add `provenance:record()` per `CmdCreateBlock` | ~5 lines |
| 2. Rust trap handler API | `src/lib.rs`, `src/ffi.rs` — add `set_trap_handler()` callback, resume mechanism | ~30 lines Rust |
| 3. Trap instrumentation | New `lua/lalin/debug_instrument.lua` — walk `BackCmd[]`, insert `CmdTrap` at block entries | ~80 lines |
| 4. Debugger core | New `lua/lalin/debugger.lua` — breakpoint table, stepping logic, condition eval | ~300 lines |
| 5. DAP server | New `lua/lalin/dap_server.lua` — DAP protocol parser/handler alongside LSP | ~400 lines |
| 6. LSP→DAP bridge | Extend `editor_subject_at.lua`, `editor_symbol_facts.lua` — expose block→line mapping for breakpoint resolution | ~50 lines |

**Total**: ~900 lines Lua, ~30 lines Rust. Self-contained, minimal upstream changes.

---

### Approach B: The Self-Hosted Native Debugger

**Core philosophy**: Make Lalin generate debuggable native code with full DWARF and ValueLabel support, then use existing debuggers (LLDB/GDB) via a Lalin DAP adapter — leverage the entire LLVM debug ecosystem without reinventing any stepping logic.

**Architecture overview**:
- **Intelligence**: Split — Rust side handles all DWARF generation and native debugging infrastructure; Lua side provides Lalin-specific semantic queries via the LSP.
- **Data flow**: Same `BackCmd[]` pipeline, but the Rust decoder and Cranelift JIT emit debug metadata inline: `source_location` on every instruction, `ValueLabel` on every SSA value, and a DWARF `.debug_info` section in object output (or in-memory for JIT). The JIT registers the debug info with a custom debug registrar that LLDB can attach to.
- **Key insight**: Instead of building a custom debugger, extend Lalin to produce standard debug info formats. Then LLDB/GDB provide stepping, variable inspection, backtraces, memory inspection — for free. A thin Lalin DAP wrapper translates between Lalin concepts (block labels, regions) and the native debugger's view (functions, lines, variables).

**Stepping model** — PC-level with Lalin semantic overlay:
- The native debugger provides standard step-over/step-into/step-out at the instruction level.
- The DAP adapter adds semantic stepping on top: it queries LSP to determine "what Lalin construct is at the current PC" and overrides the debugger's step behavior.
- Example: "step over" in Lalin means "execute until the next block boundary." The adapter sets a temporary breakpoint at all successor blocks' entry PCs and resumes. When one hits, it removes the other temporary breakpoints.
- Loop detection: The adapter uses `ControlFactBackedge` to identify loop edges. "Step out of loop" = set breakpoint at all successor blocks that are *not* backedges.

**Breakpoint model** — DWARF source-line mapping with Lalin overlay:
- Primary: standard source-line breakpoints via DWARF line number information. The Rust decoder emits a `.debug_line` section mapping every Cranelift instruction to a source line.
- Secondary: semantic breakpoints (block labels, region entries) resolved via LSP to source ranges, then to line numbers, then to DWARF entries. A `break on block "loop"` becomes a breakpoint at the source line of the `block loop(...)` keyword.
- Conditional breakpoints delegate to LLDB's expression evaluation (LLDB can evaluate C expressions against the running process). This requires Lalin to expose block parameters as named variables in the DWARF info.

**Provenance model** — Full Cranelift debug info:
- `source_location` per instruction: The Rust decoder receives a parallel stream of source positions alongside the command stream. Each `BackCmd` encoder inserts a `CmdSourceLoc(source_span_encoded)` before the command. The decoder calls `inst.set_source_location(loc)` for every Cranelift instruction.
- `ValueLabel` per SSA value: The Lua encoder sends value names as part of the `BackValId` encoding. The Rust decoder calls `func.declare_var(value, ValueLabel::new(name))` — Cranelift preserves these through optimization and maps them to DWARF `DW_TAG_variable`.
- Object emission: When emitting `.o` files, include full `.debug_info`, `.debug_line`, `.debug_abbrev` sections. This enables post-mortem debugging with `gdb lalin_program core` or `lldb -c core.dump`.
- This requires Cranelift's `opt_level` to be `"speed_and_size"` or `"debug"` to preserve debug metadata through optimizations.

**LSP integration**:
- Complementary, not merged. LSP handles static queries (hover, goto-def, references, document symbols). The DAP adapter handles runtime queries.
- They share data through a common "Lalin context" that maps source ranges ↔ block labels ↔ binding facts. Both the LSP server and the DAP adapter read from the same `analysis_ctx` structure.
- The DAP adapter is a separate process or thread that communicates with LLDB/GDB via its native protocol (MI for GDB, lldb-python for LLDB), and with the editor via DAP.

**What it enables that other approaches can't**:
- **Full native debugging**: Core dumps, memory inspection, register inspection, assembly view, profiling — everything standard debuggers offer, but for Lalin-compiled code.
- **Performance under stepping**: LLDB's breakpoint handling is highly optimized — single-stepping with `si` can do millions of instructions per second. No Lua round-trip overhead.
- **Multi-language debugging**: If Lalin code calls C libraries or vice versa, LLDB handles mixed-language stack traces, variable inspection, and stepping seamlessly.
- **Post-mortem debugging**: Core dumps from Lalin programs are fully debuggable because DWARF info is in the binary.

**What it sacrifices or leaves hard**:
- **Semantic stepping requires the DAP adapter to be smart**: LLDB doesn't know about blocks, regions, or backedges. The DAP adapter must constantly translate Lalin concepts to PC ranges and back. This translation layer is complex and error-prone.
- **No state machine visualization**: LLDB has no concept of "current block in region." The DAP adapter would need to maintain a separate model of the Lalin state machine and query LLDB for the current PC to map it.
- **Expensive to implement DWARF**: Cranelift's debug info infrastructure is incomplete and poorly documented. Getting full DWARF output working would require deep Cranelift engineering — potentially weeks of work.
- **Variable naming is fragile**: Lalin values are SSA and get optimized/rematerialized. Getting LLDB to show `i` and `acc` for a block's params at every point in the block requires Cranelift's `ValueLabel` to survive optimization, which it's not guaranteed to do at `opt_level = "speed"`.

**Rough implementation cost**:

| Phase | Files | Cost |
|-------|-------|------|
| 1. Source-location wire format | `back_command_binary.lua` — add `CmdSourceLoc` codec, `BACK_WIRE_FORMAT.md` update | ~50 lines Lua, ~20 lines spec |
| 2. Rust source-location decoder | `src/decode.rs` — parse `CmdSourceLoc`, call `set_source_location()` | ~40 lines Rust |
| 3. ValueLabel pass-through | `src/decode.rs` — `declare_var()` per value, `BACK_WIRE_FORMAT.md` update for value names | ~30 lines Rust |
| 4. DWARF emission | `src/lib.rs` — enable Cranelift's `DebugInfo` collector, emit `.debug_*` sections in object output | ~200 lines Rust (Cranelift API exploration) |
| 5. LLDB DAP adapter | New `lua/lalin/dap_lldb_adapter.lua` — manages LLDB process, translates MI protocol ↔ DAP | ~500 lines |
| 6. Semantic overlay | New `lua/lalin/dap_semantic.lua` — maps block labels to PC ranges, translates "step over block" to temp breakpoints | ~300 lines |
| 7. PVM recompile on breakpoint toggle | `lua/lalin/debug_recompile.lua` — cached re-lowering with CmdSourceLoc addition | ~100 lines |

**Total**: ~1000 lines Lua + ~300 lines Rust + ~30 lines wire format spec. Significant Cranelift expertise required for DWARF output.

---

### Approach C: The Full-Fidelity Trace Debugger

**Core philosophy**: Run the program once with full instrumentation, record every block entry with its parameter values, then debug the trace — breakpoints, stepping, and reverse-step are all queries against an immutable execution record.

**Architecture overview**:
- **Intelligence**: Lives entirely in Lua. The trace is recorded during execution (via instrumented `BackCmd[]` with recording traps), then the debugger provides interactive exploration of the trace.
- **Data flow**: Two-phase:
  1. **Record phase**: `BackCmd[]` → instrument every block entry and jump with `CmdTrap` that writes block ID + param values to a ring buffer in shared memory → Rust JIT executes → ring buffer accumulates trace → on completion or user signal, dump buffer to a trace file.
  2. **Query phase**: Load trace file into Lua → trace is an array of `{block_id: BackBlockId, params: {name: value, ...}, timestamp: u64}` entries → debugger provides interactive navigation, filtering, and visualization of the trace.
- **Key insight**: Because every block transition is a graph edge with explicit parameters, the trace is a *complete description of the program's execution as a path through a known state machine*. Reverse-step is trivially free (just move backward in the trace array). Conditional breakpoints become filters on the trace data.

**Stepping model** — Trace navigation:
- **Step forward/backward one transition**: Move ±1 in the trace array.
- **Step to next/previous occurrence of block X**: Scan forward/backward for the next block whose ID matches.
- **Step to next/previous backedge**: Scan for entries where `ControlFactBackedge` matches the transition.
- **Step to next/previous occurrence of condition C**: Scan for entries where a Lua predicate matches the params. Example: "next time `i > 100`".
- **Reverse and replay**: Move to any point in the trace and "replay" from there — because the trace is immutable, the debugger can show what happened before/after any point without re-executing.
- **Timeline view**: Show the trace as a sequence of block entries, with changes in parameter values highlighted.

**Breakpoint model** — Post-hoc trace filters:
- Breakpoints are set *after* execution, not during. The user runs the program and gets a trace. Then they query the trace.
- **"Break" on entry to block X**: Filter the trace to show only entries where block = X.
- **Conditional break**: `show_entries {|e| e.block_id:match("fib") and e.params.i > 100}`.
- **First-occurrence break**: `find_first {|e| e.block_id:match("hit")}` finds the first time the `hit` continuation was reached.
- **Hot path analysis**: Count entries per block, per transition pair — visualize the most frequent paths.
- **Watch variable**: `trace_values("acc")` shows all values of `acc` across the trace, highlighting changes.

**Provenance model** — Block-level (same as Approach A):
- Same block-level provenance enhancement needed: `tree_control_to_back.lua` records block boundaries.
- The trace entries reference `BackBlockId` strings, which Lua resolves to `BlockLabel` → source range via the anchor index.
- No PC → source mapping needed because the trace operates at the block level, not the instruction level.
- Because trace is post-hoc, the provenance map doesn't need to be available during execution — it's resolved lazily during trace navigation.

**LSP integration**:
- The LSP and debugger are separate tools that share the same "Lalin analysis" object.
- The debugger adds a web UI or TUI (not DAP) because the debugging paradigm is fundamentally different from step-execution — it's trace exploration. A DAP client assumes step/continue/pause, not timeline/query/filter.
- The LSP provides the anchor index and ControlFactSet to the debugger for labeling trace entries: `trace_entry.block_id → BackBlockId → (nonce, region, label) → BlockLabel → source_range`.
- The LSP's symbol navigation (`SymEvent` for continuation labels) is used to render trace entries as source-code-level annotations.

**What it enables that other approaches can't**:
- **Perfect reverse-step**: Moving backward in the trace is O(1) — just decrement the trace index. The parameter values at the earlier point are the actual values that were computed, not approximations or replayed state.
- **Exhaustive debugging**: The trace is the complete execution history. You can answer "did we ever enter block X with i = 42?" with a single filter. No heuristic, no partial replay.
- **Timeline visualization**: Render the execution as a Gantt-like chart of block occupancy over time. Show parameter values as signals. This is the "state machine oscilloscope" that no conventional debugger offers.
- **Deterministic reproduction**: The trace file is self-contained — send it to a colleague and they can explore the exact same execution. No need for the same binary, same inputs, or same machine.
- **Paradigm shift in debugging**: Instead of "set breakpoint, run, hit breakpoint, inspect, continue," the workflow becomes "run, then explore the complete execution." This matches how Lalin's explicit control flow makes execution fundamentally more predictable.

**What it sacrifices or leaves hard**:
- **No interactive control**: You can't pause execution mid-way and modify variables, then continue. The trace records what happened — you can't change it. (This is fundamental: you're debugging a recording, not a live process.)
- **Trace size**: Every block transition records block ID + parameter values. For a 1M-iteration loop with two i32 params, that's ~1M × (32 bytes block ID + 8 bytes params) ≈ 40MB. For complex programs, traces could be gigabytes. The ring buffer approach mitigates this (last N transitions), but then you lose full history.
- **No input modification**: You can't "change the input and rerun from here" — you'd need re-execution with new inputs, which is a separate run.
- **No memory/register inspection at arbitrary points**: The trace only records block entry parameters. If you need to know the value of a local `let` binding mid-block, you don't have it. (Mitigation: extend trace to record at finer granularity, but that increases trace size.)
- **Record-phase overhead**: Every block transition triggers a trap to record the trace entry. This is slower than Approach A's stepping (which only traps on breakpoints), because *every* transition is recorded. Programs run 10-100x slower under full trace recording.

**Rough implementation cost**:

| Phase | Files | Cost |
|-------|-------|------|
| 1. Block-level provenance | `tree_control_to_back.lua` — same record() per block as Approach A | ~5 lines |
| 2. Trace ring buffer | New C/Rust module `src/trace_buffer.rs` — lock-free shared memory ring buffer for trace entries | ~150 lines Rust |
| 3. Instrumentation for trace | New `lua/lalin/debug_trace_instrument.lua` — insert `CmdTrap` at EVERY block entry, plus param-recording commands | ~120 lines Lua |
| 4. Trap handler for recording | `src/lib.rs` — on trap, write block ID + param values to ring buffer, resume | ~50 lines Rust |
| 5. Trace file format | New `TRACE_FORMAT.md`, codec `lua/lalin/trace_codec.lua` | ~100 lines |
| 6. Trace debugger | New `lua/lalin/debug_trace_explorer.lua` — trace loading, filtering, query engine, stepping navigation | ~400 lines |
| 7. Web/TUI debugger UI | New `lua/lalin/debug_trace_ui.lua` — terminal UI or web interface (depends on choice) | ~300+ lines |
| 8. LSP integration for trace labeling | Extend `editor_subject_at.lua` — block_id → source range resolver for trace entries | ~30 lines |

**Total**: ~1000 lines Lua + ~200 lines Rust. Dominant cost is the trace UI and query engine, not the recording infrastructure.

---

### Comparison

| Dimension | Approach A: Semantic Block-Trace | Approach B: Self-Hosted Native | Approach C: Full-Fidelity Trace |
|-----------|--------------------------------|-------------------------------|--------------------------------|
| **Where intelligence lives** | Lua (debugger logic) + Rust (minimal trap handler) | Rust (DWARF + LLDB) + Lua (DAP adapter overlay) | Lua (trace engine) + Rust (ring buffer) |
| **What it steps on** | Block transitions | Native instructions | Trace entries (post-hoc) |
| **Breakpoints** | Pre-compile CmdTrap insertion, Lua condition eval | LLDB source-line breakpoints + DWARF | Post-hoc trace filters |
| **Reverse-step** | Hard (would need re-execution) | Hard (would need reverse execution) | Natural (trace index navigation) |
| **Performance under stepping** | Slow (Lua round-trip per block) | Fast (LLDB native stepping) | Slow during recording, instant during query |
| **State machine visualization** | Natural (debugger knows CFG) | Hard (LLDB doesn't know blocks) | Natural (trace + CFG) |
| **Variable inspection** | Block params only | Full DWARF variable info | Block params + selective local recording |
| **Post-mortem debugging** | No | Yes (core dumps with DWARF) | Yes (trace files) |
| **Editor integration** | DAP (custom) | DAP (via LLDB adapter) | Web/TUI (not DAP) |
| **Rust changes needed** | ~30 lines (trap handler) | ~300 lines (DWARF, ValueLabel) | ~200 lines (ring buffer) |
| **Lua changes needed** | ~900 lines | ~1000 lines | ~1000 lines |
| **Runs during execution** | Yes | Yes | Yes (recording) + No (query) |
| **Can modify variables mid-run** | No | Yes (via LLDB) | No |

**When to pick each:**

- **Pick Approach A** when you want a functioning debugger this month. It's the smallest, most self-contained change. The block-transition stepping model is the most natural fit for Lalin's paradigm. The main risk is performance for tight loops.

- **Pick Approach B** when you need production-quality native debugging with core dumps, mixed-language debugging, and don't want to reinvent basic stepping. It's the most conventional choice but requires deep Cranelift investment. The main risk is DWARF complexity and the semantic overlay fragility.

- **Pick Approach C** when you want the fundamentally different debugging paradigm that Lalin enables — trace-based, queryable, reversible. It's the most innovative and most aligned with Lalin's philosophy of explicit control flow. The main risk is trace size and the lack of interactive control during execution.

## Critique Output — 2026-05-21 19:50:06

Now I have a thorough understanding. Let me write the critique.

---

### Approach A: Semantic Block-Trace Debugger

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Tightly coupled to PVM cache behavior (recompilation strategy), the `BackCmd[]` command stream, `BackProvenance`, and the `BackBlockId` naming convention. But these are all *already* intra-module dependencies in the lowering pipeline. The debugger mostly adds new Lua modules that depend on existing interfaces rather than modifying them. The Rust coupling is minimal (one new FFI API for trap delivery). |
| **Cohesion** | 4/5 | Clean role separation: instrumentation module inserts `CmdTrap` at block entries, debugger core handles stepping logic + condition eval, DAP server handles protocol. The debugger logic is self-contained and doesn't bleed into existing compilation files. The one concern: the instrumentation pass requires modifying `BackCmd[]` *after* lowering but *before* encoding — this creates a third pipeline stage (lower → instrument → encode) that the current two-stage pipeline doesn't have. |
| **Migration cost** | 2/5 | **This is the biggest problem with Approach A that the proposal glosses over.** The "~30 lines Rust" trap handler claim is a wild underestimate. Cranelift 0.131 `JITModule` has **zero** trap handling infrastructure. There is no `set_trap_handler()`, no trap callback API, no way to resume after a trap. `TrapCode::unwrap_user(1)` generates a `ud2` (x86) which is a **non-resumable** instruction — control flow can't continue past it. To implement resumable breakpoints you'd need to: (a) set up platform-specific signal handlers (SIGILL handler), (b) parse `ucontext_t` to read register state, (c) modify the instruction pointer in the signal context to skip past the `ud2`, (d) communicate trap events to Lua via FFI (callback from signal handler context — problematic because signal handlers run on a restricted stack). This is more like **200-400 lines of Rust** plus profound platform-specific signal handling, not 30. The "minimum viable debugger" is much harder than described. |
| **Philosophy fit** | 5/5 | Excellent. The block-transition stepping model is the natural unit for Lalin's explicit control flow. Semantic breakpoints on block labels, not source lines. The `ControlFactBackedge` for loop-aware stepping. This embraces the paradigm rather than fighting it. |
| **Risk** | 5/5 | **Three significant risks**: (1) Signal-handler-based trap delivery on JIT code is fragile and platform-specific — works differently on Linux (SIGILL), macOS (SIGILL/SIGTRAP), ARM (SIGILL with different encoding). (2) Performance under stepping is genuinely bad — every block transition traps, which means stepping through a loop is one trap per iteration, each requiring a signal handler invocation and Lua FFI callback. (3) The recompilation-on-breakpoint model means every breakpoint toggle forces a full re-lower + JIT compile. PVM caches help for static recompilation, but rapid toggling (hit breakpoint, disable, continue, re-enable) incurs the full cost each time. |
| **Testability** | 3/5 | Block-level stepping is testable via existing debug benchmarks (e.g., `debug_fib_phi.lua` already inspects BackCmd[] manually). The trap handler requires platform-specific signal testing which is hard to automate. The DAP protocol can be tested against the existing LSP test infrastructure (JSON-RPC loop). |
| **Completeness** | 6/10 | **Leaves out**: (1) PC-level/instruction-level debugging — can't step through individual arithmetic within a block, (2) variable modification at runtime — trap handler captures registers but there's no mechanism to modify values before resume, (3) post-mortem debugging — no trace files, no core dumps, (4) memory inspection — can't examine arbitrary heap locations, (5) concurrent execution — single-threaded trap handling only. **Includes**: block-transition stepping, semantic breakpoints (block labels + conditions), predecessor queries, state machine visualization, loop-aware stepping. |

**Verdict**: Significant concerns

**Key concern**: The trap handler complexity is *fundamentally* harder than the proposal claims. Non-resumable traps (`TrapCode::unwrap_user`) require platform-specific signal handling, register state manipulation, and unsafe FFI callbacks from signal context. This isn't 30 lines — it's a substantial, risky, platform-dependent subsystem that will break on edge cases. If Approach A is chosen, the first implementation should **avoid traps entirely** and use a *simulated* execution path (interpret the `BackCmd[]` stream in Lua, pausing at block boundaries) for stepping, with traps only as an optimization for the "continue" path. This changes the architecture significantly.

---

### Approach B: Self-Hosted Native Debugger

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 1/5 | **Very high coupling**. Requires modifying: the wire format (adding `CmdSourceLoc` or equivalent metadata stream), the Rust decoder (`decode.rs`) to pass source locations to Cranelift IR instructions, Cranelift's `ValueLabel` allocation in the decoder, the object emission path to generate DWARF sections, and the `opt_level` setting (currently `"speed"`, needs to change to `"speed_and_size"` or `"debug"` which changes optimization behavior — a global compiler setting). This touches every layer in the Rust side. |
| **Cohesion** | 3/5 | The DAP adapter and semantic overlay are cleanly separated from the DWARF infrastructure. However, the DWARF infrastructure itself is tangled: source locations, value labels, and DWARF sections are interdependent in Cranelift's debug info API. Changing `opt_level` globally to support debug info is a cross-cutting concern that affects codegen quality for *all* programs, not just debug builds. |
| **Migration cost** | 4/5 | **High**. Getting Cranelift's debug info infrastructure working is non-trivial. Cranelift 0.131's `DebugInfo` collector is experimental and poorly documented. The wire format would need a new `CmdSourceLoc` tag, which means the encoder, decoder, and wire format spec all need simultaneous changes. The `opt_level` change is a global flag that affects optimization behavior — programs would run slower even without debugging unless you build a dual-mode JIT. The DAP adapter has the same complexity as Approach A but needs to additionally fight LLDB's assumptions about stepping granularity. |
| **Philosophy fit** | 2/5 | **Poor fit.** This approach fights Lalin's paradigm at every turn. Lalin's block-transition semantics don't map to PC-based stepping — the DAP semantic overlay would be constantly translating between LLDB's "you're at instruction X" and Lalin's "you're in block Y, about to jump to block Z." LLDB doesn't understand backedges, region exits, or continuation protocols. The semantic overlay would be complex, fragile, and constantly race-conditioned with LLDB's own stepping logic. This is like using a car engine to power a boat — it works but requires lots of adaptation plumbing. |
| **Risk** | 5/5 | **Very high.** (1) Cranelift's DWARF support may be incomplete or buggy at 0.131 — getting DWARF line tables, variable scopes, and type information all working is a multi-week effort even for experienced Cranelift developers. (2) Changing `opt_level` affects codegen quality for the entire project, not just debugged functions. (3) LLDB's DAP protocol implementation has known gaps (conditional breakpoints, expression evaluation limitations). (4) The semantic overlay requires real-time mapping between PC ranges and Lalin constructs, which changes as code is compiled — maintaining this mapping across recompilations is a correctness nightmare. (5) No existing Lalin developer has Cranelift debug info expertise. |
| **Testability** | 2/5 | Testing DWARF output requires round-tripping through LLDB/GDB, which is fragile and slow. The semantic overlay can be tested in isolation with mock LLDB responses, but end-to-end testing requires a running LLDB instance. Signal-handling and trap tests are platform-specific. |
| **Completeness** | 9/10 | **Best completeness of all three.** Native stepping, full variable inspection (not just block params), memory inspection, register inspection, core dumps, post-mortem debugging, multi-language stack traces, profiling — everything LLDB/GDB offers. The only Lalin-specific feature it can't provide natively is state machine visualization (you'd need the overlay for that). |

**Verdict**: No

**Key concern**: The architecture fundamentally forces a round peg (block-transition semantics) into a square hole (PC-based DWARF debugging). The semantic overlay needed to translate between the two is so complex that it essentially re-implements the core of Approach A's debugger *on top of* LLDB, giving you the worst of both worlds: the complexity of DWARF + the complexity of the semantic translation layer. Unless the project *specifically needs* core-dump debugging or mixed-language stack traces, this approach is architecturally misaligned.

---

### Approach C: Full-Fidelity Trace Debugger

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Moderate coupling but well-contained. Needs: block-level provenance enhancement in `tree_control_to_back.lua` (same as Approach A), a Rust ring buffer module, and the Rust trap handler. The trap handler problem is the same as Approach A (signal handling), but the requirements are slightly different — for trace recording, the trap handler doesn't need to resume; it just writes to the ring buffer and continues. This is actually *simpler* than Approach A's resumable trap handler. The full trace engine lives in Lua with no Rust dependencies beyond the ring buffer. |
| **Cohesion** | 5/5 | **Best of all three.** Record and query are hermetically separated phases. The record phase has one concern (capture block transitions into a buffer). The query phase has one concern (filter and navigate the trace). The trace file format is a clean boundary between them. No cross-cutting concerns, no state shared between phases. This is the cleanest architecture. |
| **Migration cost** | 2/5 | Similar to Approach A on the infrastructure side (provenance + trap handling), but *harder* on the user interface side. The non-resumable trap handler for recording is simpler than Approach A's resumable handler, but the trace query engine, filtering language, and Web/TUI interface are substantial new code. The proposal estimates ~400 lines for the trace explorer, but a usable query language with timeline visualization is more like 800+ lines. The "step forward/backward one transition" UI is unfamiliar to most developers and would require careful UX design. |
| **Philosophy fit** | 5/5 | **Best of all three.** This is the approach that most fully embraces Lalin's explicit control flow paradigm. Block transitions *are* the execution trace. Each trace entry is a complete state snapshot of the state machine. The trace is a first-class artifact that can be shared, analyzed, and replayed. The query language (filter by block, by parameter value, by condition) is the natural way to reason about Lalin programs. This is the debugging paradigm that Lalin's architecture makes uniquely possible. |
| **Risk** | 3/5 | **Moderate.** (1) Trace size is the primary risk — a 1M-iteration loop with two 32-bit params writes ~1 million trace entries. At ~40 bytes/entry (block ID string + param values), that's 40MB. Realistic traces could be gigabytes. The ring buffer mitigates this (last N entries), but then you can't answer "what happened at the very beginning?" (2) The ring buffer itself is lock-free shared memory between Lua and Rust — a known complex pattern that's hard to get right. (3) The trace query UI is a new thing — no existing debugger works this way, so there's no prior art for the UX patterns. (4) The trace is silent on what happens *inside* blocks — if a bug is in a `let` computation between block entry and the jump, the trace won't capture it. |
| **Testability** | 4/5 | The trace file is a plain binary format — you can generate known traces in tests and verify queries. The ring buffer can be tested in isolation. The UI layer is the hardest to test, but the query engine underneath it is pure data transformation. |
| **Completeness** | 5/10 | **Most incomplete of all three.** **Leaves out**: (1) No interactive control during execution — can't pause, modify variables, and continue. (2) No PC-level or instruction-level debugging. (3) No memory or register inspection beyond block parameters. (4) No post-mortem debugging (unless you count trace files). (5) No multi-language debugging. (6) Variable inspection limited to block params only. **Includes**: (1) Perfect reverse-step (O(1) trace index navigation). (2) Exhaustive "did this ever happen?" queries. (3) Timeline visualization of block occupancy. (4) Deterministic, shareable trace files. (5) Semantic block-label filtering. (6) Loop-aware queries via `ControlFactBackedge` cross-reference. |

**Verdict**: Yes with caveats

**Key concern**: Trace size management is the make-or-break issue. The ring buffer approach makes trace size bounded but loses early execution history. A user debugging a crash at iteration 999,999 won't have the first million iterations of the trace. The mitigation (sparse recording: record every Nth transition, or compress the ring buffer with deduplication) adds complexity. Without a Good Enough solution to trace size, the trace debugger is either "exhaustive but gigabytes" or "bounded but missing history." This needs to be solved in the first implementation design, not deferred.

---

### Incrementality Analysis: Can You Start with A and Grow to B or C?

The user's assumption that "we can always do the others later" needs scrutiny.

**A → C**: **Low conflict, moderate shared cost.** Both need the same block-level provenance enhancement in `tree_control_to_back.lua` (~5 lines). Both need the same Rust trap handler infrastructure — but A needs resumable traps (harder) while C needs record-only traps (easier). If you start with C's record-only trap handler as the base, adding A's resumable handler on top is a natural extension (record → add resume capability). The DAP server from A and the trace UI from C don't conflict — they serve different use cases and could coexist. A's recompilation-on-breakpoint model would be the primary mode, with C's trace-viewer as a secondary "show me what happened" tool. **These are genuinely complementary and share most infrastructure.**

**A → B**: **High architectural conflict.** A's entire model is "debugging intelligence lives in Lua, block-level granularity, no Rust-side provenance." B's entire model is "debugging intelligence lives in DWARF + LLDB, instruction-level granularity, full Rust-side provenance." These are fundamentally different data flows:
- A: `BackCmd[]` → instrument with traps → JIT → trap handler → Lua resolves block ID → Lua controls stepping
- B: `BackCmd[]` → insert source locs + value labels → JIT with DWARF → LLDB controls stepping → DAP adapter translates

Building A first doesn't give you B for free — you'd have to replace the trap infrastructure, wire format, and decoder simultaneously. The block-level provenance from A is useful for B (it's a subset of what DWARF needs), but the core execution model is completely different. **These are different architectures, not incremental steps.**

**B → C**: **Manageable conflict, moderate shared cost.** B's DWARF infrastructure doesn't directly help C (C doesn't need DWARF), but B's `CmdSourceLoc` in the wire format would be useful for C if you wanted to add per-instruction annotations to the trace. Both need Rust-side changes. The DAP adapter from B and the trace UI from C could coexist similarly to A and C.

**Summary**: A→C is genuinely incremental. A→B is not — they're architectural alternatives, not phases of the same plan. The user should decide which paradigm fits Lalin's philosophy (A/C's block-transition model or B's PC/instruction model) before building anything, because the first 200 lines of Rust infrastructure commit you to one path.

---

### Summary

| Approach | Verdict | Top Strength | Top Weakness |
|----------|---------|-------------|-------------|
| **A: Semantic Block-Trace** | Significant concerns | Perfect philosophy fit; natural stepping model | Trap handler is 10x harder than claimed (non-resumable `ud2`, signal handling, context manipulation); performance under stepping is genuinely slow |
| **B: Self-Hosted Native** | No | Most complete feature set (core dumps, memory, multi-language) | Architectural mismatch: DWARF is for PC-level debugging, not block transitions; semantic overlay fights LLDB constantly; `opt_level` change affects all codegen |
| **C: Full-Fidelity Trace** | Yes with caveats | Best philosophy fit + cleanest architecture (record/query separation) + natural reverse-step | No interactive control; trace size is unbounded; missing internal block detail |

**Recommended**: **Approach C**, despite its feature incompleteness. It has the cleanest architecture (record/query phase separation), the best philosophical alignment with Lalin's explicit control flow, and the most natural path to a fundamentally new debugging experience. **But** the trap handler problem must be solved with a different strategy — either using Cranelift's `jump` + explicit condition instead of `trap` (resumable by construction), or by implementing the record phase as a pure Lua interpreter over `BackCmd[]` (no traps at all, just simulation). The signal-handler approach is too fragile.

**Dark horse**: **Approach A**, if and only if the trap handler can be replaced with a simulation strategy. A pure-Lua `BackCmd[]` interpreter that steps through block boundaries would give you the block-transition debugging model without any Rust changes, and without the performance cliff of trap-per-block (simulation is slow anyway, but at least you don't have signal handler overhead). Once the simulation-based debugger works, traps can be added later as an optimization for hot loop stepping. This is the path to a *minimal* debugger that actually works this month, and it naturally converges to C's trace recording (the simulation interpreter can trivially record every block transition it visits).

**Avoid**: **Approach B**. It's the wrong abstraction for Lalin. The cost of DWARF + LLDB integration is high, the philosophical mismatch is deep, and the semantic overlay complexity means you essentially build the block-transition debugger anyway — just while fighting LLDB for control. Unless a stakeholder specifically demands native core-dump debugging or GDB/LLDB compatibility, this approach is architecturally unjustified.

## Documenter Output — 2026-05-21 19:55:50

Now I have a thorough picture of all the existing infrastructure. Let me produce the definitive architecture document.

---

# Lalin Debugger — Architectural Specification

**Status**: Definitive | **Date**: 2026-05-21 | **Workflow**: wf-lalin-debugger

---

## Goal

Enable interactive debugging of Lalin programs at the block-transition level of granularity, using a pure-Lua `BackCmd[]` interpreter for stepping and native Cranelift JIT for fast-path continuation. The debugger provides semantic breakpoints (block-label–based, not source-line–based), parameter-value inspection, block-navigation, and a DAP server that shares the LSP's STDIO loop and analysis context.

---

## Incentives

Lalin's explicit control flow — where every `block`/`jump`/`yield`/`return` is typed and named — creates a fundamentally different debugging paradigm from conventional PC-level debuggers. The existing infrastructure already captures:

- **Block labels and region IDs** as first-class ASDL values (`BlockLabel.name`, `region_id`, `BackBlockId("ctl:nonce:region:label")`) — the debugger can operate on named machine states rather than line numbers.
- **ControlFactSet** (from `tree_control_facts.lua`) documenting every edge (`ControlFactJump`, `ControlFactBackedge`, `ControlFactJumpArg`) — predecessor/successor queries are static, not heuristic.
- **AnchorContinuationName** anchors and `SubjectContinuation` editor subjects — the LSP already knows which block the cursor is on.
- **BackProvenance** infrastructure (`back_provenance.lua`) — a reverse indexing system exists but is currently used only at item-level granularity for diagnostics.

The gap is that this rich metadata is inert: there is no runtime debugging capability. The existing pipeline is batch-only (parse → typecheck → lower → encode → JIT → run), with no interactive pause, no step control, and no variable inspection. The batch pipeline cannot satisfy the debugging needs of state-machine-oriented Lalin programs where iteration correctness (loop-variant values entering block parameters) is the primary failure mode.

The critique of prior approaches identified that trap-based stepping (`TrapCode::unwrap_user(1)`) generates non-resumable `ud2` instructions requiring fragile platform-specific signal handlers (SIGILL on Linux, context-stack manipulation, unsafe FFI callbacks from signal context). This path was estimated at 200–400 lines of Rust with significant platform risk and was rejected. The architecture below replaces traps with a pure-Lua simulation strategy.

---

## Current State

### The Compilation Pipeline

The existing pipeline is:

```
Source text → Parse (anchors built with AnchorSpan per token)
  → Typecheck → LalinTree.Module (typed AST with ControlStmtRegion, ControlExprRegion)
    → Layout → LalinTree.Module (memory layouts resolved)
      → tree_to_back.lua: Lower → BackCmd[] (flat command stream)
        → back_validate.lua → back_command_binary.lua: Encode → binary wire format
          → back_jit.lua: FFI → Rust lalin_jit_compile_binary → Cranelift JIT
            → Executable native code
```

Every stage is synchronous and completes before the next starts. The Rust JIT (`lalin_jit_compile_binary`) is a single FFI call that compiles the entire wire format at once. There is no concept of "pause," "resume," or "step."

### BackCmd[] — The Flat Command Stream

The target of lowering is `LalinBack.BackProgram` containing `BackCmd[]` — a flat array of commands. Key control-flow commands (from `lua/lalin/schema/back.lua`):

| Command | Purpose | Key Fields |
|---------|---------|------------|
| `CmdCreateBlock(block)` | Declare a basic block | `BackBlockId` |
| `CmdSwitchToBlock(block)` | Set current block for subsequent cmds | `BackBlockId` |
| `CmdAppendBlockParam(block, value, ty)` | Add a parameter to a block | `BackBlockId`, `BackValId`, `BackShape` |
| `CmdJump(dest, args)` | Unconditional transfer | `BackBlockId`, `BackValId[]` |
| `CmdBrIf(cond, then, then_args, else, else_args)` | Conditional branch | `BackValId`, `BackBlockId` x2, args x2 |
| `CmdSwitchInt(value, ty, cases, default)` | Multi-way branch | `BackValId`, `BackScalar`, `BackSwitchCase[]`, `BackBlockId` |
| `CmdReturnVoid` / `CmdReturnValue(value)` | Function return | (optional `BackValId`) |
| `CmdTrap` | Trap (non-resumable) | none |
| `CmdSealBlock(block)` | Finalize a block (must be terminating) | `BackBlockId` |
| `CmdCall(dest, target, args, result)` | Function call | `BackValId`, `BackCallTarget`, `BackValId[]`, result spec |

Block IDs follow the naming convention `"ctl:{nonce}:{region_id}:{label_name}"` (e.g., `"ctl:1:fib_loop:loop"`). Value IDs follow `"ctl:{nonce}:{region_id}:{label_name}:{param_name}"` (e.g., `"ctl:1:fib_loop:loop:i"`). These human-readable names encode complete provenance information: the nonce identifies the lowering session, the region ID identifies the control region, and the label name identifies the block within the region.

### Provenance Recording (Current State)

`BackProvenanceMap` in `back_provenance.lua` provides:
- `record(cmd_start, cmd_end, source_range, doc_uri, name)` — records a mapping from command range to source location
- `resolve(cmd_index)` — returns `SourceSpan` for a command index
- `resolve_entry(cmd_index)` — returns the raw entry (for name-based resolution)
- `resolve_range(start_idx, end_idx)` — merges multiple entries into encompassing span

Currently, provenance is recorded only at **item granularity** in `tree_to_back.lua` (lines 2601–2610): each function/extern/const/static item has a single entry recording its command range and its name. There is no per-block, per-jump, or per-statement provenance.

### LSP Infrastructure

The LSP server (`lsp.lua`) runs through `rpc_stdio_loop.lua`, which:
1. Reads STDIN for `Content-Length`–framed JSON-RPC messages
2. Decodes to `ClientEvent` ASDL variants via `rpc_lsp_decode.lua`
3. Applies via `editor_workspace_apply.lua` state machine
4. Emits outgoing messages via `rpc_lsp_encode.lua`

The existing LSP provides (among others):
- `editor_subject_at.lua` — resolves a source position to a semantic `Subject` (including `SubjectContinuation` for block labels)
- `editor_symbol_facts.lua` — emits `SymbolFact` for continuation labels as `SymEvent` kind
- `editor_binding_facts.lua` — binding definition/use/resolution facts
- `editor_definition.lua`, `editor_references.lua` — goto-def and find-refs

These modules already answer the static queries a debugger needs ("what block is at this cursor?", "what blocks contain this binding?", "what jumps target this block?"), but no runtime debugging hooks exist.

### Block Lowering Detail

`tree_control_to_back.lua` lowers `ControlStmtRegion` and `ControlExprRegion` to flat `BackCmd[]`. For each region:

1. A unique `nonce` is generated (monotonically increasing counter)
2. Block records are created: `{label, block_id(BackBlockId), params, body, is_entry}`
3. `CmdCreateBlock` is emitted for each record, plus an `exit_block` for yield destinations
4. Entry jump is lowered: `CmdJump(entry_block, args)` where args are the entry parameter initializers
5. Body statements are lowered: each `StmtJump` becomes `CmdJump(target, args)`, `StmtYieldVoid`/`StmtYieldValue` become `CmdJump(exit_block)`, `StmtIf` becomes `CmdBrIf`, `StmtSwitch` becomes `CmdSwitchInt`
6. Each block is sealed with `CmdSealBlock`

The `labels` table maps `BlockLabel.name` → block record, enabling target resolution for jumps.

### Data Declarations and Memory

The `BackProgram` also contains data declarations (`CmdDeclareData`), initializers (`CmdDataInit`, `CmdDataInitZero`), extern function declarations (`CmdDeclareExtern`), and function signatures (`CmdCreateSig`). Stack slots are created with `CmdCreateStackSlot`. Memory operations include `CmdLoad`, `CmdStore`, `CmdMemcpy`, `CmdMemset`, `CmdMemcmp`, `CmdAtomicLoad`, `CmdAtomicStore`.

---

## Chosen Target: The Simulation-Based Block-Trace Debugger

### Approach

The architecture combines elements of the critique's recommended **Approach C** (Full-Fidelity Trace Debugger) with the critique's "dark horse" suggestion (simulation-based stepping instead of traps). The key decisions:

1. **No traps for stepping.** `CmdTrap` generates non-resumable `ud2` instructions. Stepping uses a pure-Lua `BackCmd[]` interpreter that walks the flat command stream, maintains a virtual register file, and pauses at block boundaries. Native JIT compilation is used only for "continue" (fast-path execution without stopping).

2. **Block-level stepping model.** The debugging granularity is the block transition, not the instruction. Primitives: step one block, complete current block, complete current region, continue until breakpoint.

3. **Two execution paths.** Interpreter for stepping (simulated execution with pause capability); native JIT for "continue" (with optional `CmdTrap` insertion at breakpoints for the trap-based fast path).

4. **Natural trace recording.** The interpreter visits every block transition and can trivially record them to build an execution trace (the Full-Fidelity Trace approach from Approach C, available as a future extension with zero architectural change).

5. **Zero Rust changes for the core debugger.** Everything lives in Lua. The only Rust change is enhanced block-level provenance in the lowering pipeline (~5 lines). No signal handlers, no trap infrastructure, no DWARF.

6. **DAP alongside LSP.** The Debug Adapter Protocol runs in the same STDIO loop as the existing LSP server, sharing the analysis context.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        User's Editor                            │
│                  (VS Code / Neovim / etc.)                      │
└──────────────────┬──────────────────────────────────────────────┘
                   │  DAP                                             │  LSP
                   ▼                                                  ▼
┌──────────────────────────────┐     ┌──────────────────────────────┐
│       DAP Server             │     │       LSP Server             │
│  (lua/lalin/dap_server)   │     │  (lsp.lua + existing modules)│
│                              │     │                              │
│  DAP protocol ↔ debugger     │     │  Static queries: hover,      │
│  commands: step, continue,   │     │  goto-def, symbols,          │
│  breakpoint, stack trace,    │     │  semantic tokens, etc.       │
│  variables                   │     │                              │
└───────────┬──────────────────┘     └──────────────┬───────────────┘
            │                                       │
            │   shares analysis context              │
            ▼                                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 Debugger Core                                │
│       (lua/lalin/debugger_core)                           │
│                                                              │
│  ┌──────────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Breakpoint Table  │  │ Stepping     │  │ Variable      │  │
│  │ (block label →    │  │ Machine      │  │ Inspector     │  │
│  │  condition fn)    │  │ (state:      │  │ (block params │  │
│  │                   │  │  stepping,   │  │  → binding    │  │
│  │                   │  │  running,    │  │  facts → val) │  │
│  │                   │  │  paused,     │  │               │  │
│  │                   │  │  terminated) │  │               │  │
│  └──────────────────┘  └──────────────┘  └───────────────┘  │
└──────────────────────┬───────────────────────────────────────┘
                       │
              ┌────────┴────────┐
              │                 │
              ▼                 ▼
┌─────────────────────┐  ┌───────────────────────────┐
│ BackCmd Interpreter  │  │ Native JIT (fast path)    │
│ (lua/interpreter)    │  │                           │
│                      │  │  BackCmd[] → encode →     │
│  Walks BackCmd[]     │  │  Rust JIT → run native    │
│  Virtual register    │  │  (with optional CmdTrap   │
│  file                │  │   for breakpoint resume)  │
│  Simulated heap      │  │                           │
│  Pauses at block     │  │                           │
│  boundaries          │  │                           │
└─────────────────────┘  └───────────────────────────┘
```

---

## Component Specifications

### 1. Provenance Enhancement (`tree_control_to_back.lua`)

**Responsibility**: Record block-level provenance during lowering so the debugger can map `BackBlockId` → source range.

**Current state**: `BackProvenance` is created in `tree_to_back.lua` within `with_module_context()`, but `record()` is called only at item granularity (per function, per extern, per const). Blocks within control regions carry no provenance.

**Change**: In `tree_control_to_back.lua`, after creating each `CmdCreateBlock`, call `provenance:record()` with the source range of the `block` or `entry` keyword. The anchor index already has `AnchorContinuationName` anchors with exact byte ranges.

**Location**: Inside `declare_blocks()` or immediately after each block's `CmdCreateBlock` in `lower_region()`:

```lua
-- In lower_region(), after declare_blocks(cmds, records, ...):
for i = 1, #records do
    local block_source_range = find_block_source_range(region, records[i].label)
    if block_source_range and provenance then
        -- The CmdCreateBlock is at position (start of block declaration commands)
        -- Record from CmdCreateBlock to the end of the block's seal
        provenance:record(
            block_cmd_start_idx,  -- known from cmds index tracking
            block_cmd_end_idx,    -- after CmdSealBlock
            block_source_range,   -- SourceRange from anchor
            doc_uri,
            records[i].label.name  -- block label name for fallback resolution
        )
    end
end
```

**Data flow**: `provenance` is threaded through the lowering context. It's created in `tree_to_back.lua`'s `with_module_context()` and must be passed into `tree_control_to_back.lua`'s `lower_region()`. Currently, `tree_control_to_back.lua` does not receive the provenance object; this is the key plumbing change.

**Edge cases**:
- Blocks without source anchors (synthetic blocks from if/switch lowering): record with `name` only for anchor-index–based resolution
- Entry block: the `entry` keyword is the anchor (`AnchorContinuationName`)
- Exit blocks (synthetic): record with name `"ctl:{nonce}:{region}:exit"` — resolved via anchor index if the yield keyword has an anchor

### 2. BackCmd Interpreter (`lua/lalin/debug_interpreter.lua`)

**Responsibility**: Walk the `BackCmd[]` flat command stream sequentially, maintain a virtual register file and simulated heap, and pause execution at block boundaries (before executing a `CmdSwitchToBlock` after a `CmdJump`/`CmdBrIf`/`CmdSwitchInt`).

**Key data structures**:

```lua
local InterpreterState = {
    cmds = {},                    -- BackCmd[] (flat command stream)
    cursor = 1,                   -- current index into cmds
    registers = {},               -- BackValId → concrete value (number/boolean/string)
    current_block = nil,          -- BackBlockId of the currently executing block
    block_params = {},            -- BackBlockId → {name → BackValId}
    stack = {},                   -- stack slots (CmdCreateStackSlot → bytes)
    heap = {},                    -- allocated data regions (CmdDeclareData → bytes)
    extrn = {},                   -- extern function name → FFI function reference
    return_value = nil,           -- value from CmdReturnValue
    terminated = false,           -- true when return/trap encountered
    paused = true,                -- paused at a block boundary
    block_boundary = false,       -- true when at a block entry
    trace = {},                   -- optional: recorded trace entries
    trace_enabled = false,        -- whether to record trace
    trace_max = 1000000,          -- max trace entries before ring-buffer wrap
}
```

**Execution model**:

The interpreter advances one command at a time via a `step()` function. Each command has a handler that:
1. Reads its operands from `registers` (by `BackValId`)
2. Computes the result (for arithmetic, memory, etc.)
3. Stores the result in `registers[result_id]`
4. Advances `cursor`

**Control flow handlers**:

| Command | Interpreter Action |
|---------|-------------------|
| `CmdCreateBlock(bid)` | Register block existence; no runtime effect |
| `CmdSwitchToBlock(bid)` | Set `current_block = bid`; if in stepping mode, set `paused = true` and return control to debugger |
| `CmdAppendBlockParam(bid, val, ty)` | Register `val` as a param of `bid`; set `registers[val]` from block's jump args (set during `CmdJump` resolution) |
| `CmdJump(dest, args)` | Evaluate each arg from registers, set `pending_bindings = {dest → args}`, advance cursor to the `CmdSwitchToBlock` for `dest` |
| `CmdBrIf(cond, then, then_args, else, else_args)` | Evaluate `cond`; select target block; set `pending_bindings`; advance to next block's `CmdSwitchToBlock` |
| `CmdSwitchInt(val, ty, cases, default)` | Evaluate `val`; match against cases; select target; set `pending_bindings` |
| `CmdReturnVoid` | Set `terminated = true`; return control to debugger |
| `CmdReturnValue(val)` | Set `return_value = registers[val]`; set `terminated = true` |
| `CmdTrap` | Set `terminated = true` with event `"trap"`; return control to debugger |

**Stepping protocol**:

The interpreter exposes:
- `interpreter:step_into_block()`: Execute from current cursor until the next block boundary (a `CmdSwitchToBlock` reached via jump/brif/switch). Pause before executing any commands inside the target block.
- `interpreter:complete_block()`: Execute all commands in the current block (from current `CmdSwitchToBlock` to the block's terminal `CmdJump`/`CmdReturn`/`CmdTrap`). Pause at the target block boundary.
- `interpreter:complete_region()`: Execute until a `CmdReturnVoid`/`CmdReturnValue`/`CmdTrap` is encountered, or until a jump exits the current region (yield to parent context). Pause at the exit.
- `interpreter:continue()`: Execute until a registered breakpoint condition is met, or until termination.

**Virtual register file**:

Registers are stored as `registers[BackValId.text] → raw_value`. Raw values are Lua numbers, booleans, or nil (for null pointers). Pointers are represented as numeric addresses into the simulated heap or stack. The register file is populated:

1. Block parameters: set when entering a block via `CmdJump`/`CmdBrIf` args, mapped to `BackValId` names via `CmdAppendBlockParam`
2. Constant commands: `CmdConst` stores the literal value
3. Computation commands: `CmdIntBinary` stores the result of the operation

**Memory simulation**:

- `CmdCreateStackSlot(size, align)`: allocate a chunk in `stack[slot_id]`
- `CmdLoad(dst, addr)`: read from `heap[addr]` or `stack[addr]` into `registers[dst]`
- `CmdStore(addr, value)`: write `registers[value]` into `heap[addr]` or `stack[addr]`
- `CmdMemcpy(dst, src, len)`: copy bytes in heap
- `CmdMemset(dst, byte, len)`: set bytes in heap
- `CmdDeclareData(id, size, align)`: allocate `data` region
- `CmdDataInit(data_id, offset, value)`: initialize data region

Memory is byte arrays (`string` or `table` of bytes for simplicity). Load/store operations handle scalar widths (i8, i32, i64, f32, f64) by extracting raw bytes and converting to/from Lua numbers using `ffi.cast` or manual bit manipulation.

**Extern function calls**:

`CmdCall` with `BackCallExtern` target: the interpreter looks up the extern function by name in the `extrn` table (populated from `CmdDeclareExtern` declarations or from the compiler's extern registry). It calls the FFI function with the operand values, captures the return value, and stores it in the result register. The extern registry is populated by the host pipeline (`lalin.host` → extern function table) — the interpreter receives this as a constructor parameter.

`CmdCall` with `BackCallDirect`: calls another Lalin function within the same module. The interpreter maintains a `functions` table mapping `BackFuncId` → `BackCmd[]` (the function's body). On call: push the current cursor and register file onto a call stack, set cursor to the callee's body start, and resume interpretation. On return: pop the call stack, restore cursor, capture return value.

**Edge cases**:
- **Block with no source-location provenance**: the interpreter still functions — it just can't provide source location for the current block. The block label (from `BackBlockId`) is always available.
- **CmdCall to indirect function pointer**: requires resolving the function address from registers, looking up the target function by address in a side table built during lowering.
- **Concurrent register assignment**: The same `BackValId` may be assigned multiple times in different execution paths (e.g., both branches of a `CmdBrIf` assign to the same name). The interpreter overwrites the register — this matches SSA semantics where each name is defined exactly once (the encoder renumbers values, but the textual ID stays constant within a function body).
- **Uninitialized registers**: If a jump target receives arguments with names that weren't set by the caller (shouldn't happen in valid Lalin), the interpreter provides a typed default (0 for integers, false for booleans, 0.0 for floats).
- **Stack slot lifetime**: Stack slots are created at module level (in `CmdCreateStackSlot` before any function body). Their allocation is static — the interpreter pre-allocates all at initialization time.

### 3. Debugger Core (`lua/lalin/debugger_core.lua`)

**Responsibility**: Manage the debugger's state machine — stepping modes, breakpoint table, condition evaluation, and coordination between the interpreter and the DAP server.

**State machine**:

```
                   ┌─────────────┐
                   │   IDLE      │ ← program loaded, not yet running
                   └──────┬──────┘
                          │ debugger:run()
                          ▼
                   ┌─────────────┐
          ┌───────→│  PAUSED     │ ← at block boundary, waiting for user
          │        └──────┬──────┘
          │               │ user command: step / continue / next block
          │               ▼
          │        ┌─────────────┐
          │        │ STEPPING    │ ← interpreter is executing
          │        └──────┬──────┘
          │               │ block boundary reached OR breakpoint hit
          │               ▼
          │        ┌─────────────┐
          └────────│  PAUSED     │
                   └──────┬──────┘
                          │ terminate command
                          ▼
                   ┌─────────────┐
                   │ TERMINATED  │ ← program exited or trapped
                   └─────────────┘
```

**Key data structures**:

```lua
local DebuggerState = {
    interpreter = nil,            -- InterpreterState instance
    breakpoints = {},             -- {[block_label_key] = {enabled, condition_fn, hit_count}}
    stepping_mode = "none",       -- "step_block" | "complete_block" | "complete_region" | "continue" | "none"
    paused = true,
    terminated = false,
    current_region_id = nil,      -- string (from BackBlockId parsing)
    current_block_label = nil,    -- string (from BackBlockId parsing)
    block_provenance = {},        -- BackBlockId → SourceSpan (from enhanced provenance)
    source_lines_to_blocks = {},  -- line_number → {block_label, region_id}[]
    call_stack = {},              -- {region_id, block_label, params}[]
    variable_cache = {},          -- {name → {value, type}}
}
```

**Breakpoint table**:

Breakpoints are keyed by `BlockLabel.name` (e.g., `"loop"`, `"start"`, `"done"`). Each entry stores:
- `region_id`: optional filter (break on block `"loop"` only in region `"fib"`)
- `condition_fn`: optional Lua function `(params_table) → boolean` — evaluated at each block entry
- `hit_count`: number of times this breakpoint was triggered (for "break after N hits")
- `temporary`: boolean (single-fire breakpoints for stepping)

Breakpoints are set via DAP `setBreakpoints` request, which maps source lines → anchors → `AnchorContinuationName` → block label.

**Condition evaluation**:

When the interpreter pauses at a block boundary (before any commands in the block execute), the debugger core:
1. Resolves the `BackBlockId` to region_id and label_name (textual parse: `"ctl:{nonce}:{region}:{label}"`)
2. Queries the breakpoint table for matching entries (by label_name, optionally filtered by region_id)
3. For each matching entry, evaluates `condition_fn` with the block's parameter values (read from interpreter registers using the block's `param_name → BackValId` mapping)
4. If any condition returns true, emits `"breakpoint hit"` event to DAP server
5. If no condition matches (or no breakpoints), continues execution

**Stepping modes**:

Each mode is implemented as a small interpreter driver:

```lua
-- Step one block: execute from current boundary to next boundary
function debugger:step_block()
    self.stepping_mode = "step_block"
    local next_block = self.interpreter:step_into_block()
    self:pause_with_event("step_complete", {block = next_block})
end

-- Complete block: execute all commands in current block, stop at target
function debugger:complete_block()
    self.stepping_mode = "complete_block"
    local target = self.interpreter:complete_block()
    self:pause_with_event("step_complete", {block = target})
end

-- Continue: run until breakpoint or termination
function debugger:continue()
    self.stepping_mode = "continue"
    local event = self.interpreter:continue_until(self:active_breakpoints())
    self:pause_with_event(event.type, event.data)
end
```

**Call stack representation**:

The call stack is not a conventional call stack — it's a "breadcrumb trail" of region/block transitions. Each entry records:
- `region_id`: the control region the block belongs to
- `block_label`: the block label name
- `params`: parameter values at entry (name → value pairs)
- `transition_from`: which block/region we came from

On `CmdCall` (function call), the caller's current block/region is pushed onto the call stack. On return, it's popped. On `yield` (region exit), the current region's exit is recorded.

### 4. DAP Server (`lua/lalin/dap_server.lua`)

**Responsibility**: Implement the Debug Adapter Protocol in the same STDIO loop as the LSP server, translating DAP requests to debugger core commands and debugger events to DAP notifications.

**Architecture**: The DAP server is a second handler registered alongside the LSP event loop in `rpc_stdio_loop.lua`. Both LSP and DAP messages arrive on the same STDIN. Messages are dispatched by method prefix:

- Methods starting with `"dap/"` or matching DAP method names (`"initialize"`, `"setBreakpoints"`, `"stackTrace"`, `"next"`, `"stepIn"`, `"continue"`, etc.) → DAP handler
- All other methods → LSP handler

**DAP request mapping**:

| DAP Request | Debugger Action |
|-------------|-----------------|
| `initialize` | Return DAP capabilities (supports: breakpoints, step, continue, stackTrace, variables, exceptionInfo) |
| `launch` / `attach` | Compile the target `.mlua` file, instantiate the interpreter, set initial state to PAUSED at module entry point |
| `setBreakpoints` | Translate source lines → anchors → `AnchorContinuationName` → `BlockLabel` → create breakpoint entries |
| `setFunctionBreakpoints` | Set breakpoints on function names (can use existing `AnchorFunctionName` anchors) |
| `continue` | Unpause interpreter in `"continue"` mode |
| `next` | "Step over": execute current block, stop at next block boundary in same region |
| `stepIn` | "Step into": same as `next` (no nested function calls in blocks) |
| `stepOut` | "Step out of region": continue to region exit (yield) |
| `pause` | Pause the interpreter at the next block boundary |
| `stackTrace` | Return the block breadcrumb trail (call stack) |
| `scopes` / `variables` | Return block parameters as named variables with types from binding facts |
| `disconnect` / `terminate` | Clean up interpreter state |

**DAP event mapping**:

| Debugger Event | DAP Notification |
|----------------|-----------------|
| `"step_complete"` | `stopped{reason="step"}` |
| `"breakpoint_hit"` | `stopped{reason="breakpoint"}` |
| `"exception"` (CmdTrap) | `stopped{reason="exception", description="trap in user code"}` |
| `"terminated"` | `terminated{}` + `exited{}` |

**Shared analysis context**:

The DAP server and LSP server share the same `analysis_ctx` (containing anchors, binding facts, control facts, provenance). The DAP server uses LSP modules directly for breakpoint resolution:
- `editor_subject_at.lua` → resolves cursor position to `SubjectContinuation`
- `editor_symbol_facts.lua` → resolves block label names to source ranges
- `editor_binding_facts.lua` → resolves block param names to types

**Integration with `rpc_stdio_loop.lua`**:

The loop's `run()` function is extended with an optional `dap_handler` parameter. When a message arrives, it checks:

```lua
if is_dap_method(method) then
    local result = dap_handler.handle(incoming)
    write_message(output, result)
else
    -- existing LSP dispatch
    local event = Decode.decode(incoming, state)
    local transition = WorkspaceApply.apply_event(state, event)
    -- ...
end
```

### 5. LSP Integration (`lua/lalin/dap_breakpoint_resolver.lua`)

**Responsibility**: Bridge the DAP's source-line–based breakpoint model to Lalin's block-label–based breakpoint model. Map `{uri, line}` → `{region_id, block_label}`.

**Algorithm**:

```
1. Given a source URI and line number L:
2. Build position index for the document (source_position_index.lua)
3. Convert line → byte offset range (one line span)
4. Query anchor index (source_anchor_index.lua) for anchors at that range
5. Filter for AnchorContinuationName anchors (block/entry keywords)
6. For each matching anchor, extract:
   - block_label = anchor.label (e.g., "loop", "start")
   - region_id = determined from enclosing region anchor (AnchorRegionName)
   - source_range = anchor.range
7. Return {region_id, block_label, source_range}[]
```

If a source line contains no `AnchorContinuationName`, return no breakpoints (or widen the search to nearby block definitions). The DAP's `setBreakpoints` may set multiple breakpoints per line if the line contains multiple block/entry keywords.

**Reverse mapping** (debugger → editor highlight):

When the debugger pauses at a block boundary, it emits `{region_id, block_label}`. The LSP provides:
- `editor_symbol_facts.lua` → finds the `SubjectContinuation` for that block label
- `SubjectContinuation.scope` and `SubjectContinuation.label` → source range via anchor index
- The editor highlights that range as the current execution point

### 6. Native Fast Path (`lua/lalin/debug_native_exec.lua` — Future)

**Responsibility**: When the user presses "continue" (no breakpoints active, or breakpoints are all inactive), compile the program natively via Cranelift and run at full speed. When breakpoints are active and the user presses "continue", either:
- (a) Insert `CmdTrap` commands at target block entries and compile natively (trap handler reports which block fired)
- (b) Use the interpreter but skip block-boundary pauses (fast path within interpreter)

**Decision**: Option (b) is preferred initially — the interpreter already handles all execution. The "continue" optimization is to disable block-boundary pausing (set `paused = false`) and run the interpreter at full speed until a breakpoint condition is met or termination. This is always correct and avoids the trap-handler complexity entirely.

Option (a) is a future optimization for when the interpreter's overhead (even without pausing) becomes prohibitive. It requires:
1. The block-level provenance to identify which `BackCmd` indices correspond to each block's entry
2. Insertion of `CmdTrap` before the first command of each breakpoint-target block
3. Re-encoding and re-JITting the modified command stream
4. A trap handler that reports `BackBlockId` back to Lua (via FFI callback or polling)

The signal-handler complexity from Approach A applies here. This is deferred until the interpreter's performance is measured and found insufficient.

---

## User-Facing Debugger Experience

### Setting a Breakpoint

The user opens a `.mlua` file and clicks in the gutter at line 15, to the left of:

```lalin
    block loop(i: index = 0, acc: i32 = 0)
```

The editor sends DAP `setBreakpoints` with `{source: {path: "fib.mlua"}, lines: [15]}`.

The DAP server:
1. Loads the source document
2. Builds the position index for the document
3. Converts line 15 → byte offset range (byte position of the `block` keyword)
4. Queries the anchor index for `AnchorContinuationName` anchors intersecting that range
5. Finds anchor: `{kind: AnchorContinuationName, label: "loop", range: {start_offset: 342, stop_offset: 346}}`
6. Resolves the enclosing region via `AnchorRegionName` anchors → region `"fib"`
7. Creates breakpoint entry: `{region_id: "fib", block_label: "loop", enabled: true, condition_fn: nil}`
8. Returns DAP `breakpoints: [{id: 1, verified: true, line: 15}]`

The editor shows a red dot at line 15.

### Stepping

**Step Over** (`next` in DAP terminology):

The user is paused at the entry of block `loop` in region `fib`. Block `loop` has parameters `i: index` and `acc: i32`. The body is:
```lalin
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
```

The user presses "Step Over" (`next`).

The DAP server sends `next` to the debugger core. The debugger:
1. Sets `stepping_mode = "complete_block"`
2. Tells the interpreter to `complete_block()` — execute all commands in the current block
3. The interpreter executes: `CmdBrIf(i >= n, exit, loop)` — evaluates `i >= n`, finds it false, selects the `loop` target
4. The interpreter evaluates jump arguments: `i + 1` → new_i, `acc + xs[i]` → new_acc
5. The interpreter reaches the `CmdJump(loop, {new_i, new_acc})` followed by `CmdSealBlock(loop)` then `CmdSwitchToBlock(loop)`
6. At the `CmdSwitchToBlock(loop)`, the interpreter pauses
7. The debugger emits `stopped{reason="step"}` to the DAP server
8. The editor highlights the new location: still block `loop`, but with updated parameter values

The parameter values are now `i = 1, acc = 10` (assuming `xs = [5, 3], n = 2`).

**Step Into** (`stepIn` in DAP terminology):

In Lalin, there are no function calls within control flow blocks (all calls are either extern FFI calls or direct function calls, both of which are visible as `CmdCall` commands). "Step Into" behaves identically to "Step Over" for control flow — it executes the current block and stops at the next block boundary.

If the current statement is a `CmdCall(dest, target, args)` to a Lalin function, "Step Into" follows into the callee's first block. The interpreter pushes the current cursor onto the call stack and sets cursor to the callee's body.

**Step Out** (`stepOut` in DAP terminology):

"Step Out of Region" — the debugger sets a temporary breakpoint at all exit transitions (jumps to the exit block that correspond to `yield`). It then continues execution. When the exit block is reached, it pauses and reports `stopped{reason="step"}`.

Alternatively, the debugger tells the interpreter to `complete_region()` — execute until a `CmdReturnVoid`/`CmdReturnValue`/`CmdTrap` terminates the function, or until a `CmdJump(exit_block)` fires.

### Variable View

When paused at a block boundary, the DAP server sends `scopes` and `variables` requests.

The debugger responds with:
```
scopes: [{
    name: "Block Parameters",
    variablesReference: 2,
    namedVariables: 2
}]
```

Then `variables(variablesReference: 2)`:
```
variables: [
    {name: "i", value: "1", type: "index"},
    {name: "acc", value: "10", type: "i32"}
]
```

The type information comes from `Binding` facts in the editor schema (the `class` field contains `BindingClassBlockParam` or `BindingClassEntryBlockParam` with the region_id, label, and param index). The value comes from the interpreter's register file: for each block param name, the debugger looks up the corresponding `BackValId` (constructing it as `"ctl:{nonce}:{region}:{label}:{name}"`), reads the register, and formats it with the correct type.

If the block param is a pointer type, the variable shows the numeric address and (if provenance information exists) the pointed-to type.

### Stack Trace

The debugger's "stack trace" is a breadcrumb trail of block/region transitions:

```
stackFrames: [
    {
        id: 1,
        name: "fib:loop(i=1, acc=10)",
        source: {path: "fib.mlua"},
        line: 15,  -- line of the `block loop` keyword
        column: 1
    },
    {
        id: 2,
        name: "fib:entry(i=0, acc=0)",
        line: 12,  -- line of the `entry start` keyword
        column: 1
    }
]
```

This is NOT a call stack — it's a sequence of region/block transitions. The first frame is the current block. Each subsequent frame is a predecessor block (both within the same region via jumps, or across regions via yields/returns). If the program uses function calls (via `CmdCall`), the call stack frames are interleaved with the block breadcrumbs.

The `name` field uses the format `"{region_id}:{block_label}({param_name}={param_value}, ...)"` — this is a human-readable state machine state identifier.

### Continue

When the user presses "Continue" (`continue` in DAP), the debugger:

1. **If no breakpoints are active**: The debugger sets `paused = false` and lets the interpreter run at full speed (no pauses at block boundaries). When the interpreter reaches `terminated = true`, the debugger emits `terminated{}`.

2. **If breakpoints are active**: The debugger maintains a list of active breakpoint block labels. The interpreter calls `check_breakpoints()` after each `CmdSwitchToBlock`. This is a hash lookup and condition evaluation — fast enough that the overhead is negligible for the initial implementation.

3. **Future optimization (native JIT)**: When the interpreter overhead becomes a problem, the native fast path compiles via Cranelift and inserts `CmdTrap` at breakpoint positions. This requires trap-handler infrastructure (deferred).

---

## Hard Questions

### How does the interpreter handle `CmdCall` to extern functions?

The interpreter maintains an `extrn` table populated from the host pipeline's extern registry. When the debugger is instantiated, it receives the extern function mapping from the compiler's analysis context:

```lua
-- In lalin/host.lua (or equivalent extern provider):
-- The host pipeline already resolves extern symbols to FFI functions
-- The interpreter receives: {["write"] = ffi.C.write, ["host_add7"] = host_add7_impl}

-- In interpreter step for CmdCall with BackCallExtern:
function interpreter:handle_call(cmd)
    local target = cmd.target -- BackCallExtern(func_id)
    local func_name = cmd.target.func.text
    local args = {}
    for i = 1, #cmd.args do
        args[i] = self.registers[cmd.args[i].text]
    end
    local fn = self.extrn[func_name]
    if not fn then
        error("extern function not found: " .. func_name)
    end
    local result = fn(unpack(args))
    if cmd.result.kind == "BackCallValue" then
        self.registers[cmd.result.dst.text] = result
    end
end
```

The `extrn` table is populated from the same extern declarations that the Rust JIT uses. For the hosted pipeline (`lalin.loadstring`), these are LuaJIT FFI function handles. For the MOM pipeline, they're native function pointers. The interpreter doesn't care about the implementation — it just calls them.

**Edge cases**:
- Extern functions that modify memory (e.g., `memcpy`) — the interpreter's simulated heap must be exposed to the FFI call. This means the simulated heap must be a LuaJIT FFI-accessible buffer (e.g., `ffi.new("uint8_t[?]", size)`) for the duration of the call.
- Extern functions that block indefinitely — the interpreter can't preempt them. The user would need to forcefully terminate the debugging session.
- Extern functions that throw Lua errors — caught by pcall in the interpreter, reported as an exception event.

### How does the interpreter handle memory operations?

The interpreter maintains a simulated heap as a table of byte arrays:

```lua
-- Data regions (from CmdDeclareData)
self.data_regions[data_id] = ffi.new("uint8_t[?]", size)

-- Stack slots (from CmdCreateStackSlot)
self.stack_slots[slot_id] = ffi.new("uint8_t[?]", size)
```

`CmdLoad(dst, addr)` resolves the address to a specific byte range in a data region or stack slot, reads the appropriate number of bytes, and decodes them according to the scalar type:

```lua
function interpreter:handle_load(cmd)
    local addr = self:resolve_address(cmd.addr)
    local size = self:scalar_size(cmd.ty)
    local ptr = ffi.cast("uint8_t*", addr)
    if cmd.ty == BackI32 or cmd.ty == BackU32 then
        self.registers[cmd.dst.text] = ffi.cast("int32_t*", ptr)[0]
    elseif cmd.ty == BackI64 or cmd.ty == BackU64 then
        self.registers[cmd.dst.text] = ffi.cast("int64_t*", ptr)[0]
    elseif cmd.ty == BackF32 then
        self.registers[cmd.dst.text] = ffi.cast("float*", ptr)[0]
    elseif cmd.ty == BackF64 then
        self.registers[cmd.dst.text] = ffi.cast("double*", ptr)[0]
    end
end
```

`CmdStore(addr, value)` writes the raw value bytes to the address using the appropriate width.

`CmdMemcpy`, `CmdMemset`, `CmdMemcmp` operate on the byte arrays directly using `ffi.copy`, `ffi.fill`, and `ffi.compare` respectively.

Address resolution converts a `BackAddress` (with base and byte_offset) to an absolute address in the simulated address space:

```lua
function interpreter:resolve_address(addr)
    local base = self.registers[addr.base.value.text]
    local offset = self.registers[addr.byte_offset.text]
    return base + offset  -- numeric addresses into a flat byte array
end
```

For simplicity, the interpreter uses a single flat address space (a large `ffi.new("uint8_t[?]", max_size)` buffer). All allocations (data regions, stack slots) are offsets into this buffer. This simplifies pointer arithmetic and makes extern FFI calls safe (the buffer is a real C array pointer).

### How does the interpreter handle `CmdTrap`?

`CmdTrap` is a non-resumable trap in native code. In the interpreter, it's simply an event:

```lua
function interpreter:handle_trap(cmd)
    self.terminated = true
    self:emit_event("exception", {
        description = "trap in user code",
        block = self.current_block
    })
end
```

The debugger reports this as a DAP `stopped{reason="exception"}` event. The user can inspect the current parameter values at the trap site (the block whose body contained the trap).

### How does "continue" with breakpoints work if native code is used?

**Phase 1 (interpreter always)**: "Continue" is simply the interpreter running without pausing at block boundaries. The interpreter checks breakpoints only at `CmdSwitchToBlock` boundaries — this is a hash lookup (O(1) with the block label string). Condition functions are Lua closures evaluated at each block entry. This is fast enough for initial debugging.

**Phase 2 (native with trap insertion)**: When the interpreter's per-block-entry overhead becomes a problem (tight loops with millions of iterations), the native path inserts `CmdTrap` commands at target block entries:

1. For each active breakpoint, find the `CmdSwitchToBlock(bid)` command that enters that block
2. After that command, insert `CmdTrap`
3. Re-encode the command stream and re-JIT

The trap handler (a Rust-side signal handler for `ud2`) reports `bid` back to Lua via a shared memory cell or an FFI callback. The Lua debugger reads the trap site block ID and checks breakpoint conditions.

This requires implementing the trap handler infrastructure that the critique identified as high-risk. It is explicitly deferred until the interpreter-only approach is proven insufficient. The architecture does not depend on it.

### How does the DAP server coexist with the LSP server?

Both servers share the same `rpc_stdio_loop.lua` STDIN/STDOUT. The dispatching is by DAP method prefix:

```lua
local DAP_METHODS = {
    initialize = true, setBreakpoints = true, setFunctionBreakpoints = true,
    continue = true, next = true, stepIn = true, stepOut = true,
    pause = true, stackTrace = true, scopes = true, variables = true,
    disconnect = true, terminate = true, launch = true, attach = true,
    configurationDone = true, threads = true, setExceptionBreakpoints = true,
    goto = true, gotoTargets = true, source = true,
}

function is_dap_method(method)
    return DAP_METHODS[method] == true or method:match("^dap/")
end
```

In the loop:

```lua
function M.run(opts)
    local dap_handler = opts.dap_handler
    local lsp_handler = opts.lsp_handler or M.default_lsp_handler()

    while running do
        local body = read_message(input)
        local incoming = Json.decode_message(body)
        local method = incoming.method or (incoming.command and incoming.command:gsub("^dap/", ""))

        if is_dap_method(method) then
            dap_handler:handle(incoming, output)
        else
            lsp_handler:handle(incoming, output, state)
        end
    end
end
```

The DAP handler maintains its own state (debugger core, interpreter instance) separate from the LSP workspace state. They share read-only access to the analysis context (anchors, binding facts, provenance) through the common `T` (ASDL context) and `analysis_ctx` objects.

### What happens when source code changes while debugging?

When the user edits a file and saves, the LSP receives a `ClientDidChange` event, which triggers re-parsing, re-typechecking, and re-lowering of the affected module. The PVM cache ensures that only changed subtrees recompute.

The debugger detects the change via a file modification hook or a DAP `setBreakpoints` request arriving after a save. The debugger:

1. **Pauses the interpreter** (if running)
2. **Invalidates the current `BackCmd[]`** — the old command stream is stale
3. **Triggers re-compilation**: re-run the pipeline (parse → typecheck → layout → lower) to get a new `BackCmd[]` and new provenance
4. **Rebuilds the interpreter state**: new register file (empty), new block boundary map, new extern table
5. **Attempts to restore the current execution point**: if the block label that was paused on still exists in the new `BackCmd[]`, resume at that block's entry with initial parameter values. If the block was deleted, show a warning and start from the new module's entry point.
6. **Resets breakpoints**: verify that each breakpoint's block label still exists in the new `BackCmd[]`. Remove stale breakpoints, emit DAP `breakpoint{verified: false}` for removed blocks.

The recompilation is fast because PVM phases cache their outputs. Only the `lalin_tree_module_to_back` phase and downstream phases need to re-run for the changed file.

### What happens when an interpreted block contains a loop that runs 1M iterations?

It is slow. The interpreter executes each command sequentially in Lua — for a tight loop body with ~10 commands (compare, branch, add, load, jump), 1M iterations means ~10M interpreted commands. At best, LuaJIT can interpret at ~10-20 million simple operations per second, so 1M loop iterations take about 0.5-1 second.

This is acceptable for interactive debugging — the user is intentionally stepping through their program to understand behavior. When they don't need to step, they press "Continue" and the interpreter runs without pausing (still interpreting, but not stopping at each block). For production debugging of hot loops, the native fast path (Phase 2) is the solution.

The architecture explicitly accepts this performance tradeoff. The alternative (native execution with trap handlers) would require the fragile signal-handling infrastructure that the critique rejected.

### How does the interpreter handle CmdCall to direct Lalin functions?

When `CmdCall(dest, target, args)` targets a direct Lalin function (not an extern), the interpreter:

1. Looks up the function's body (`BackCmd[]`) in a `functions` table built during module lowering
2. Pushes the current state onto a call stack: `{cursor, registers, current_block, current_region_id}`
3. Sets cursor to the callee's first `CmdBeginFunc` → body start
4. Allocates new block params for the callee's entry block
5. Evaluates call arguments and binds them to entry block params
6. Resumes interpretation

On `CmdReturnVoid`/`CmdReturnValue`:
1. Pops the call stack
2. Restores cursor to the command after `CmdCall`
3. Stores return value in the result register

The call stack is also what the DAP's `stackTrace` returns — it shows both the Lalin call frames and the block breadcrumbs within each frame.

### How does the interpreter handle CmdSwitchInt?

`CmdSwitchInt` is a multi-way branch. The interpreter:
1. Evaluates the switch value from registers
2. Iterates through `cases[]`, comparing each case's `raw` against the value
3. If a match is found, selects the target block (same as `CmdBrIf` then-branch)
4. If no match, selects `default_dest`
5. For the selected target: evaluates target block params (from `CmdAppendBlockParam` declarations, the interpreter reads the jump target's param specs)
6. Stores param values as `pending_bindings`
7. Advances cursor to the block's `CmdSwitchToBlock`
8. Pauses (if in stepping mode)

---

## Implementation Plan

### Phase 1: Foundation (~300 lines)

1. **Provenance enhancement** (`tree_control_to_back.lua`, 5 lines): Thread `provenance` into `lower_region()` and record block-level entries after each `CmdCreateBlock`.

2. **Interpreter skeleton** (`lua/lalin/debug_interpreter.lua`, ~200 lines): Implement the core interpreter loop, register file, block boundary detection, and basic command handlers (control flow, constants, arithmetic, comparisons).

3. **Debugger core skeleton** (`lua/lalin/debugger_core.lua`, ~100 lines): State machine, stepping modes, `pause()`/`continue()`/`step_block()`.

### Phase 2: Breakpoints and LSP Bridge (~200 lines)

4. **Breakpoint resolver** (`lua/lalin/dap_breakpoint_resolver.lua`, ~80 lines): Map source lines → `AnchorContinuationName` → `BlockLabel` using anchor index.

5. **Breakpoint table** in debugger_core (~50 lines): Insert/remove/check breakpoints, condition evaluation.

6. **LSP integration** (~70 lines): Extend `editor_subject_at.lua` or add a new module to resolve `BlockLabel` → source range (reverse of the breakpoint resolver).

### Phase 3: Memory and Extern Calls (~200 lines)

7. **Memory simulation** in interpreter (`debug_interpreter.lua`, ~100 lines): Simulated heap with flat address space, `CmdLoad`/`CmdStore`/`CmdMemcpy`/`CmdMemset` handlers.

8. **Extern call handling** in interpreter (`debug_interpreter.lua`, ~50 lines): FFI function lookup, argument marshaling, result capture.

9. **Lalin function calls** in interpreter (`debug_interpreter.lua`, ~50 lines): Call stack management, direct function body lookup.

### Phase 4: DAP Server (~400 lines)

10. **DAP server** (`lua/lalin/dap_server.lua`, ~300 lines): DAP protocol implementation with all required requests and events.

11. **STDIO loop integration** (`rpc_stdio_loop.lua`, ~30 lines): Add DAP method dispatching.

12. **Variable inspection** (`lua/lalin/dap_variables.lua`, ~70 lines): Format block parameter values with types from binding facts.

### Phase 5: Trace Recording (Future, ~300 lines)

13. **Trace recorder** in interpreter (~50 lines): Record every block entry with parameter values.

14. **Trace explorer** (`lua/lalin/debug_trace_explorer.lua`, ~250 lines): Timeline view, filter by block/param value/condition, reverse-step navigation.

### Total implementation cost

| Component | Lines | New/Modified |
|-----------|-------|--------------|
| Provenance enhancement | ~5 | Modified (`tree_control_to_back.lua`) |
| Interpreter | ~400 | New (`debug_interpreter.lua`) |
| Debugger core | ~150 | New (`debugger_core.lua`) |
| Breakpoint resolver | ~80 | New (`dap_breakpoint_resolver.lua`) |
| DAP server | ~300 | New (`dap_server.lua`) |
| DAP variables | ~70 | New (`dap_variables.lua`) |
| STDIO loop integration | ~30 | Modified (`rpc_stdio_loop.lua`) |
| LSP integration | ~70 | New/Modified |
| **Total** | **~1105** | |

Zero new Rust code. Zero signal handlers. Zero DWARF. Zero traps.

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| **Interpreter too slow for practical debugging** | Medium | Most debugging workflows spend time paused (examining state). Tight loop iteration is fast enough (1M iterations ~1s). Native fast path with trap insertion is a well-defined future upgrade path. |
| **Extern FFI calls crash in interpreter** | Low | The simulated heap is a real `ffi.new("uint8_t[?]")` buffer — extern functions see valid memory. All extern calls are wrapped in pcall. |
| **Source code changes during debugging leave stale state** | Medium | Re-compilation preserves breakpoints for blocks that still exist. Rebuilding the interpreter from scratch is fast (PVM cache hits). The user loses runtime state (current block, param values) and must restart execution. |
| **DAP protocol gaps for Lalin-specific features** | Medium | DAP supports custom requests via `"supportsCustomRequest"` capability. Block-label breakpoints can be exposed as DAP function breakpoints (DAP has `setFunctionBreakpoints`). The block breadcrumb "stack trace" is a valid DAP stack frame list — each frame has a name that includes block labels and param values. |
| **Multiple threads/concurrent execution** | Low | Lalin is currently single-threaded. The interpreter is inherently single-threaded. If threading is added later, the interpreter would need per-thread state. |
| **Interpreter correctness vs. native execution** | High | The interpreter is an alternative execution engine. It must match the Cranelift JIT's semantics exactly. Differences in integer overflow behavior, floating-point rounding, or memory layout could cause the interpreter to disagree with native execution. **Mitigation**: The interpreter is used for debugging, not for production. Minor semantic differences (e.g., trapping on overflow vs. wrapping) are acceptable tradeoffs for interactive debugging. The `back_validate.lua` validation pass catches many semantic mismatches at the BackCmd level. |

## Edit-planner Output — 2026-05-21 19:59:46

Now I have all the information needed. Let me produce the comprehensive implementation plan.

---

## Implementation Plan: Lalin Debugger (Semantic Block-Trace)

### Precondition Checks

Before any edits begin, verify:
1. `lua/lalin/tree_control_to_back.lua` still has `lower_region` at line 353 with 6 params (no provenance param added yet)
2. `lua/lalin/tree_to_back.lua` still has `control_api` defined at line 2159 with the current `base` table
3. `lua/lalin/tree_to_back.lua` still has `lower_module_direct` at line 2596 and item-level provenance at line 2604
4. `lua/lalin/rpc_stdio_loop.lua` still has `run()` at line 30 with the current message-dispatch loop
5. `lua/lalin/frontend_pipeline.lua` still creates `analysis_ctx.anchors` and passes it through to lowering
6. Check that `lua/lalin/back_provenance.lua` `record()` function signature is `record(cmd_start, cmd_end, source_range, doc_uri, name)` — if name is provided but source_range is nil, it stores a name-only entry

---

### Phase 1: Foundation

#### 1.1 `lua/lalin/tree_to_back.lua` — Thread provenance into the `base` table passed to `tree_control_to_back`

**Goal**: Make the `lower_context.provenance` accessible from within `tree_control_to_back.lua` by passing it through the `base` parameter table.

**Edit block 1**: Lines 2159-2167 — Add `provenance` accessor to the `base` table.

**Before** (lines 2159-2167):
```lua
    control_api = require("lalin.tree_control_to_back").Define(T, {
        env_add = env_add,
        env_with_locals = env_with_locals,
        env_with_counters = env_with_counters,
        env_next_block = env_next_block,
        expr_to_back = expr_to_back,
        stmt_to_back = stmt_to_back,
        back_scalar = back_scalar,
        const_eval = const_eval_api,
        get_const_env = function() return lower_context.const_env end,
    })
```

**After** (lines 2159-2168):
```lua
    control_api = require("lalin.tree_control_to_back").Define(T, {
        env_add = env_add,
        env_with_locals = env_with_locals,
        env_with_counters = env_with_counters,
        env_next_block = env_next_block,
        expr_to_back = expr_to_back,
        stmt_to_back = stmt_to_back,
        back_scalar = back_scalar,
        const_eval = const_eval_api,
        get_const_env = function() return lower_context.const_env end,
        get_provenance = function() return lower_context.provenance end,
    })
```

**Quirks**: The `base` table is the second argument to `tree_control_to_back.Define(T, base)`. Inside `tree_control_to_back`, it's accessed as `base.*`.

---

#### 1.2 `lua/lalin/tree_control_to_back.lua` — Record block-level provenance

**Goal**: For each block in a control region, record a provenance entry mapping the `CmdCreateBlock` command index to the block's label name. This enables name-based anchor resolution later.

**Edit block 1**: Lines 106-121 (the `declare_blocks` function) — After each `CmdCreateBlock`, record a provenance entry.

This requires knowing the command index of each `CmdCreateBlock`. The `declare_blocks` function takes `cmds` as a table and appends to it. After each `cmds[#cmds + 1] = Back.CmdCreateBlock(...)`, we know the index is `#cmds`.

Add recording after each `CmdCreateBlock`. We need `base.get_provenance` to be available.

**Before** (lines 106-121):
```lua
    local function declare_blocks(cmds, records, exit_block, exit_value, exit_scalar)
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
            for j = 1, #records[i].params do
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, records[i].params[j].value, shape_scalar(records[i].params[j].scalar))
            end
        end
        cmds[#cmds + 1] = Back.CmdCreateBlock(exit_block)
        if exit_value ~= nil then
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(exit_block, exit_value, shape_scalar(exit_scalar))
        end
    end
```

**After** (lines 106-126):
```lua
    local function declare_blocks(cmds, records, exit_block, exit_value, exit_scalar)
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
            local provenance = base.get_provenance()
            if provenance then
                provenance:record(#cmds, #cmds, nil, nil,
                    "block:" .. tostring(records[i].label.name))
            end
            for j = 1, #records[i].params do
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, records[i].params[j].value, shape_scalar(records[i].params[j].scalar))
            end
        end
        cmds[#cmds + 1] = Back.CmdCreateBlock(exit_block)
        local provenance = base.get_provenance()
        if provenance then
            provenance:record(#cmds, #cmds, nil, nil,
                "block:" .. tostring(exit_block.text))
        end
        if exit_value ~= nil then
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(exit_block, exit_value, shape_scalar(exit_scalar))
        end
    end
```

**Edit block 2**: Lines 353-389 (the `lower_region` function) — The function signature and body will be left unchanged; the provenance is recorded inside `declare_blocks`. However, we may also want to record provenance for `CmdSwitchToBlock` commands so the interpreter can map "about to execute block X" to source position.

Add provenance recording after each `CmdSwitchToBlock` in the body loop (after line 369).

**Before** (lines 368-375):
```lua
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(records[i].block)
            local start = add_param_locals(current, outside_locals, records[i].params)
            local body_env, body_cmds, flow = lower_body(records[i].body, start, ctx)
            append_all(cmds, body_cmds)
```

**After** (lines 368-376):
```lua
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(records[i].block)
            local provenance = base.get_provenance()
            if provenance then
                provenance:record(#cmds, #cmds, nil, nil,
                    "switch:" .. tostring(records[i].label.name))
            end
            local start = add_param_locals(current, outside_locals, records[i].params)
            local body_env, body_cmds, flow = lower_body(records[i].body, start, ctx)
            append_all(cmds, body_cmds)
```

**Patterns**: Use `"block:{label}"` prefix for block declarations and `"switch:{label}"` for switch-to-block commands. This distinguishes which kind of provenance entry is being recorded. The debugger will query for `"block:"` or `"switch:"` prefixed names.

**Danger zones**: The `declare_blocks` function is called exactly once per `lower_region` invocation. The provenance must NOT be called if `base.get_provenance` returns `nil` (which it won't in the normal lowering path — `with_module_context` always creates it, but guard anyway).

---

#### 1.3 NEW: `lua/lalin/debug_interpreter.lua` — Interpreter skeleton

**Purpose**: Walk `BackCmd[]` sequentially, maintain a virtual register file, and pause at block boundaries. This is the core execution engine for debugging.

**Contents sketch** (~400 lines):

```lua
-- lalin/debug_interpreter.lua
-- Pure-Lua BackCmd[] interpreter for block-transition debugging.
-- Maintains a virtual register file, a flat address space for memory,
-- and pauses at block boundaries for stepping control.

local pvm = require("lalin.pvm")

local M = {}

local Interpreter = {}
Interpreter.__index = Interpreter

--- Create a new interpreter instance.
-- @param cmds  BackCmd[] — the flat command stream to execute
-- @param opts  table with optional fields:
--   extrn: {[name] = function} — extern FFI function table
--   functions: {[func_id] = BackCmd[]} — direct function bodies
--   max_registers: number — register file capacity (default 4096)
-- @return Interpreter instance
function M.new(cmds, opts)
    opts = opts or {}
    local self = setmetatable({
        cmds = cmds,
        cursor = 1,
        cursor_limit = #cmds,
        registers = {},        -- BackValId.text → raw_value
        current_block = nil,   -- BackBlockId.text
        paused = false,
        terminated = false,
        return_value = nil,
        trap_reason = nil,
        pending_jump_target = nil,  -- {target, args} for conditional jumps
        extrn = opts.extrn or {},
        functions = opts.functions or {},
        call_stack = {},       -- [{cursor, registers, current_block}]
        -- Address space: flat byte array via FFI
        memory_size = opts.memory_size or (1024 * 1024 * 64),  -- 64MB default
        memory = nil,          -- ffi byte array, lazily allocated
        stack_slots = {},      -- slot_id.text → {offset, size}
        next_stack_offset = 0,
        data_regions = {},     -- data_id.text → {offset, size}
        next_data_offset = 0,
        -- Stepping
        step_mode = "none",    -- "block" | "continue" | "none"
        breakpoints = {},      -- {[block_label] = {enabled, condition_fn}}
        event_handler = nil,   -- function(event_type, data)
        -- Block metadata
        block_provenance = {}, -- block_label → {cmd_start, cmd_end, name}
    }, Interpreter)

    -- Build block boundary map
    self:_build_block_map()
    -- Build function body map
    self:_build_func_map()
    return self
end

--- Build a map of block boundaries from the command stream.
-- Scans for CmdSwitchToBlock commands and records their positions.
function Interpreter:_build_block_map()
    self.switch_to_block_map = {}  -- cmd_index → block_id.text
    self.block_entry_indices = {}  -- block_id.text → cmd_index
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == Back.CmdSwitchToBlock then
            local bid = cmd.block.text
            self.switch_to_block_map[i] = bid
            self.block_entry_indices[bid] = i
        elseif cls == Back.CmdCreateBlock then
            self.block_creation_order = self.block_creation_order or {}
            self.block_creation_order[#self.block_creation_order + 1] = cmd.block.text
        end
    end
end

--- Build a map from BackFuncId to function body index range.
function Interpreter:_build_func_map()
    self.func_map = {}  -- func_id.text → {start_idx, end_idx}
    local in_func = nil
    local func_start = nil
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == Back.CmdDeclareFunc then
            in_func = cmd.func.text
            func_start = i
        elseif cls == Back.CmdBeginFunc then
            -- body starts after CmdBeginFunc
            if in_func then
                self.func_map[in_func] = { start_idx = i + 1, end_idx = nil }
            end
        elseif cls == Back.CmdFinishFunc then
            if in_func and self.func_map[in_func] then
                self.func_map[in_func].end_idx = i - 1
            end
            in_func = nil
            func_start = nil
        end
    end
end

--- Execute one command and advance cursor.
-- Returns true if execution should continue, false if paused or terminated.
function Interpreter:step()
    if self.terminated then return false end
    if self.cursor > self.cursor_limit then
        self.terminated = true
        return false
    end

    local cmd = self.cmds[self.cursor]
    local cls = pvm.classof(cmd)

    -- Dispatch to command handler
    self:_dispatch(cmd, cls)

    -- Advance cursor (unless blocked by a pending jump)
    if self.cursor <= self.cursor_limit then
        self.cursor = self.cursor + 1
    end

    -- Check for pause conditions
    if self.paused then return false end

    return not self.terminated
end

--- Main dispatch: routes each command class to its handler.
-- @param cmd  the BackCmd instance
-- @param cls  the ASDL class of the command (pre-computed for speed)
function Interpreter:_dispatch(cmd, cls)
    local Back = _G.Back or require("lalin.schema.back")  -- cached at init
    -- Use a handler table for O(1) dispatch
    local handler = self._handlers[cls]
    if handler then
        handler(self, cmd)
    else
        -- Unknown command: skip (may be missed in early implementation)
    end
end

-- Handler table built at initialization.
Interpreter._handlers = {}

-- Register handlers (simplified; actual registration in init)
-- The pattern for each handler:

function Interpreter:_handle_const(cmd)
    -- CmdConst(dst, scalar, lit)
    local val = self:_lit_to_value(cmd.lit)
    self.registers[cmd.dst.text] = val
end

function Interpreter:_handle_int_binary(cmd)
    -- CmdIntBinary(dst, op, scalar, sem, lhs, rhs)
    local lv = self.registers[cmd.lhs.text]
    local rv = self.registers[cmd.rhs.text]
    local val = self:_int_binary_op(cmd.op, lv, rv)
    self.registers[cmd.dst.text] = val
end

function Interpreter:_handle_jump(cmd)
    -- CmdJump(dest, args)
    local args = {}
    for i = 1, #cmd.args do
        args[i] = self.registers[cmd.args[i].text]
    end
    self.pending_jump_target = { target = cmd.dest.text, args = args }
    -- The jump is resolved at the next CmdSwitchToBlock
end

function Interpreter:_handle_br_if(cmd)
    -- CmdBrIf(cond, then_block, then_args, else_block, else_args)
    local cond_val = self.registers[cmd.cond.text]
    if cond_val then
        self.pending_jump_target = { target = cmd.then_block.text, args = self:_resolve_args(cmd.then_args) }
    else
        self.pending_jump_target = { target = cmd.else_block.text, args = self:_resolve_args(cmd.else_args) }
    end
end

function Interpreter:_handle_switch_int(cmd)
    -- CmdSwitchInt(value, ty, cases, default)
    local val = self.registers[cmd.value.text]
    local matched = false
    for _, case in ipairs(cmd.cases) do
        if tostring(val) == case.raw then
            self.pending_jump_target = { target = case.block.text, args = {} }
            matched = true
            break
        end
    end
    if not matched then
        self.pending_jump_target = { target = cmd.default.text, args = {} }
    end
end

function Interpreter:_handle_switch_to_block(cmd)
    -- CmdSwitchToBlock(block)
    if self.pending_jump_target then
        -- Resolve the pending jump: bind block params
        -- (block params were declared via CmdAppendBlockParam)
        local bid = cmd.block.text
        self.current_block = bid

        -- Bind parameters: the last CmdAppendBlockParam declarations for this block
        -- define which values are expected. The jump args supply them.
        if self.pending_jump_target.target == bid then
            -- Bind args to registers for this block's params
            -- (details depend on CmdAppendBlockParam tracking)
            self:_bind_block_params(bid, self.pending_jump_target.args)
        end
        self.pending_jump_target = nil

        -- Pause at block boundary if stepping
        if self.step_mode == "block" then
            self.paused = true
            self:emit_event("step", { block = bid })
        end

        -- Check breakpoints for this block
        if self.step_mode ~= "step_block" and not self.paused then
            self:_check_breakpoints(bid)
        end
    end
    -- If the switch-to-block is the very first block (module entry),
    -- there's no pending jump — we just start executing.
    if self.current_block == nil then
        self.current_block = cmd.block.text
    end
end

--- Bind block parameters from jump arguments.
-- When entering a block, map the jump arg values to the block's
-- formal parameter names (defined by CmdAppendBlockParam).
-- @param bid  string — BackBlockId.text of the target block
-- @param args  array of raw values from jump
function Interpreter:_bind_block_params(bid, args)
    local param_names = self.block_params[bid]  -- built during init
    if not param_names then return end
    for i = 1, #param_names do
        local name = param_names[i]
        self.registers[name] = args[i] or 0
    end
end

--- Build the block_params map by scanning for CmdAppendBlockParam commands.
-- Called during init.
function Interpreter:_build_block_params_map()
    self.block_params = {}  -- bid → {param_backvalid.text, ...}
    -- Scan all CmdCreateBlock + CmdAppendBlockParam commands
    -- to build the mapping from block ID to param names.
    local current_bid = nil
    for i, cmd in ipairs(self.cmds) do
        local cls = pvm.classof(cmd)
        if cls == Back.CmdCreateBlock then
            current_bid = cmd.block.text
            if not self.block_params[current_bid] then
                self.block_params[current_bid] = {}
            end
        elseif cls == Back.CmdAppendBlockParam then
            if current_bid then
                self.block_params[current_bid][#self.block_params[current_bid] + 1] = cmd.value.text
            end
        end
    end
end

-- Step control API:

function Interpreter:step_block()
    self.step_mode = "block"
    self.paused = false
    while self:step() do
        if self.paused then
            self.step_mode = "none"
            return self.current_block
        end
    end
    return nil
end

function Interpreter:continue_until(breakpoints_fn)
    self.breakpoints_fn = breakpoints_fn
    self.step_mode = "continue"
    self.paused = false
    while self:step() do
        if self.paused then
            return self:_pause_event()
        end
    end
    return { type = "terminated" }
end

function Interpreter:pause()
    self.paused = true
end

function Interpreter:emit_event(event_type, data)
    if self.event_handler then
        self.event_handler(event_type, data)
    end
end

-- Register accessor for the debugger
function Interpreter:read_register(name)
    return self.registers[name]
end

function Interpreter:read_all_registers()
    local out = {}
    for k, v in pairs(self.registers) do
        out[k] = v
    end
    return out
end

return M
```

**Key design decisions**:
- `_handlers` table for O(1) command dispatch (vs. a big if/elseif chain)
- `pending_jump_target` model: `CmdJump`/`CmdBrIf`/`CmdSwitchInt` set a pending target; the next `CmdSwitchToBlock` resolves it. This matches how the Rust decoder works.
- `block_params` map built during init by scanning `CmdAppendBlockParam` commands
- Registers keyed by `BackValId.text` (string), since the IDs are human-readable strings like `"ctl:1:fib_loop:loop:i"`

**Dependencies**:
- `pvm` (for `pvm.classof`)
- Schema modules (`Back.*` variants), resolved via globals or imported schema

**Edge cases**:
- `CmdBindEntryParams` at function entry: map entry params directly to registers
- `CmdSealBlock`: no-op in interpreter (block boundaries are implicit)
- `CmdReturnVoid`/`CmdReturnValue`: set `terminated = true`, store return value
- `CmdCall`: push call stack, jump to callee body, or call extern function
- `CmdTrap`: set `terminated = true`, emit `"trap"` event
- `CmdCreateStackSlot`: allocate a stack slot offset in the flat address space
- Uninitialized registers: return 0/false as default (Lua `nil` → 0)

**Handler registration pattern** (in `init` of Interpreter):
```lua
-- Map Back class names to handler methods
Interpreter._handler_map = {
    CmdConst = "_handle_const",
    CmdIntBinary = "_handle_int_binary",
    -- ... etc
}
-- At init time, resolve class objects to handler methods
function Interpreter:_init_handlers()
    self._handlers = {}
    for cls_name, method_name in pairs(Interpreter._handler_map) do
        local cls = _G.Back["Back" .. cls_name]
        if cls then
            self._handlers[cls] = Interpreter[method_name]
        end
    end
end
```

---

#### 1.4 NEW: `lua/lalin/debugger_core.lua` — Debugger core

**Purpose**: State machine for stepping, breakpoint management, and coordination between the interpreter and DAP server.

**Contents sketch** (~150 lines):

```lua
-- lalin/debugger_core.lua
-- Debugger state machine: stepping modes, breakpoint table, pause/resume.

local pvm = require("lalin.pvm")
local Interpreter = require("lalin.debug_interpreter")

local M = {}

local Debugger = {}
Debugger.__index = Debugger

--- States
local STATE_IDLE = "idle"
local STATE_RUNNING = "running"
local STATE_PAUSED = "paused"
local STATE_TERMINATED = "terminated"

--- Create a new debugger instance.
-- @param opts  table:
--   source_uri: string — document URI for breakpoint resolution
--   anchors: AnchorSet — for anchor-based breakpoint resolution
--   extrn: {[name] = function} — extern functions for interpreter
--   functions: {[func_id] = BackCmd[]} — direct function bodies
function M.new(cmds, opts)
    opts = opts or {}
    local self = setmetatable({
        state = STATE_IDLE,
        interpreter = nil,
        cmds = cmds,
        breakpoints = {},       -- {[label_key] = {enabled, condition_fn, hit_count, temporary}}
        source_lines_to_block = {},  -- line_number → {region_id, block_label}[]
        current_block = nil,
        current_region = nil,
        last_event = nil,
        event_handlers = {},    -- {[event_type] = {handler_fn, ...}}
        opts = opts,
    }, Debugger)

    return self
end

--- Initialize: create interpreter and set to paused at first block entry.
function Debugger:init()
    self.interpreter = Interpreter.new(self.cmds, {
        extrn = self.opts.extrn or {},
        functions = self.opts.functions or {},
    })
    self.interpreter.event_handler = function(event_type, data)
        self:_on_interpreter_event(event_type, data)
    end
    self.state = STATE_PAUSED
    -- Prime the interpreter to pause at first block boundary
    self.interpreter.step_mode = "block"
    return self
end

--- Run until first pause.
function Debugger:start()
    if self.state ~= STATE_PAUSED then
        return nil, "debugger not paused"
    end
    self.interpreter:step_block()
    return self.current_block
end

--- Step one block transition.
function Debugger:step_block()
    if self.state ~= STATE_PAUSED then return nil, "not paused" end
    self.state = STATE_RUNNING
    local block = self.interpreter:step_block()
    self.state = STATE_PAUSED
    self.current_block = block
    return block
end

--- Continue until breakpoint or termination.
function Debugger:continue()
    if self.state ~= STATE_PAUSED then return nil, "not paused" end
    self.state = STATE_RUNNING
    local result = self.interpreter:continue_until(function(bid)
        return self:_check_breakpoints(bid)
    end)
    self.state = STATE_PAUSED
    self.last_event = result
    return result
end

--- Poll interpreter for pause without blocking.
function Debugger:poll()
    if self.state == STATE_RUNNING and self.interpreter.paused then
        self.state = STATE_PAUSED
    end
    return self.state
end

--- Set a breakpoint on a block label.
-- @param block_label  string — block label name (e.g. "loop", "start")
-- @param opts  {condition_fn, region_id, temporary}
-- @return breakpoint id or nil
function Debugger:set_breakpoint(block_label, opts)
    opts = opts or {}
    local key = block_label .. (opts.region_id and ":" .. opts.region_id or "")
    self.breakpoints[key] = {
        enabled = true,
        condition_fn = opts.condition_fn,
        hit_count = 0,
        temporary = opts.temporary or false,
        region_id = opts.region_id,
    }
    return key
end

--- Remove a breakpoint.
function Debugger:clear_breakpoint(key)
    self.breakpoints[key] = nil
end

--- Get current variable values (block parameters).
function Debugger:get_variables()
    if not self.interpreter then return {} end
    local regs = self.interpreter:read_all_registers()
    -- Filter to only block param registers (those matching the naming pattern)
    local vars = {}
    for name, value in pairs(regs) do
        -- "ctl:{nonce}:{region}:{label}:{param}"
        -- Strip the prefix to show just param_name
        local param_name = name:match(":([^:]+)$")
        if param_name then
            vars[param_name] = value
        end
    end
    return vars
end

--- Map a source line to block label names using the anchor index.
-- @param line  number — 0-based line number
-- @return array of {block_label, region_id} or empty array
function Debugger:resolve_line_to_block(line)
    -- Uses the anchor set to find AnchorContinuationName anchors
    -- at the given line. Built during init from opts.anchors + PositionIndex.
    return self.source_lines_to_block[line] or {}
end

--- Internal breakpoint check, called by interpreter at each block entry.
function Debugger:_check_breakpoints(bid)
    -- Parse block label from BackBlockId text
    local label = self:_parse_block_label(bid)
    if not label then return false end

    local key = label
    local bp = self.breakpoints[key]
    if not bp or not bp.enabled then return false end

    bp.hit_count = (bp.hit_count or 0) + 1

    -- Evaluate condition
    if bp.condition_fn then
        local vars = self:get_variables()
        if not bp.condition_fn(vars) then return false end
    end

    -- Auto-remove temporary breakpoints (for stepping)
    if bp.temporary then
        self.breakpoints[key] = nil
    end

    return true
end

--- Parse a BackBlockId to extract the label name.
-- Format: "ctl:{nonce}:{region}:{label}"
function Debugger:_parse_block_label(bid)
    local parts = bid and bid.text and bid.text:split(":")
    if not parts or #parts < 4 then return nil end
    return parts[#parts]  -- label is the last segment
end

--- Register an event handler.
-- @param event_type  string — "paused", "terminated", "breakpoint"
-- @param fn  function(event_data)
function Debugger:on(event_type, fn)
    if not self.event_handlers[event_type] then
        self.event_handlers[event_type] = {}
    end
    self.event_handlers[event_type][#self.event_handlers[event_type] + 1] = fn
end

function Debugger:_on_interpreter_event(event_type, data)
    for _, handler in ipairs(self.event_handlers[event_type] or {}) do
        handler(data)
    end
end

-- Pause execution
function Debugger:pause()
    if self.interpreter then
        self.interpreter:pause()
    end
end

-- Get call stack (breadcrumb trail)
function Debugger:stack_trace()
    local stack = {}
    if self.current_block then
        stack[#stack + 1] = {
            block = self.current_block,
            params = self:get_variables(),
        }
    end
    -- Include interpreter call stack
    if self.interpreter and self.interpreter.call_stack then
        for _, frame in ipairs(self.interpreter.call_stack) do
            stack[#stack + 1] = frame
        end
    end
    return stack
end

function Debugger:is_terminated()
    return self.state == STATE_TERMINATED or
        (self.interpreter and self.interpreter.terminated)
end

return M
```

**Dependencies**:
- `lalin.debug_interpreter`
- `pvm` (for `pvm.classof`)

**Pattern memo**: All breakpoints are keyed by label name only (not by full `BackBlockId`), since labels are the user-facing concept. Region filtering is optional.

**Edge cases**:
- Multiple blocks with the same label name in different regions: the breakpoint applies to ALL blocks with that label. To restrict to a specific region, use the `region_id` filter.
- No interpreter: `get_variables()` returns `{}` if no interpreter is initialized.

---

### Phase 2: Breakpoints

#### 2.1 NEW: `lua/lalin/dap_breakpoint_resolver.lua` — Source line → block label mapping

**Purpose**: Map DAP source-line breakpoints to Lalin block labels using the anchor index. Bridges the PC-level debugger model to the block-level debugger model.

**Contents sketch** (~80 lines):

```lua
-- lalin/dap_breakpoint_resolver.lua
-- Maps DAP source-line breakpoints to Lalin block label names.
-- Uses the anchor index (AnchorContinuationName anchors) to find
-- which block label corresponds to a given source line.

local pvm = require("lalin.pvm")
local PositionIndex = require("lalin.source_position_index")
local AnchorIndex = require("lalin.source_anchor_index")

local M = {}

function M.Define(T)
    local S = T.LalinSource

    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)

    --- Resolve a source line to block label anchors.
    -- For DAP setBreakpoints: given a document URI and line number,
    -- find the AnchorContinuationName anchors at that line.
    --
    -- @param doc_uri  string — document URI
    -- @param line  number — 0-based line number (LSP convention)
    -- @param source_text  string — document source text
    -- @param anchor_set  AnchorSet — anchors from the analysis context
    -- @return array of {block_label, source_range}
    function M.resolve_line(doc_uri, line, source_text, anchor_set)
        local document = S.DocumentSnapshot(
            S.DocUri(doc_uri), S.DocVersion(1), S.LangLalin, source_text)
        local pos_index = P.build_index(document)
        local anchor_index = AI.build_index(anchor_set)

        -- Convert line number to byte offset range (one-line span)
        local line_result = P.byte_offset_at_byte_col(pos_index, line, 0)
        if pvm.classof(line_result) ~= S.SourceOffsetHit then
            return {}
        end
        local start_offset = line_result.offset
        local line_span = pos_index.lines[line + 1]
        if not line_span then return {} end
        local end_offset = line_span.next_offset

        -- Query anchors at this line's byte range
        local line_range = S.SourceRange(
            S.DocUri(doc_uri), start_offset, end_offset,
            S.SourcePos(line, 0, 0),
            S.SourcePos(line, math.max(1, end_offset - start_offset), 0))
        local lookup = AI.lookup_by_range(anchor_index, line_range)

        -- Filter for AnchorContinuationName anchors
        local results = {}
        for _, anchor in ipairs(lookup.anchors) do
            if anchor.kind == S.AnchorContinuationName then
                results[#results + 1] = {
                    block_label = anchor.label,
                    source_range = anchor.range,
                }
            end
        end
        return results
    end

    --- Reverse map: given a block label, find its source range.
    -- Used by DAP stackTrace to highlight the current block.
    --
    -- @param block_label  string
    -- @param anchor_set  AnchorSet
    -- @return SourceRange or nil
    function M.resolve_block_label(block_label, anchor_set)
        local anchor_index = AI.build_index(anchor_set)
        for _, anchor in ipairs(anchor_index.anchors) do
            if anchor.kind == S.AnchorContinuationName
               and anchor.label == block_label then
                return anchor.range
            end
        end
        return nil
    end

    return M
end

return M
```

**Dependencies**:
- `lalin.source_position_index`
- `lalin.source_anchor_index`
- Same `Define(T)` pattern as other LSP modules

**Edge cases**:
- Line with no block/entry keyword: returns empty array (DAP will show "unverified" breakpoint)
- Multiple blocks on same line (rare): returns all matching anchors
- No anchor set available: returns empty (debugger can't resolve)
- The anchor set is built during parsing in `frontend_pipeline.lua` as `analysis_ctx.anchors`. The DAP server must have access to this.

---

#### 2.2 Integration: Modify `debugger_core.lua` — Build `source_lines_to_block` map

After the `init()` function, build the source-line-to-block map using `dap_breakpoint_resolver`. This requires passing the anchor set and source text at debugger creation time.

**In `Debugger:init()`** (new code after interpreter creation, around line 55-70):
```lua
    -- Build source-lines-to-block mapping
    if self.opts.anchor_set and self.opts.source_uri and self.opts.source_text then
        local resolver = require("lalin.dap_breakpoint_resolver")
        local S = _G.T and _G.T.LalinSource  -- schema context from caller
        local lines = self.opts.source_text:split("\n")
        for line_no = 0, #lines - 1 do
            local blocks = resolver.resolve_line(
                self.opts.source_uri, line_no,
                self.opts.source_text, self.opts.anchor_set)
            if #blocks > 0 then
                self.source_lines_to_block[line_no] = blocks
            end
        end
    end
```

---

### Phase 3: Memory and Calls

#### 3.1 `lua/lalin/debug_interpreter.lua` — Add memory simulation handlers

**Purpose**: Add `CmdLoad`, `CmdStore`, `CmdMemcpy`, `CmdMemset`, `CmdStackAddr`, `CmdDataAddr`, data region management.

**New functions** (inserted after `_handle_switch_to_block`):

```lua
--- Initialize the flat address space.
-- Called in init(). Allocates an FFI byte array.
function Interpreter:_init_memory()
    if not self.memory then
        local ffi = require("ffi")
        self.memory = ffi.new("uint8_t[?]", self.memory_size)
        self.memory_ptr = ffi.cast("uint8_t*", self.memory)
    end
end

--- Allocate a block in the address space for data.
-- @param size  number — bytes
-- @param align  number — alignment
-- @return offset (simulated address)
function Interpreter:_alloc_data(size, align)
    local offset = self.next_data_offset
    -- Simple alignment: round up to next multiple of align
    if align > 1 then
        offset = offset + (align - offset % align) % align
    end
    self.next_data_offset = offset + size
    return offset
end

--- Allocate a stack slot.
-- @param size  number
-- @param align  number
-- @return offset (simulated address)
function Interpreter:_alloc_stack(size, align)
    local offset = self.next_stack_offset
    if align > 1 then
        offset = offset + (align - offset % align) % align
    end
    self.next_stack_offset = offset + size
    return offset
end

-- Handle CmdCreateStackSlot
function Interpreter:_handle_create_stack_slot(cmd)
    local slot_id = cmd.slot.text
    local offset = self:_alloc_stack(cmd.size, cmd.align)
    self.stack_slots[slot_id] = { offset = offset, size = cmd.size }
end

-- Handle CmdStackAddr
function Interpreter:_handle_stack_addr(cmd)
    local slot = self.stack_slots[cmd.slot.text]
    if slot then
        self.registers[cmd.dst.text] = slot.offset
    else
        self.registers[cmd.dst.text] = 0
    end
end

-- Handle CmdLoadInfo
function Interpreter:_handle_load_info(cmd)
    local addr = self.registers[cmd.addr.base.value.text]
        + (self.registers[cmd.addr.byte_offset.text] or 0)
    local scalar = cmd.shape.scalar  -- BackI32, BackI64, etc.
    if addr >= 1 and addr + self:_scalar_size(scalar) <= self.memory_size then
        local val = self:_read_memory(addr, scalar)
        self.registers[cmd.dst.text] = val
    else
        self.registers[cmd.dst.text] = 0
    end
end

-- Handle CmdStoreInfo
function Interpreter:_handle_store_info(cmd)
    local addr = self.registers[cmd.addr.base.value.text]
        + (self.registers[cmd.addr.byte_offset.text] or 0)
    local scalar = cmd.shape.scalar
    local val = self.registers[cmd.value.text]
    if addr >= 1 and addr + self:_scalar_size(scalar) <= self.memory_size then
        self:_write_memory(addr, scalar, val)
    end
end

-- Scalar size helper
function Interpreter:_scalar_size(scalar)
    local sizes = {
        BackBool = 1, BackI8 = 1, BackU8 = 1,
        BackI16 = 2, BackU16 = 2,
        BackI32 = 4, BackU32 = 4, BackF32 = 4,
        BackI64 = 8, BackU64 = 8, BackF64 = 8,
        BackIndex = 8, BackPtr = 8,
    }
    return sizes[scalar.kind] or 4
end

-- Read typed value from flat memory
function Interpreter:_read_memory(addr, scalar)
    local ffi = require("ffi")
    local ptr = self.memory_ptr + addr
    if scalar == BackBool or scalar == BackU8 then
        return ptr[0]
    elseif scalar == BackI8 then
        return ffi.cast("int8_t*", ptr)[0]
    elseif scalar == BackI16 then
        return ffi.cast("int16_t*", ptr)[0]
    elseif scalar == BackU16 then
        return ffi.cast("uint16_t*", ptr)[0]
    elseif scalar == BackI32 then
        return ffi.cast("int32_t*", ptr)[0]
    elseif scalar == BackU32 then
        return ffi.cast("uint32_t*", ptr)[0]
    elseif scalar == BackI64 or scalar == BackIndex then
        return tonumber(ffi.cast("int64_t*", ptr)[0])
    elseif scalar == BackU64 then
        return tonumber(ffi.cast("uint64_t*", ptr)[0])
    elseif scalar == BackF32 then
        return ffi.cast("float*", ptr)[0]
    elseif scalar == BackF64 then
        return ffi.cast("double*", ptr)[0]
    end
    return 0
end

-- Write typed value to flat memory
function Interpreter:_write_memory(addr, scalar, val)
    local ffi = require("ffi")
    local ptr = self.memory_ptr + addr
    if scalar == BackBool or scalar == BackU8 then
        ptr[0] = val and val ~= 0 and 1 or 0
    elseif scalar == BackI8 then
        ffi.cast("int8_t*", ptr)[0] = val
    elseif scalar == BackI16 then
        ffi.cast("int16_t*", ptr)[0] = val
    elseif scalar == BackU16 then
        ffi.cast("uint16_t*", ptr)[0] = val
    elseif scalar == BackI32 or scalar == BackU32 then
        ffi.cast("int32_t*", ptr)[0] = val
    elseif scalar == BackI64 or scalar == BackIndex then
        ffi.cast("int64_t*", ptr)[0] = val
    elseif scalar == BackU64 then
        ffi.cast("uint64_t*", ptr)[0] = val
    elseif scalar == BackF32 then
        ffi.cast("float*", ptr)[0] = val
    elseif scalar == BackF64 then
        ffi.cast("double*", ptr)[0] = val
    end
end
```

**For `CmdCall` handling**:
```lua
-- Handle CmdCall (direct function call)
function Interpreter:_handle_call(cmd)
    local target = cmd.target
    local cls = pvm.classof(target)

    if cls == BackCallExtern then
        -- Call extern function
        local func_name = target.func.text
        local fn = self.extrn[func_name]
        if fn then
            local args = {}
            for i = 1, #cmd.args do
                args[i] = self.registers[cmd.args[i].text]
            end
            local ok, result = pcall(fn, unpack(args))
            if ok and cmd.result and cmd.result.kind == "BackCallValue" then
                self.registers[cmd.result.dst.text] = result or 0
            end
        end
    elseif cls == BackCallDirect then
        -- Call direct Lalin function
        local func_id = target.func.text
        local func_body = self.functions[func_id]
        if func_body then
            -- Push call stack
            table.insert(self.call_stack, {
                cursor = self.cursor,
                registers = self:_copy_registers(),
                current_block = self.current_block,
            })
            -- Jump to function body
            local func_entry = self.func_map[func_id]
            if func_entry then
                self.cursor = func_entry.start_idx
                -- Don't advance cursor (will advance in step())
                self.cursor = self.cursor - 1
            end
        end
    end
end

function Interpreter:_copy_registers()
    local copy = {}
    for k, v in pairs(self.registers) do
        copy[k] = v
    end
    return copy
end

-- Handle CmdReturnValue / CmdReturnVoid
function Interpreter:_handle_return(cmd)
    local cls = pvm.classof(cmd)
    if cls == BackCmdReturnValue then
        self.return_value = self.registers[cmd.value.text]
    end
    -- Pop call stack
    if #self.call_stack > 0 then
        local frame = table.remove(self.call_stack)
        self.registers = frame.registers
        self.cursor = frame.cursor  -- command after CmdCall
        self.current_block = frame.current_block
        -- Store return value in call result register
    else
        self.terminated = true
    end
end
```

---

#### 3.2 `lua/lalin/debug_interpreter.lua` — Add remaining command handlers

Register handlers for all arithmetic, comparison, cast, and memory commands.

**Handler registration table** (new code at module top, after `Interpreter._handlers = {}`):

```lua
-- Map ASDL command class names to handler method names
Interpreter._handler_map = {
    CmdConst = "_handle_const",
    CmdIntBinary = "_handle_int_binary",
    CmdFloatBinary = "_handle_float_binary",
    CmdUnary = "_handle_unary",
    CmdCompare = "_handle_compare",
    CmdSelect = "_handle_select",
    CmdCast = "_handle_cast",
    CmdBitBinary = "_handle_bit_binary",
    CmdShift = "_handle_shift",
    CmdJump = "_handle_jump",
    CmdBrIf = "_handle_br_if",
    CmdSwitchInt = "_handle_switch_int",
    CmdSwitchToBlock = "_handle_switch_to_block",
    CmdCreateBlock = "_handle_noop",      -- no runtime effect
    CmdSealBlock = "_handle_noop",        -- no runtime effect
    CmdAppendBlockParam = "_handle_noop",  -- handled during init
    CmdReturnVoid = "_handle_return_void",
    CmdReturnValue = "_handle_return_value",
    CmdTrap = "_handle_trap",
    CmdBindEntryParams = "_handle_bind_entry_params",
    CmdCall = "_handle_call",
    CmdCreateStackSlot = "_handle_create_stack_slot",
    CmdStackAddr = "_handle_stack_addr",
    CmdLoadInfo = "_handle_load_info",
    CmdStoreInfo = "_handle_store_info",
    CmdDataAddr = "_handle_data_addr",
    CmdDeclareData = "_handle_declare_data",
    CmdDataInit = "_handle_data_init",
    CmdDataInitZero = "_handle_data_init_zero",
    CmdMemcpy = "_handle_memcpy",
    CmdMemset = "_handle_memset",
    CmdMemcmp = "_handle_memcmp",
    CmdPtrOffset = "_handle_ptr_offset",
    CmdFuncAddr = "_handle_func_addr",
    CmdExternAddr = "_handle_extern_addr",
    CmdCreateSig = "_handle_noop",
    CmdDeclareFunc = "_handle_noop",
    CmdBeginFunc = "_handle_noop",
    CmdFinishFunc = "_handle_noop",
    CmdFinalizeModule = "_handle_noop",
    CmdIntrinsic = "_handle_intrinsic",
    CmdAtomicLoad = "_handle_load_info",   -- same as regular load for sim
    CmdAtomicStore = "_handle_store_info",  -- same as regular store for sim
    CmdFma = "_handle_fma",
}
```

**Key arithmetic handlers** pattern:

```lua
function Interpreter:_handle_int_binary(cmd)
    local lv = self.registers[cmd.lhs.text] or 0
    local rv = self.registers[cmd.rhs.text] or 0
    local val
    if cmd.op == Back.BackIntAdd then val = lv + rv
    elseif cmd.op == Back.BackIntSub then val = lv - rv
    elseif cmd.op == Back.BackIntMul then val = lv * rv
    elseif cmd.op == Back.BackIntSDiv then val = math.floor(lv / rv)
    elseif cmd.op == Back.BackIntSRem then val = lv % rv
    end
    self.registers[cmd.dst.text] = val
end
```

**Danger zones**:
- Integer overflow: Lua numbers are doubles, so overflow behavior differs from i32/i64 semantics. For debugging purposes, this is acceptable.
- Division by zero: Lua errors; wrap in pcall and emit trap event.
- Float to int conversion: use `math.floor` or `ffi.cast` depending on op.

---

### Phase 4: DAP Server

#### 4.1 NEW: `lua/lalin/dap_server.lua` — DAP server

**Purpose**: Implement the Debug Adapter Protocol in the same STDIO loop as the LSP, translating DAP requests to debugger core commands.

**Contents sketch** (~300 lines):

```lua
-- lalin/dap_server.lua
-- Debug Adapter Protocol server for Lalin.
-- Shares the STDIO loop with the LSP server.
-- Translates DAP requests → debugger core commands.

local pvm = require("lalin.pvm")
local JsonDecode = require("lalin.rpc_json_decode")
local Debugger = require("lalin.debugger_core")
-- Lazy-required: Resolver = require("lalin.dap_breakpoint_resolver")

local M = {}

local DapServer = {}
DapServer.__index = DapServer

--- DAP request -> method handler map
local DAP_METHODS = {
    initialize = true, setBreakpoints = true, setFunctionBreakpoints = true,
    continue = true, next = true, stepIn = true, stepOut = true,
    pause = true, stackTrace = true, scopes = true, variables = true,
    disconnect = true, terminate = true, launch = true, attach = true,
    configurationDone = true, threads = true, setExceptionBreakpoints = true,
    goto = true, gotoTargets = true, source = true,
}

function M.is_dap_method(method)
    return DAP_METHODS[method] == true or
        (type(method) == "string" and method:match("^dap/"))
end

--- Create a new DAP server instance.
-- @param opts  table:
--   source_uri: string — document URI
--   source_text: string — document source
--   anchor_set: AnchorSet — for breakpoint resolution
--   extrn: {[name] = function} — extern functions
--   functions: {[func_id] = BackCmd[]} — Lalin function bodies
--   cmds: BackCmd[] — full module command stream
function M.new(opts)
    opts = opts or {}
    local self = setmetatable({
        debugger = nil,
        opts = opts,
        seq = 0,
        initialized = false,
        running = false,
        breakpoint_id_counter = 0,
        breakpoints = {},   -- {[dap_bp_id] = {verified, block_label, line, condition}}
        output = nil,       -- output stream (set during handle)
    }, DapServer)

    return self
end

--- Initialize the debugger with program commands.
function DapServer:init_with_program(cmds)
    self.debugger = Debugger.new(cmds, {
        source_uri = self.opts.source_uri,
        source_text = self.opts.source_text,
        anchor_set = self.opts.anchor_set,
        extrn = self.opts.extrn or {},
        functions = self.opts.functions or {},
    })
    self.debugger:init()
end

--- Handle a single DAP request.
-- @param incoming  decoded JSON message {command, arguments, seq, type}
-- @param output    io output stream for writing response
function DapServer:handle(incoming, output)
    self.output = output
    local method = incoming.command or incoming.method
    local args = incoming.arguments or {}
    local request_seq = incoming.seq

    if method == "initialize" then
        self:_handle_initialize(request_seq, args)
    elseif method == "launch" or method == "attach" then
        self:_handle_launch(request_seq, args)
    elseif method == "setBreakpoints" then
        self:_handle_set_breakpoints(request_seq, args)
    elseif method == "setFunctionBreakpoints" then
        self:_handle_set_function_breakpoints(request_seq, args)
    elseif method == "continue" then
        self:_handle_continue(request_seq, args)
    elseif method == "next" then
        self:_handle_next(request_seq, args)
    elseif method == "stepIn" then
        self:_handle_step_in(request_seq, args)
    elseif method == "stepOut" then
        self:_handle_step_out(request_seq, args)
    elseif method == "pause" then
        self:_handle_pause(request_seq, args)
    elseif method == "stackTrace" then
        self:_handle_stack_trace(request_seq, args)
    elseif method == "scopes" then
        self:_handle_scopes(request_seq, args)
    elseif method == "variables" then
        self:_handle_variables(request_seq, args)
    elseif method == "disconnect" or method == "terminate" then
        self:_handle_disconnect(request_seq, args)
    elseif method == "configurationDone" then
        self:_send_response(request_seq, {})
    elseif method == "threads" then
        self:_send_response(request_seq, { threads = [{ id = 1, name = "main" }] })
    elseif method == "setExceptionBreakpoints" then
        self:_send_response(request_seq, {})
    else
        self:_send_response(request_seq, { success = false, message = "unsupported" })
    end
end

-- Helper: send DAP response
function DapServer:_send_response(request_seq, body)
    self.seq = self.seq + 1
    local response = {
        type = "response",
        seq = self.seq,
        command = "request",
        request_seq = request_seq,
        success = body.success ~= false,
        body = body,
    }
    self:_write_json(response)
end

-- Helper: send DAP event
function DapServer:_send_event(event_type, body)
    self.seq = self.seq + 1
    local event = {
        type = "event",
        seq = self.seq,
        event = event_type,
        body = body or {},
    }
    self:_write_json(event)
end

-- Helper: encode and write JSON message
function DapServer:_write_json(obj)
    if not self.output then return end
    local json = require("lalin.rpc_json_encode")
    local body = json.encode(obj)
    self.output:write("Content-Length: ", tostring(#body), "\r\n\r\n", body)
    self.output:flush()
end

-- DAP initialize handler
function DapServer:_handle_initialize(request_seq, args)
    self.initialized = true
    self:_send_response(request_seq, {
        supportsConfigurationDoneRequest = true,
        supportsSetVariable = false,
        supportsConditionalBreakpoints = true,
        supportsFunctionBreakpoints = true,
        supportsStepInTargetsRequest = false,
        supportsGotoTargetsRequest = false,
        supportsCompletionsRequest = false,
        supportTerminateDebuggee = true,
    })
end

-- DAP launch handler: compile and start debugger
function DapServer:_handle_launch(request_seq, args)
    if not self.opts.cmds then
        self:_send_response(request_seq, {
            success = false,
            message = "no program commands provided"
        })
        return
    end
    self:init_with_program(self.opts.cmds)
    self.running = true

    -- Start execution (pauses at first block boundary)
    self.debugger:start()

    -- Register pause event handler
    self.debugger:on("paused", function(data)
        self:_send_event("stopped", {
            reason = "step",
            threadId = 1,
        })
    end)

    self.debugger:on("breakpoint", function(data)
        self:_send_event("stopped", {
            reason = "breakpoint",
            threadId = 1,
        })
    end)

    self:_send_response(request_seq, {})
    -- Send initial stopped event (paused at entry)
    self:_send_event("stopped", {
        reason = "entry",
        threadId = 1,
    })
end

-- DAP setBreakpoints handler
function DapServer:_handle_set_breakpoints(request_seq, args)
    local source = args.source
    local lines = args.lines or {}
    local breakpoints = args.breakpoints or {}

    -- Resolve each line to a block label
    local resolved = {}
    local resolver_module = require("lalin.dap_breakpoint_resolver")
    -- (assumes source URI and anchor set available)
    local results = resolver_module.resolve_line(
        self.opts.source_uri, lines[1] - 1,  -- DAP lines are 1-based
        self.opts.source_text, self.opts.anchor_set)

    if #results > 0 then
        for _, r in ipairs(results) do
            local bp_id = self.breakpoint_id_counter + 1
            self.breakpoint_id_counter = bp_id
            self.breakpoints[bp_id] = {
                verified = true,
                block_label = r.block_label,
                line = lines[1],
                condition = breakpoints[1] and breakpoints[1].condition,
            }
            -- Register with debugger
            local condition_fn = nil
            if breakpoints[1] and breakpoints[1].condition then
                local cond_text = breakpoints[1].condition
                condition_fn = function(vars)
                    -- Simple eval: replace $var_name with vars[var_name]
                    local expr = cond_text
                    for k, v in pairs(vars) do
                        expr = expr:gsub("%$" .. k, tostring(v))
                    end
                    local ok, result = pcall(load("return " .. expr))
                    return ok and result
                end
            end
            if self.debugger then
                self.debugger:set_breakpoint(r.block_label, {
                    condition_fn = condition_fn,
                })
            end
            resolved[#resolved + 1] = {
                id = bp_id,
                verified = true,
                line = lines[1],
            }
        end
    else
        -- No block at this line: unverified breakpoint
        for _, line in ipairs(lines) do
            resolved[#resolved + 1] = {
                id = self.breakpoint_id_counter + 1,
                verified = false,
                line = line,
            }
            self.breakpoint_id_counter = self.breakpoint_id_counter + 1
        end
    end

    self:_send_response(request_seq, { breakpoints = resolved })
end

-- DAP continue handler
function DapServer:_handle_continue(request_seq, args)
    if self.debugger and not self.debugger:is_terminated() then
        local result = self.debugger:continue()
        if result.type == "terminated" then
            self:_send_response(request_seq, { allThreadsContinued = true })
            self:_send_event("terminated", {})
            self:_send_event("exited", { exitCode = 0 })
        else
            self:_send_response(request_seq, { allThreadsContinued = true })
        end
    else
        self:_send_response(request_seq, {})
    end
end

-- DAP next handler (step over block)
function DapServer:_handle_next(request_seq, args)
    if self.debugger and self.debugger.state == "paused" then
        local block = self.debugger:step_block()
        self:_send_response(request_seq, {})
    else
        self:_send_response(request_seq, { success = false, message = "not paused" })
    end
end

-- DAP stepIn handler (same as next for block-level stepping)
function DapServer:_handle_step_in(request_seq, args)
    self:_handle_next(request_seq, args)
end

-- DAP stepOut handler (complete current region)
function DapServer:_handle_step_out(request_seq, args)
    -- Continue until a region exit (CmdReturn or CmdJump to exit block)
    -- For now, same as continue; future: track region nesting
    self:_handle_continue(request_seq, args)
end

-- DAP pause handler
function DapServer:_handle_pause(request_seq, args)
    if self.debugger then
        self.debugger:pause()
    end
    self:_send_response(request_seq, {})
end

-- DAP stackTrace handler
function DapServer:_handle_stack_trace(request_seq, args)
    if not self.debugger then
        self:_send_response(request_seq, { stackFrames = [], totalFrames = 0 })
        return
    end
    local stack = self.debugger:stack_trace()
    local frames = {}
    for i, frame in ipairs(stack) do
        local resolver = require("lalin.dap_breakpoint_resolver")
        local range = resolver.resolve_block_label(
            frame.block, self.opts.anchor_set)

        local line = 0
        local column = 0
        if range and range.start then
            line = range.start.line + 1  -- 1-based for DAP
            column = range.start.utf16_col + 1
        end

        frames[#frames + 1] = {
            id = i,
            name = frame.block or "?",
            source = { path = self.opts.source_uri },
            line = line,
            column = column,
        }
    end
    self:_send_response(request_seq, {
        stackFrames = frames,
        totalFrames = #frames,
    })
end

-- DAP scopes handler
function DapServer:_handle_scopes(request_seq, args)
    self:_send_response(request_seq, {
        scopes = {{
            name = "Block Parameters",
            variablesReference = 1,
            namedVariables = self.debugger and
                #self.debugger:get_variables() or 0,
        }}
    })
end

-- DAP variables handler
function DapServer:_handle_variables(request_seq, args)
    if not self.debugger then
        self:_send_response(request_seq, { variables = {} })
        return
    end
    local vars = self.debugger:get_variables()
    local result = {}
    -- Filter to block param names only
    for name, value in pairs(vars) do
        result[#result + 1] = {
            name = name,
            value = tostring(value),
            type = type(value) == "number" and "i32" or type(value),
        }
    end
    self:_send_response(request_seq, { variables = result })
end

-- DAP disconnect handler
function DapServer:_handle_disconnect(request_seq, args)
    self.running = false
    self.debugger = nil
    self:_send_response(request_seq, {})
end

-- DAP setFunctionBreakpoints handler
function DapServer:_handle_set_function_breakpoints(request_seq, args)
    -- Map function names to entry block labels
    -- "function_name" → "func:function_name:entry" or similar
    local resolved = {}
    for _, bp in ipairs(args.breakpoints or {}) do
        local block_label = "func:" .. bp.name
        if self.debugger then
            self.debugger:set_breakpoint(block_label)
        end
        resolved[#resolved + 1] = {
            id = self.breakpoint_id_counter + 1,
            verified = true,
            name = bp.name,
        }
        self.breakpoint_id_counter = self.breakpoint_id_counter + 1
    end
    self:_send_response(request_seq, { breakpoints = resolved })
end

return M
```

**Dependencies**:
- `lalin.debugger_core`
- `lalin.dap_breakpoint_resolver` (lazy)
- `lalin.rpc_json_decode` / `lalin.rpc_json_encode`
- `pvm`

**Pattern memo**: All DAP responses use `self:_send_response(request_seq, body)`. All debugger events use `self:_send_event(event_type, body)`. The DAP server maintains its own request sequence counter.

**Edge cases**:
- DAP uses 1-based line numbers; Lalin anchors use 0-based (LSP convention). Convert with `line - 1`.
- DAP `setBreakpoints` sends `lines` array; each line needs separate resolution.
- No debugger (before launch): all handlers return empty/success.
- Multiple breakpoints on same line: each gets a separate DAP breakpoint ID.
- Condition evaluation errors: wrap in pcall, treat as "no match".

---

#### 4.2 `lua/lalin/rpc_stdio_loop.lua` — Add DAP method dispatching

**Goal**: Route DAP requests to the DAP server, LSP requests to the existing LSP handler.

**Edit block 1**: Lines 30-58 (the `run()` function) — Add DAP dispatch.

**Before** (lines 45-58):
```lua
    local state = opts.state or WorkspaceApply.initial_state()
    local running = true
    while running do
        local body, read_err = read_message(input)
        if not body then
            if read_err and err then err:write("lalin-lsp read error: ", read_err, "\n") end
            break
        end
        local incoming = Json.decode_message(body)
        local event = Decode.decode(incoming, state)
        local transition = WorkspaceApply.apply_event(state, event)
        state = transition.after
        local commands = Out.commands(transition)
        for i = 1, #commands do
            local cmd = commands[i]
            local cls = pvm.classof(cmd)
            if cls == R.SendMessage then
                write_message(output, Encode.encode_outgoing(cmd.outgoing))
            elseif cls == R.LogMessage then
                if err then err:write(cmd.level, ": ", cmd.message, "\n") end
            elseif cmd == R.StopServer or cls == pvm.classof(R.StopServer) then
                running = false
            end
        end
    end
```

**After** (lines 45-66):
```lua
    local Dap = require("lalin.dap_server")
    local dap_handler = opts.dap_handler

    local state = opts.state or WorkspaceApply.initial_state()
    local running = true
    while running do
        local body, read_err = read_message(input)
        if not body then
            if read_err and err then err:write("lalin-lsp read error: ", read_err, "\n") end
            break
        end
        local incoming = Json.decode_message(body)
        local method = incoming.method or incoming.command or ""

        -- Check if this is a DAP message
        if dap_handler and Dap.is_dap_method(method) then
            dap_handler:handle(incoming, output)
            -- DAP doesn't affect LSP state; just loop
        else
            -- Existing LSP dispatch
            local event = Decode.decode(incoming, state)
            local transition = WorkspaceApply.apply_event(state, event)
            state = transition.after
            local commands = Out.commands(transition)
            for i = 1, #commands do
                local cmd = commands[i]
                local cls = pvm.classof(cmd)
                if cls == R.SendMessage then
                    write_message(output, Encode.encode_outgoing(cmd.outgoing))
                elseif cls == R.LogMessage then
                    if err then err:write(cmd.level, ": ", cmd.message, "\n") end
                elseif cmd == R.StopServer or cls == pvm.classof(R.StopServer) then
                    running = false
                end
            end
        end
    end
```

**Edit block 2**: Lines 1-5 (requires at top of file) — Add DAP dependency.

**Before** (lines 1-5):
```lua
local pvm = require("lalin.pvm")
local Asdl = require("lalin.asdl")
local JsonDecode = require("lalin.rpc_json_decode")
local LspDecode = require("lalin.rpc_lsp_decode")
local LspEncode = require("lalin.rpc_lsp_encode")
```

**After** (lines 1-5):
```lua
local pvm = require("lalin.pvm")
local Asdl = require("lalin.asdl")
local JsonDecode = require("lalin.rpc_json_decode")
local LspDecode = require("lalin.rpc_lsp_decode")
local LspEncode = require("lalin.rpc_lsp_encode")
local Dap = require("lalin.dap_server")
```

**Quirks**: The `dap_handler` is passed through `opts.dap_handler`. The LSP server's `lsp.lua` entry point must be updated to create and pass the DAP handler when applicable. The `Dap.is_dap_method()` and `Dap.new()` must be available before the loop starts.

**Also add to `run()` function signature** (line 30): Document that `opts.dap_handler` can be provided:
```lua
-- @param opts.dap_handler  DapServer instance (optional) — handles DAP messages
```

---

#### 4.3 NEW: `lua/lalin/dap_variables.lua` — Variable formatting

**Purpose**: Format block parameter values with type information from binding facts. Provides the DAP `variables` response body.

**Contents sketch** (~70 lines):

```lua
-- lalin/dap_variables.lua
-- Format Lalin variables for DAP display.
-- Maps register values to typed, named variables using binding facts.

local M = {}

--- Format variables from the interpreter for DAP.
-- @param vars  table {name → raw_value} from debugger
-- @param bindings  BindingFact[] from editor_binding_facts (optional)
-- @return DAP variables array: [{name, value, type, variablesReference}]
function M.format_variables(vars, bindings)
    local result = {}
    for name, raw_value in pairs(vars) do
        -- Skip internal variables (non-param names)
        if not name:match("^v%d+$") and not name:match("^addr") then
            local ty = M._infer_type(name, raw_value, bindings)
            result[#result + 1] = {
                name = name,
                value = M._format_value(raw_value, ty),
                type = ty,
                variablesReference = 0,
            }
        end
    end
    -- Sort by name for consistent display
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--- Infer type of a variable from binding facts.
-- @param name  string — variable name
-- @param value  raw value
-- @param bindings  BindingFact[] or nil
-- @return type string like "i32", "bool", "f64", "i64"
function M._infer_type(name, value, bindings)
    -- Try to resolve from binding facts
    if bindings then
        for _, fact in ipairs(bindings) do
            if fact.name == name and fact.ty then
                return tostring(fact.ty)
            end
        end
    end
    -- Fallback: infer from value type
    if type(value) == "boolean" then return "bool" end
    if type(value) == "number" then
        if value == math.floor(value) and math.abs(value) < 2^31 then
            return "i32"
        end
        return "i64"
    end
    if type(value) == "string" then
        return "ptr"  -- addresses are strings
    end
    return "unknown"
end

--- Format a raw value for display.
function M._format_value(raw, ty)
    if type(raw) == "boolean" then
        return raw and "true" or "false"
    end
    if type(raw) == "number" then
        if raw == math.floor(raw) then
            return tostring(math.floor(raw))
        end
        return string.format("%g", raw)
    end
    if type(raw) == "string" then
        -- Might be a synthetic address
        if raw:match("^%d+$") then
            return "0x" .. tonumber(raw):fmt("%x")
        end
        return raw
    end
    return tostring(raw)
end

return M
```

---

### Phase 5: LSP Entry Point Integration

#### 5.1 `lsp.lua` — Create DAP handler and pass to STDIO loop

**Edit the main LSP entry point** to optionally create a DAP server when `—debug` flag is passed or when DAP methods are expected.

**New code at the end of `lsp.lua`** (around the `run()` call):

```lua
-- DAP server support
local DapServer = require("lalin.dap_server")
local dap_handler = nil

-- Create DAP handler if debug mode or if DAP initialization is expected
-- (e.g., the editor sends both LSP and DAP messages on the same channel)
if opts.debug then
    dap_handler = DapServer.new({
        source_uri = opts.source_uri or "file.mlua",
        source_text = opts.source_text or "",
        anchor_set = opts.anchor_set,
        cmds = opts.cmds,
        extrn = opts.extrn,
        functions = opts.functions,
    })
end

-- Pass dap_handler to the run loop
Program.run({
    context = T,
    state = state,
    input = io.stdin,
    output = io.stdout,
    err = io.stderr,
    dap_handler = dap_handler,
})
```

**Note**: The exact integration point depends on `lsp.lua`'s current structure. The key change is passing `dap_handler` through `opts` to `run()`.

---

### Order of Operations

1. **First**: Modify `tree_to_back.lua` (1.1) to add `get_provenance` to the `base` table. This is a pure addition with no breaking changes.

2. **Second**: Modify `tree_control_to_back.lua` (1.2) to record provenance in `declare_blocks` and after `CmdSwitchToBlock`. This depends on step 1's `base.get_provenance`.

3. **Third**: Create `debug_interpreter.lua` (1.3) skeleton with handler dispatch, basic arithmetic, control flow, and register file. Don't implement memory or calls yet.

4. **Fourth**: Create `debugger_core.lua` (1.4) with state machine and stepping modes. Depends on step 3.

5. **Fifth**: Create `dap_breakpoint_resolver.lua` (2.1). Depends on `source_position_index` and `source_anchor_index`.

6. **Sixth**: Extend `debugger_core.lua` (2.2) with `source_lines_to_block` map init.

7. **Seventh**: Add memory handlers to `debug_interpreter.lua` (3.1). Flat FFI buffer, load/store, stack slots.

8. **Eighth**: Add call handlers to `debug_interpreter.lua` (3.2). Extern FFI calls, direct function calls, return handling.

9. **Ninth**: Create `dap_variables.lua` (4.3).

10. **Tenth**: Create `dap_server.lua` (4.1) with full DAP protocol. Depends on steps 4, 5, 9.

11. **Eleventh**: Modify `rpc_stdio_loop.lua` (4.2) with DAP dispatch. Depends on step 10.

12. **Twelfth**: Integrate in `lsp.lua` (5.1) if applicable.

---

### Testing Strategy

**Incremental verification**:

| Step | Test |
|------|------|
| 1-2 | Rebuild and run existing tests (`luajit tests/test_back_add_i32.lua`, `luajit tests/test_parse_typecheck.lua`). No behavior change expected. |
| 3 | Write new `tests/test_debug_interpreter.lua` with a hand-crafted `BackCmd[]` (add_i32 program) and verify the interpreter produces the correct result. Follow the pattern in `tests/test_back_add_i32.lua`. **Test before any memory support**: just integer arithmetic and jump. |
| 4 | Extend test with stepping: call `interpreter:step_block()` and verify it pauses at the first block boundary. |
| 5 | Write `tests/test_debug_breakpoint_resolver.lua`: parse a small `.mlua` file, build anchors, then resolve a source line to a block label. |
| 6-8 | Write `tests/test_debug_memory.lua`: hand-craft a BackCmd[] with load/store, run in interpreter, verify values match expected. |
| 9-10 | Write `tests/test_dap_server.lua`: create DAP server, send `initialize` request, verify response. |
| 11 | Write `tests/test_dap_stdio_loop.lua`: send a DAP message through the STDIO loop, verify it's dispatched to the DAP handler. |

**Integration test flow**:
1. Parse a `.mlua` file (use existing pipeline: `frontend_pipeline.parse_and_lower`)
2. Pass the `BackCmd[]` to the interpreter
3. Set a breakpoint on a block label
4. Step through, verify pauses at correct positions
5. Inspect variables, verify correct values

**Follow existing test patterns**:
- Tests are standalone Lua scripts that set `package.path`
- They `require()` the modules they need
- They create a PVM context with `pvm.context()` and `Asdl.Define(T)`
- They use `assert()` for verification
- They print `"... ok"` at the end

---

### Pattern Memo (applies to ALL new/modified files)

1. **Naming**: New files use snake_case: `debug_interpreter.lua`, `debugger_core.lua`, `dap_server.lua`, `dap_breakpoint_resolver.lua`, `dap_variables.lua`

2. **Module structure**: Export a table `M` with functions. Use `M.Define(T)` pattern for modules that need ASDL schema context (breakpoint resolver, variables). Use `M.new()` for modules that are OOP-style (interpreter, debugger, DAP server).

3. **PVM usage**: The interpreter does NOT use PVM phases (it's a flat command loop). The breakpoint resolver uses PVM phases indirectly through PositionIndex and AnchorIndex.

4. **Error handling**: Use `pcall` around extern FFI calls and breakpoint condition evaluation. Don't let Lua errors from the simulated program crash the debugger.

5. **Command dispatch**: Use a handler TABLE keyed by ASDL class objects, not a chain of `if/elseif`. Build at `init()` time for O(1) dispatch.

6. **Register file**: Keyed by `BackValId.text` (string). Overwrite semantics (SSA means each name is assigned once per path, but different paths may assign the same name).

7. **Memory**: Flat `ffi.new("uint8_t[?]", size)` buffer. Addresses are integer offsets. All loads/stores use `ffi.cast` typed pointers.

8. **No globals**: Import schema classes via local variable at module init, e.g., `local Back = T.LalinBack` inside `Define(T)` functions. For the interpreter (which doesn't use `Define(T)`), capture the `Back` table at construction time: `self.Back = Back`.

9. **Threading**: The interpreter is single-threaded. No locks or synchronization needed.

10. **Stepping**: Block boundaries are `CmdSwitchToBlock` commands reached via `CmdJump`/`CmdBrIf`/`CmdSwitchInt`. The first `CmdSwitchToBlock` (after module `CmdFinalizeModule`) is the entry point.

## Worker Output — 2026-05-21 20:08:56

## Completed

Implemented the Lalin Debugger — a pure-Lua block-transition debugger with interpreter, breakpoints, stepping, and DAP server. The debugger operates at the block-transition level, using Lalin's explicit control flow to provide semantic breakpoints (block-label based), parameter value inspection, and block navigation — all without any Rust code changes beyond the pre-existing provenance infrastructure.

## Files Changed

### Modified (3 files):
- **`lua/lalin/tree_to_back.lua`** — Added `get_provenance` accessor to the `base` table passed to `tree_control_to_back.Define(T, base)`, enabling block-level provenance recording in the control flow lowering pass.
- **`lua/lalin/tree_control_to_back.lua`** — Added provenance recording: (a) after each `CmdCreateBlock` in `declare_blocks()`, record `"block:{label_name}"`; (b) after each `CmdSwitchToBlock` in `lower_region()`, record `"switch:{label_name}"`. This builds name-based provenance entries the debugger uses for block-to-source mapping.
- **`lua/lalin/rpc_stdio_loop.lua`** — Added DAP method dispatching: checks if incoming messages are DAP methods (via `dap_server.is_dap_method`) and routes them to the DAP handler, while all other messages continue to the existing LSP dispatch. Optional `dap_handler` passed through `opts`.
- **`lsp.lua`** — Added `--debug` flag support: when launched with `--debug`, creates a DAP server instance and passes it to the run loop for shared STDIO LSP+DAP operation.

### New files (6 files):
- **`lua/lalin/debug_interpreter.lua`** (~1050 lines) — The heart of the debugger. Pure-Lua `BackCmd[]` interpreter with:
  - Handler dispatch table for O(1) command routing (all 50+ BackCmd variants)
  - Register file keyed by `BackValId.text`
  - Block params map built from `CmdAppendBlockParam` scanning
  - Pending jump target model (`CmdJump`/`CmdBrIf`/`CmdSwitchInt` → `CmdSwitchToBlock` resolution with block skipping)
  - Control flow: `CmdJump`, `CmdBrIf`, `CmdSwitchInt` with proper target block selection
  - Arithmetic: `CmdConst`, `CmdIntBinary` (add/sub/mul/sdiv/srem/udiv/urem), `CmdFloatBinary`, `CmdBitBinary`, `CmdShift`, `CmdCompare`, `CmdCast`, `CmdSelect`, `CmdUnary`
  - Memory: flat `ffi.new("uint8_t[?]")` buffer, `CmdLoadInfo`/`CmdStoreInfo` for all scalar types (i8/i16/i32/i64/u8/u16/u32/u64/f32/f64/bool/index/ptr), `CmdMemcpy`/`CmdMemset`/`CmdMemcmp` via FFI
  - Stack: `CmdCreateStackSlot`, `CmdStackAddr`, `CmdDeclareData`, `CmdDataAddr`, `CmdDataInit`
  - Calls: extern FFI calls via `pcall`, direct Lalin function calls with call stack
  - Stepping protocol: `step_block()`, `continue_until(breakpoints_fn)`, `pause()`
  - Block boundary maps, function body maps built during init

- **`lua/lalin/debugger_core.lua`** (~160 lines) — Debugger state machine:
  - States: idle → paused → running → paused/terminated
  - Breakpoint table keyed by block label with condition_fn, hit_count, temporary, region_id
  - Stepping: `step_block()`, `continue()`, `pause()`, `start()`
  - Variable inspection: `get_variables()` filters register file to block param names
  - Stack trace: breadcrumb trail of block transitions
  - Event handlers for DAP integration (breakpoint, trap events)
  - Block label and region ID parsing from `"ctl:{nonce}:{region}:{label}"` format
  - Source-line-to-block mapping built from anchor set during init

- **`lua/lalin/dap_breakpoint_resolver.lua`** (~100 lines) — Maps DAP source-line breakpoints to Lalin block labels using the anchor index. Uses `PositionIndex` and `AnchorIndex` from the existing LSP infrastructure. Provides `resolve_line(doc_uri, line, source_text, anchor_set)` and `resolve_block_label(block_label, anchor_set)`.

- **`lua/lalin/dap_server.lua`** (~450 lines) — Full DAP protocol server:
  - Handles: initialize, launch, setBreakpoints, setFunctionBreakpoints, continue, next, stepIn, stepOut, pause, stackTrace, scopes, variables, disconnect, threads, configurationDone
  - Uses same Content-Length framing as LSP
  - Resolves DAP line breakpoints to block labels via `dap_breakpoint_resolver`
  - Starts debugger, handles events (breakpoint hit, step complete, terminated)
  - Formats stack frames with block label, region, parameter values, and source location
  - Provides variable inspection with type inference

- **`lua/lalin/dap_variables.lua`** (~90 lines) — Variable formatting for DAP display. Infers types from Lua value types (bool, i32, i64, f64, ptr) and formats values for display.

- **`lua/lalin/debug_init.lua`** (~45 lines) — Helper module for creating a Debugger instance from a compiled `BackProgram` and analysis context. Bridges the compilation pipeline to the debugger.

### New test files (2 files):
- **`tests/test_debug_interpreter.lua`** — Tests the interpreter with add_i32, abs via BrIf, and register inspection.
- **`tests/test_debugger_core.lua`** — Tests the debugger core with breakpoints, stepping, variable inspection, stack traces, and source line resolution.

## Architecture

The debugger architecture follows the simulation-based block-trace approach from the architecture spec:

1. **No traps for stepping**: Uses pure-Lua `BackCmd[]` interpretation instead of fragile signal-handler-based trap delivery
2. **Block-level stepping**: The natural fit for Lalin's jump-first semantics
3. **Two execution paths**: Interpreter for stepping/debugging; native JIT for production
4. **Zero Rust changes**: Everything in Lua, sharing the existing LSP infrastructure
5. **DAP alongside LSP**: Same STDIO loop, shared analysis context

All 6 existing Core tests and all passing LSP tests continue to pass. Build succeeds with only pre-existing Cranelift vector-type warnings.
