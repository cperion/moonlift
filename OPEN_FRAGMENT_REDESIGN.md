# MoonLift Open Fragment Redesign

This document is the implementation target for the redesign of MoonLift's `.mlua` island, Lua slicing, quote, fragment, open expansion, and validation pipeline.

The goal is not compatibility with the current open-fragment implementation. The goal is a sound, coherent meta layer.

## Hard invariants

1. `.mlua` islands are syntax templates with typed holes, not string fragments with ad-hoc splice side tables.
2. A fragment is a hygienic open term with a typed interface and body.
3. `emit` is instantiation of a fragment, not a call and not textual inclusion.
4. Fragment continuation parameters are formal parameters, not free open slots.
5. Open slots represent genuinely free meta holes only.
6. Expansion is hygienic substitution plus control-graph splicing.
7. Continuation forwarding is valid aliasing and must not require wrapper blocks.
8. Closed MoonLift after expansion contains no fragment uses, no unbound meta slots, and no open module names.
9. All identities are declaration identities, not surface names.
10. No `moon2_*` naming remains in redesigned code. Use canonical `Moon*` schema/module names and `moonlift_*` phase names only.

## Current structural failures

### 1. Island and antiquote handling is source-string based

Current `host_quote.lua` translates hosted islands into Lua calls by scanning source text and replacing `@{...}` with `__moonlift_host.source(...)` pieces.

This causes:

- heuristic splice kind inference (`expected_splice_kind`),
- string-name fragment references,
- side-table propagation of `region_frags` / `expr_frags`,
- cross-`dofile` metatable identity problems,
- parse-order dependency failures,
- accidental reliance on source concatenation.

Correct model: islands are syntax templates with explicit typed holes.

```text
IslandTemplate {
    island_id
    kind
    source_slice
    holes: [SpliceHole]
}

SpliceHole {
    hole_id
    source_range
    expected_kind
    lua_expr_source
}
```

The MoonLift island parser, not regex heuristics, determines each hole's expected kind.

### 2. `SourceChunk` side tables are not a sound dependency model

Current quote values carry:

```lua
{ source = string, region_frags = table, expr_frags = table }
```

This is a weak approximation of a dependency graph.

Correct model:

```text
QuoteValue {
    template_or_ast
    declarations: [Decl]
    dependencies: [DeclRef]
}
```

Splicing a fragment inserts a typed `FragRef`, not the fragment's surface name plus a Lua table entry.

### 3. Region fragment interface is represented as open slots

Current `RegionFrag` stores continuation formals in `open.slots`:

```text
RegionFrag(params, open.slots = [SlotCont(ok), SlotCont(fail)], entry, blocks)
```

This is wrong. A formal continuation parameter is not an unfilled open slot.

Correct shape:

```text
RegionFragDecl {
    id: FragId
    name: SurfaceName
    sig: RegionFragSig
    body: RegionFragBody
}

RegionFragSig {
    runtime_params: [OpenParam]
    continuations: [ContParam]
}

ContParam {
    id: ContParamId
    name: SurfaceName
    params: [BlockParam]
}

RegionFragBody {
    entry: EntryControlBlock
    blocks: [ControlBlock]
}
```

`OpenSet.slots` remains only for actual free meta holes.

### 4. Slot identity is under-scoped

Current parser-created continuation slots use keys like:

```text
cont:fail:2
```

This collides across fragments. All generated identities must include their owner declaration identity.

Correct identity examples:

```text
frag:<module-or-host-scope>:<fragment-name>
cont:<frag-id>:<cont-name>:<index>
param:<frag-id>:<param-name>:<index>
use:<parent-scope>:<ordinal>
label:<instantiation-path>:<local-label>
```

Surface names are diagnostics only; identity is explicit.

### 5. Fragment parsing is phase-confused

Current module compilation parses fragments iteratively because an `emit` requires the target fragment's parsed body.

Correct phases:

1. discover declarations,
2. parse interfaces,
3. build declaration environment,
4. parse bodies against interfaces,
5. resolve references,
6. validate templates,
7. expand hygienically,
8. validate closed code,
9. typecheck/lower.

Body parsing must only require target signatures, not target bodies.

### 6. Fragment instantiation is not hygienic

Current expansion rebases labels using local parser `use_id`. Nested reusable fragment uses therefore collide.

Correct expansion environment:

```text
ExpandEnv {
    instantiation_path: [UseId]
    runtime_bindings: ParamSubst
    continuation_bindings: ContSubst
}
```

Every nested fragment use extends the full path.

```text
outer-use.inner-use.local-label
```

not:

```text
inner-use.local-label
```

### 7. Continuation forwarding is valid but currently treated as unfilled slot leakage

This must be valid:

```moonlift
emit A(...; ok = ok, fail = fail)
```

Meaning:

```text
A.ok   := current.ok
A.fail := current.fail
```

Continuation resolution is transitive:

```text
resolve(cont):
    cont -> label        => label
    cont -> other cont   => resolve(other cont)
    unbound             => open until closed validation
```

Cycles are validation errors.

### 8. Validation is one phase doing two incompatible jobs

Current `open_facts` / `open_validate` mixes template validation and closed-program validation.

Correct split:

#### Template validation

Runs before expansion on open terms.

Checks:

- fragment signatures are well formed,
- continuation names unique,
- local labels unique within fragment,
- local jumps valid,
- jumps to continuation formals use correct args,
- emits target known signatures,
- emit runtime arg count/type compatibility,
- continuation fills are complete for required continuations,
- continuation forwarding type compatibility.

Does **not** report formal continuations as unfilled.

#### Closed validation

Runs after expansion.

Checks:

- no fragment uses remain,
- no unbound slots remain,
- no open module name remains,
- labels unique,
- jumps target existing labels,
- jump args match block params,
- control termination is valid.

## Redesigned pipeline

```text
.mlua document
    ↓
Document segmentation
    LuaOpaque + HostedIslandTemplate
    ↓
Lua execution
    produces QuoteValues / DeclValues / FragRefs
    ↓
Island template parsing with typed holes
    ↓
Declaration collection
    modules, funcs, structs, expr frags, region frags
    ↓
Interface pass
    all fragment/module/function signatures
    ↓
Body parse and resolution
    references resolved to declaration IDs
    ↓
Template validation
    open terms checked, formals allowed
    ↓
Open expansion
    hygienic instantiation, continuation alias normalization,
    runtime-param closure conversion
    ↓
Closed validation
    no meta constructs remain
    ↓
Typecheck
    expressions, statements, control graph
    ↓
Lowering/backend
```

## New schema direction

### MoonOpen

Keep actual open meta slots, but remove fragment continuation formals from `OpenSet.slots`.

Add first-class fragment/interface records:

```text
FragId
UseId
ContParamId

ExprFragDecl
RegionFragDecl
ExprFragSig
RegionFragSig
ContParam
FragmentEnv
```

### MoonTree

Replace body-embedded fragment use forms with declaration-reference forms:

```text
ExprEmitFrag(h, use_id, frag_ref, args, fills)
StmtEmitRegionFrag(h, use_id, frag_ref, args, fills)
```

A `frag_ref` points to a declaration identity/interface. It should not embed the reusable fragment body directly into every AST node.

### Continuation target

Represent emit fill targets explicitly:

```text
ContTargetLabel(label)
ContTargetParam(cont_param_id)
```

Do not encode formal continuation forwarding as `SlotValueContSlot` in the general open-slot system.

## Naming cleanup

The redesign removes old `moon2_*` names.

Examples:

- `moon2_open_expand_*` -> `moonlift_open_expand_*`
- `moon2_open_validate_*` -> `moonlift_open_validate_*`
- `moon2_tree_control_*` -> `moonlift_tree_control_*`
- comments saying `Moon2` / `moon2` are updated to `MoonLift` / `moonlift`.

No compatibility aliases should be added for redesigned phases.

## Implementation order

This is an architectural order, not a compatibility migration:

1. Introduce canonical identity helpers for declaration IDs, use IDs, continuation IDs.
2. Redesign schema for fragment declarations and emit references.
3. Replace island antiquote text splicing with typed hole templates.
4. Replace SourceChunk side tables with quote dependency/declaration objects.
5. Implement declaration/interface collection pass.
6. Parse/resolve bodies against interfaces.
7. Implement template validator.
8. Implement hygienic fragment expansion with full instantiation paths.
9. Implement continuation alias normalization with cycle detection.
10. Implement closed validator.
11. Remove old `moon2_*` phase names from touched pipeline.
12. Update host/runtime APIs to construct the new quote values directly.
13. Rebuild grammar combinators on the corrected fragment model.

## Success tests

The redesigned implementation must support these without wrappers or hacks:

1. Same fragment emitted twice in one region: no duplicate labels.
2. Nested reused fragment emitted through two different parents: no duplicate labels.
3. Continuation forwarding through multiple fragments: no unfilled continuation error.
4. Fragment definitions parsed out of dependency order.
5. Unknown fragment name gives a resolution error, not parse-order failure.
6. Missing/extra continuation fill gives template validation error.
7. Missing/extra runtime argument gives template validation/type error.
8. Recursive macro fragment expansion is rejected with an expansion-cycle diagnostic.
9. No `StmtEmitRegionFrag` / `ExprEmitFrag` remains after closed expansion.
10. No `moon2_*` phase names remain in redesigned files.
