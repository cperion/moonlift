# MoonLift Full ASDL-Hosted Refactor Plan

This is the full clean rewrite plan, not a compatibility patch.  The premise is
that `region_compose` is only a symptom.  The deeper issue is that MoonLift has
source-string hosted quoting, Lua evaluation, fragment expansion, dependency
collection, and composition partially outside the ASDL/PVM model.

The target architecture is:

```text
.mlua document
  -> ASDL document parts
  -> ASDL hosted program / templates / splice sites
  -> explicit PVM phases for Lua evaluation of host slices
  -> typed ASDL slot values / fragment values / declarations
  -> ASDL parse/typecheck/open-expand/lower phases
```

Source text remains an authoring/import format.  ASDL values become the primary
representation.  Lua evaluation becomes an explicit phase input/output, not an
implicit string-rewrite side effect.

---

## 0. Non-goals

- Do not incrementally patch `region_compose.lua` with better strings.
- Do not preserve `Host.source` as the primary intermediate representation.
- Do not add more side-table dependency propagation.
- Do not make parser `ok/fail/pos/next` the center of the region model.
- Do not add another general mutable builder framework if PVM ASDL builders can
  express the target nodes directly.

Compatibility shims may exist at the edges after the new model is in place, but
not as the design center.

---

## 1. Current architectural problem

Today hosted MoonLift has several layers that bypass ASDL:

1. `host_quote.lua` translates `.mlua` hosted islands into Lua source strings.
2. `@{...}` antiquotes are evaluated by generated Lua code.
3. `Host.source(parts)` concatenates text and side-collects dependencies.
4. Region composition generates textual `region ... end` forms.
5. Text is reparsed to recover `MoonOpen.RegionFrag` / `MoonTree.Module` ASDL.
6. Open expansion then expands fragments after this artificial reconstruction.

This creates duplicate reality:

```text
Lua value/source quote reality
ASDL/PVM compiler reality
```

The clean rewrite eliminates this split.

---

## 2. Target principle

Every hosted construct should have an ASDL representation before it has compiler
meaning.

```text
Lua evaluation is a PVM phase.
Splice sites are ASDL nodes.
Fragments are ASDL values.
Composition is ASDL construction.
Host values are explicit handles/facts, not hidden string fragments.
```

The new invariant:

```text
RegionCompose accepts canonical RegionFragValue handles.
RegionCompose returns canonical RegionFragValue handles.
Each RegionFragValue wraps/points to MoonOpen.RegionFrag ASDL and metadata.
```

---

## 3. New top-level architecture

```text
lua/moonlift/mlua_document.lua
  lexical island discovery only
  outputs MoonMlua.DocumentParts

lua/moonlift/mlua_host_model.lua              NEW
  converts DocumentParts to MoonHost.HostProgram
  preserves Lua slices, hosted islands, antiquote sites, source anchors

lua/moonlift/host_eval.lua                    NEW / replaces host_quote center
  PVM phase: HostProgram -> HostEvalResult
  evaluates Lua slices explicitly in a HostSession
  produces HostValueIds, declarations, templates, slot values, host issues

lua/moonlift/host_template_parse.lua          NEW
  PVM phase: evaluated templates -> ASDL fragments/modules/declarations
  antiquote results are already typed HostSlotValues

lua/moonlift/host_values.lua                  NEW
  canonical hosted value registry and handle types

lua/moonlift/region_compose.lua               REWRITE
  ASDL-native protocol-aware routing algebra

lua/moonlift/parser_compose.lua               NEW
  parser protocol sugar over region_compose

lua/moonlift/host_quote.lua                   RETIRE / compatibility only
  no longer owns architecture
```

---

## 4. ASDL schema additions

The exact schema can be refined, but the model should look like this.

### 4.1 Hosted program model

Add to `lua/moonlift/schema/host.lua` or a new `schema/host_eval.lua` module:

```lua
A.product "HostProgram" {
    A.field "source" "MoonHost.MluaSource",
    A.field "steps" (A.many "MoonHost.HostStep"),
    A.unique,
}

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
}
```

`HostStepLua` is not opaque runtime behavior hidden in generated Lua source.  It
is an explicit phase input.

### 4.2 Template model

```lua
A.product "HostTemplate" {
    A.field "kind" "MoonMlua.IslandKind",
    A.field "parts" (A.many "MoonHost.TemplatePart"),
    A.unique,
}

A.sum "TemplatePart" {
    A.variant "TemplateText" {
        A.field "source" "MoonSource.SourceSlice",
        A.variant_unique,
    },
    A.variant "TemplateSplice" {
        A.field "id" "string",
        A.field "expected" "MoonHost.SpliceExpectation",
        A.field "lua_source" "MoonSource.SourceSlice",
        A.variant_unique,
    },
}

A.sum "SpliceExpectation" {
    A.variant "SpliceAny",
    A.variant "SpliceExpr",
    A.variant "SpliceType",
    A.variant "SpliceEmit",
    A.variant "SpliceRegionFrag",
    A.variant "SpliceExprFrag",
    A.variant "SpliceSource",      -- legacy/import only
}
```

Eventually `SpliceSource` should be rare.  Most splices should be typed slots or
ASDL handles.

### 4.3 Host value handles

Do not put arbitrary Lua tables/functions into ASDL.  Store stable handles in a
host session registry and model the handles in ASDL.

```lua
A.product "HostValueId" {
    A.field "key" "string",
    A.field "pretty" "string",
    A.unique,
}

A.sum "HostValueKind" {
    A.variant "HostValueRegionFrag",
    A.variant "HostValueExprFrag",
    A.variant "HostValueType",
    A.variant "HostValueDecl",
    A.variant "HostValueModule",
    A.variant "HostValueLua",
    A.variant "HostValueSource",   -- legacy/import only
}

A.product "HostValueRef" {
    A.field "id" "MoonHost.HostValueId",
    A.field "kind" "MoonHost.HostValueKind",
    A.unique,
}
```

The Lua-side `HostSession` maps `HostValueId.key -> Lua object`.  The ASDL graph
contains the stable reference and kind.

### 4.4 Evaluated template / splice result

```lua
A.product "HostSpliceResult" {
    A.field "splice_id" "string",
    A.field "expected" "MoonHost.SpliceExpectation",
    A.field "value" "MoonHost.HostValueRef",
    A.unique,
}

A.product "HostEvaluatedTemplate" {
    A.field "template" "MoonHost.HostTemplate",
    A.field "splices" (A.many "MoonHost.HostSpliceResult"),
    A.field "issues" (A.many "MoonHost.HostIssue"),
    A.unique,
}
```

### 4.5 Canonical region-fragment value metadata

Some metadata can be derived from `MoonOpen.RegionFrag`, but host-facing values
need reflection and protocol facts.

```lua
A.product "RegionProtocol" {
    A.field "name" "string",
    A.field "roles" (A.many "MoonHost.ProtocolRole"),
    A.unique,
}

A.product "ProtocolRole" {
    A.field "role" "string",
    A.field "target" "string",
    A.unique,
}

A.product "RegionFragMeta" {
    A.field "name" "string",
    A.field "frag" "MoonOpen.RegionFrag",
    A.field "protocol" "MoonHost.RegionProtocol" (A.optional),
    A.field "deps" "MoonHost.FragmentDeps",
    A.unique,
}

A.product "FragmentDeps" {
    A.field "region_frags" (A.many "MoonOpen.RegionFrag"),
    A.field "expr_frags" (A.many "MoonOpen.ExprFrag"),
    A.unique,
}
```

Lua `RegionFragValue` wraps `RegionFragMeta` plus ergonomic indexed metadata:

```lua
RegionFragValue {
    id,
    name,
    frag,       -- MoonOpen.RegionFrag
    params,     -- derived OpenParam/host ParamValue view
    conts,      -- name -> ContValue/ContSlot view
    protocol,
    deps,
    T,
    session,
}
```

---

## 5. Host evaluation as explicit PVM phases

### 5.1 Build HostProgram

`mlua_document` keeps doing lexical island discovery.  A new phase converts
segments to a hosted program:

```lua
local host_program_phase = pvm.phase("moonlift_host_program", {
    [Mlua.DocumentParts] = function(parts)
        local steps = {}
        for each segment do
            if LuaOpaque then
                steps[#steps+1] = H.HostStepLua { id = fresh, source = segment.occurrence.slice }
            elseif HostedIsland then
                steps[#steps+1] = H.HostStepIsland {
                    id = fresh,
                    island = segment.island,
                    template = parse_template(segment.island),
                }
            end
        end
        return pvm.once(H.HostProgram { source = ..., steps = steps })
    end,
})
```

This replaces `host_quote.translate` as the architectural center.

### 5.2 Evaluate Lua steps

`host_eval` runs through `HostProgram.steps` in order inside a `HostSession`.
It is explicitly effectful but still phase-shaped.

```lua
local host_eval_phase = pvm.phase("moonlift_host_eval", function(program, session)
    local env = session:lua_env()
    local results = {}

    for _, step in ipairs(program.steps) do
        if classof(step) == H.HostStepLua then
            session:eval_lua_slice(step.id, step.source.text, env)
        elseif classof(step) == H.HostStepIsland then
            local evaluated = session:evaluate_template(step.template, env)
            results[#results+1] = evaluated
            session:bind_island_result(step, evaluated, env)
        end
    end

    return H.HostEvalResult { program = program, values = ..., templates = results, report = ... }
end, { cache = false })
```

Important: host eval should probably default to uncached because it executes Lua.
PVM still models the boundary and inputs/outputs.  Later, pure host chunks can be
annotated/cacheable.

### 5.3 Template evaluation

Template splices are not string substitution.  Each splice evaluates to a typed
host value:

```lua
function session:evaluate_splice(splice, env)
    local value = eval_lua_expr(splice.lua_source.text, env)
    local ref = self:intern_host_value(value, splice.expected)
    return H.HostSpliceResult { splice_id = splice.id, expected = splice.expected, value = ref }
end
```

`intern_host_value` validates kind immediately and raises `HostIssueExpected` /
specific splice issues.

---

## 6. Parsing hosted islands after evaluation

### 6.1 End-state parser model

The ideal endpoint is not “concatenate evaluated text and parse”.  The endpoint
is:

```text
HostTemplate + typed splice results -> parser with holes -> ASDL
```

A region island:

```moonlift
region @{name}(p: ptr(u8); ok: cont(next: i32))
entry start()
    emit @{frag}(p; ok = ok)
end
end
```

is parsed as source text plus typed holes:

```text
hole name: expected identifier/source-name
hole frag: expected region fragment handle
```

The parser produces ASDL directly:

```text
MoonOpen.RegionFrag
  StmtUseRegionFrag references frag.name / HostValueRef
```

The splice is explicit in ASDL/facts; dependency closure is automatic from the
HostValueRef.

### 6.2 Transitional internal representation within the clean design

Even in the full rewrite, there may be a first implementation stage where
`HostTemplate + typed splices -> ResolvedTemplateText` before parse.  But this is
an implementation detail of `host_template_parse`, not the core host value model.

If used, it must retain source maps and value refs:

```lua
A.product "ResolvedTemplateText" {
    A.field "template" "MoonHost.HostTemplate",
    A.field "text" "string",
    A.field "splice_refs" (A.many "MoonHost.HostSpliceResult"),
    A.field "source_map" "MoonSource.AnchorSet",
    A.unique,
}
```

But the target remains parser-with-holes.

---

## 7. Region composition redesign inside the full architecture

`region_compose` is rewritten as a client of ASDL/PVM builders and canonical
fragment values.

### 7.1 Core API

```lua
local C = moon.region_compose.new(session, {
    prefix = "json",
})

local routed = C:route("routed_name", frag, {
    params = frag.params,
    conts = outer_conts,
    args = C.args { "p", "n", "pos" },
    exits = {
        ok = C.to_outer("ok"),
        fail = C.to_outer("fail"),
    },
})
```

### 7.2 Core concepts

```lua
RouteTargetOuter { cont_name, arg_map }
RouteTargetBlock { block_ref, arg_map }
RouteTargetEmit  { fragment, args, exits }
RoutePlan        { fragment, args, exits }
ComposePlan      { name, params, conts, blocks, entry, deps, protocol }
```

These may be Lua planner objects, but all lowering produces ASDL with PVM
builders:

```lua
local B = T:Builders()
local Tr, O = B.MoonTree, B.MoonOpen

Tr.StmtUseRegionFrag {
    h = Tr.StmtSurface,
    use_id = session:symbol_key("emit", frag.name),
    frag_name = frag.name,
    args = args,
    fills = {},
    cont_fills = cont_bindings,
}
```

### 7.3 No baked-in parser protocol

Generic compose validates names/signatures only.

Parser composition becomes a separate layer:

```lua
local P = moon.parser_compose.new(session, {
    prefix = "json",
    params = { p: ptr(u8), n: i32, pos: i32 },
    success = "ok",
    failure = "fail",
    success_pos = "next",
    failure_pos = "at",
})

P:seq { a, b }
P:choice { a, b }
P:repeat(a, { min = 0 })
```

### 7.4 Dependency closure

`BlockBuilder:emit` or lowerer equivalent must record:

```lua
composed.deps = union(composed.deps, emitted_fragment.deps, emitted_fragment)
```

No side-table scan of source strings.

---

## 8. Canonical hosted values

Create one module to own hosted value handles:

```text
lua/moonlift/host_values.lua
```

Responsibilities:

- create `HostValueId`
- register Lua object in `HostSession`
- validate expected kind
- expose canonical `RegionFragValue`, `ExprFragValue`, `TypeValue`, etc.
- derive metadata from ASDL fragments
- forbid mixing ASDL contexts unless explicitly imported

Sketch:

```lua
function M.region_frag_value(session, meta)
    assert(classof(meta.frag) == session.T.MoonOpen.RegionFrag)
    local params = derive_params(session, meta.frag.params)
    local conts = derive_conts(session, meta.frag.conts)
    local value = setmetatable({
        kind = "region_frag",
        id = session:host_value_id("region", meta.name),
        name = meta.name,
        frag = meta.frag,
        params = params,
        conts = conts,
        protocol = meta.protocol,
        deps = meta.deps or empty_deps(session),
        T = session.T,
        session = session,
    }, RegionFragValue)
    session:register_host_value(value.id, value)
    return value
end
```

`moon.region_frag(...)`, source region islands, parser fragments, and
composition all return this same shape.

---

## 9. Retiring `host_quote.lua`

`host_quote.lua` currently does too much:

- document translation
- antiquote scanning
- host source value creation
- dependency propagation
- source parsing
- compilation bridge

In the rewrite:

```text
host_quote.lua -> compatibility facade only
```

It may expose old functions, but internally delegates to:

- `mlua_document`
- `mlua_host_model`
- `host_eval`
- `host_template_parse`
- `host_values`

Old APIs:

```lua
Host.source(parts)
Host.region_from_source(src)
Host.module_from_source(src)
```

become import/facade APIs that construct `HostTemplate` / canonical values, not
primary compiler machinery.

---

## 10. Compilation pipeline after rewrite

Current rough pipeline:

```text
source -> host_quote translation -> Lua eval -> source quote -> parse -> open expand
```

New pipeline:

```text
source
  -> mlua_document_parts                         ASDL
  -> host_program                                ASDL
  -> host_eval(program, session)                 explicit PVM phase
  -> host_template_parse(eval_result)            ASDL modules/frags/decls
  -> host_pipeline(decls)                        ASDL host facts/plans
  -> open_expand(module, canonical fragment env) ASDL
  -> typecheck
  -> tree_to_back
  -> back_validate
  -> backend
```

Hosted Lua still exists, but it is explicit:

```text
HostStepLua(SourceSlice) --phase--> HostValueRegistry/HostEvalResult
```

---

## 11. Error model

Add structured host issues for the new layer:

```lua
HostIssueSpliceExpected {
    splice_id: string,
    expected: SpliceExpectation,
    actual: string,
}

HostIssueSpliceEvalError {
    splice_id: string,
    message: string,
}

HostIssueLuaStepError {
    step_id: string,
    message: string,
}

HostIssueTemplateParseError {
    template_id: string,
    message: string,
}

HostIssueRegionComposeMissingExit {
    fragment_name: string,
    exit_name: string,
}

HostIssueRegionComposeIncompatibleCont {
    fragment_name: string,
    exit_name: string,
    expected: string,
    actual: string,
}

HostIssueRegionComposeIncompleteRoute {
    fragment_name: string,
    exit_name: string,
}

HostIssueRegionComposeContextMismatch {
    left: string,
    right: string,
}
```

No more delayed parse/typecheck noise for host composition mistakes.

---

## 12. Concrete code skeletons

### 12.1 `mlua_host_model.lua`

```lua
local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = T.MoonHost
    local Mlua = T.MoonMlua

    local phase = pvm.phase("moonlift_mlua_host_program", {
        [Mlua.DocumentParts] = function(parts)
            local steps = {}
            for i = 1, #parts.segments do
                local seg = parts.segments[i]
                local cls = pvm.classof(seg)
                if cls == Mlua.LuaOpaque then
                    steps[#steps + 1] = H.HostStepLua(
                        "lua." .. tostring(i),
                        seg.occurrence.slice)
                elseif cls == Mlua.HostedIsland then
                    steps[#steps + 1] = H.HostStepIsland(
                        "island." .. tostring(i),
                        seg.island,
                        M.parse_template(T, seg.island))
                elseif cls == Mlua.MalformedIsland then
                    -- Model malformed islands as issues in HostProgram or report.
                end
            end
            return pvm.once(H.HostProgram(H.MluaSource(parts.document.uri.path, parts.document.text), steps))
        end,
    })

    return { host_program = phase }
end

return M
```

Use PVM no-parens builders if preferred:

```lua
local B = T:Builders()
local H = B.MoonHost
return H.HostProgram { source = ..., steps = steps }
```

### 12.2 `host_eval.lua`

```lua
local M = {}

function M.Define(T)
    local H = T.MoonHost

    local eval = require("moonlift.pvm").phase("moonlift_host_eval", function(program, session)
        local values, templates, issues = {}, {}, {}
        local env = session:lua_env()

        for _, step in ipairs(program.steps) do
            local ok, result_or_err = session:evaluate_host_step(step, env)
            if not ok then
                issues[#issues + 1] = result_or_err
            elseif result_or_err then
                templates[#templates + 1] = result_or_err
            end
        end

        return H.HostEvalResult(program, values, templates, H.HostReport(issues))
    end, { cache = false })

    return { eval = eval }
end

return M
```

### 12.3 ASDL-native region compose lowering

```lua
function Compose:lower_emit(block, frag, args, routes)
    self:require_region_value(frag)
    self:validate_args(frag, args)
    self:validate_routes(frag, routes)

    local cont_fills = {}
    for exit_name, target in ordered_pairs(routes) do
        cont_fills[#cont_fills + 1] = self:lower_cont_binding(exit_name, target)
    end

    return self.Tr.StmtUseRegionFrag {
        h = self.Tr.StmtSurface,
        use_id = self.session:symbol_key("emit", frag.name),
        frag_name = frag.name,
        args = args,
        fills = {},
        cont_fills = cont_fills,
    }
end
```

### 12.4 Canonical RegionFragValue creation

```lua
function HostValues.region_frag(session, frag, opts)
    opts = opts or {}
    local meta = {
        name = frag.name,
        frag = frag,
        params = derive_params(session, frag.params),
        conts = derive_conts(session, frag.conts),
        protocol = opts.protocol,
        deps = opts.deps or empty_deps(session),
    }
    return setmetatable(meta, RegionFragValue)
end
```

---

## 13. Test strategy

### Host model tests

- `.mlua` document becomes `DocumentParts`.
- `DocumentParts` becomes `HostProgram` with ordered Lua/island steps.
- Template antiquote sites preserve source ranges and expected kinds.

### Host eval tests

- Lua slice defines a value; later island splice sees it.
- Splice type mismatch produces `HostIssueSpliceExpected`.
- Lua eval error becomes `HostIssueLuaStepError` with range/step id.
- Host value IDs are stable inside one session.

### Template parse tests

- Region island with spliced region frag records dependency.
- Expr island with spliced type emits typed ASDL.
- Module island containing local region fragments returns module + frags.
- Parser-with-holes preserves source anchors.

### Region value tests

- Source region island returns canonical `RegionFragValue`.
- `moon.region_frag` builder returns same canonical shape.
- Composed region returns same canonical shape.
- Context mismatch is rejected.

### Composition tests

- `route` forwards arbitrary continuation names.
- Missing exit fails early.
- Incompatible continuation signatures fail early.
- Deps are transitively closed.
- Generated block names are hygienic.
- Parser `seq/choice/star` are implemented only in parser layer.

### End-to-end tests

- Existing tokenizer fragments rebuilt through parser layer.
- JSON parser/control composition does not use source generation.
- Hosted JSON implementation compiles without backend-baked grammar hacks.
- LSP diagnostics report host eval/template/compose issues structurally.

---

## 14. Implementation checklist

### Phase A: Schema foundation

- [ ] Add HostProgram / HostStep / HostTemplate / TemplatePart schemas.
- [ ] Add SpliceExpectation schema.
- [ ] Add HostValueId / HostValueRef / HostValueKind schemas.
- [ ] Add HostEvalResult / HostEvaluatedTemplate / HostSpliceResult schemas.
- [ ] Add RegionProtocol / RegionFragMeta / FragmentDeps schemas.
- [ ] Add structured host issue variants.
- [ ] Regenerate/validate ASDL builders.
- [ ] Add schema construction tests.

### Phase B: Canonical host value layer

- [ ] Create `lua/moonlift/host_values.lua`.
- [ ] Move/unify RegionFragValue, ExprFragValue, TypeValue concepts.
- [ ] Implement host session value registry.
- [ ] Implement `HostValueId` creation and kind validation.
- [ ] Implement metadata derivation from `MoonOpen.RegionFrag`.
- [ ] Implement context mismatch checks.
- [ ] Update `moon.region_frag` to return canonical RegionFragValue.
- [ ] Update expr frag builder similarly.

### Phase C: Hosted program model

- [ ] Create `lua/moonlift/mlua_host_model.lua`.
- [ ] Convert `DocumentParts` to `HostProgram`.
- [ ] Parse antiquote sites into `HostTemplate` ASDL.
- [ ] Preserve source ranges and expected splice kinds.
- [ ] Add host model tests.

### Phase D: Explicit host eval phase

- [ ] Create `lua/moonlift/host_eval.lua`.
- [ ] Implement ordered Lua slice evaluation in `HostSession`.
- [ ] Implement expression evaluation for `TemplateSplice`.
- [ ] Register values as HostValueRefs.
- [ ] Produce structured issues instead of thrown string errors.
- [ ] Mark phase uncached/effectful initially.
- [ ] Add tests for Lua eval and splice errors.

### Phase E: Template-to-ASDL parsing

- [ ] Create `lua/moonlift/host_template_parse.lua`.
- [ ] Implement evaluated template parse for struct/expose/func/module/region/expr.
- [ ] First acceptable endpoint: resolved text plus source map.
- [ ] Final endpoint: parser with typed holes.
- [ ] Parse region/expr islands into canonical fragment values.
- [ ] Parse module islands with local fragments as ASDL values/deps.
- [ ] Remove dependency side-table string propagation from parse path.

### Phase F: Region composition rewrite

- [ ] Rewrite `lua/moonlift/region_compose.lua` from scratch.
- [ ] Use `T:Builders()` / PVM ASDL builders directly.
- [ ] Implement route targets: outer, block, emit.
- [ ] Implement validation: exits, signatures, args, fills, context.
- [ ] Implement dependency closure.
- [ ] Implement hygiene namespace.
- [ ] Implement generic operations: route, forward, rename, switch, loop.
- [ ] Do not implement parser-specific star/plus/opt in core.

### Phase G: Parser layer

- [ ] Create `lua/moonlift/parser_compose.lua`.
- [ ] Define parser protocol role object.
- [ ] Implement seq, choice, repeat/star/plus, opt, pred, not_pred over core compose.
- [ ] Update tokenizer/grammar clients to use parser layer.
- [ ] Remove parser assumptions from core region compose.

### Phase H: Retire host_quote center

- [ ] Make `host_quote.lua` a compatibility facade.
- [ ] Route `Host.dofile`, `Host.source`, `region_from_source`, etc. through new phases.
- [ ] Remove source quote dependency accumulation as core behavior.
- [ ] Keep legacy APIs only as import wrappers.
- [ ] Update documentation to describe ASDL-hosted pipeline.

### Phase I: Pipeline integration

- [ ] Update `mlua_parse` / document analysis to consume `HostEvalResult` outputs.
- [ ] Feed canonical fragment envs into open expansion.
- [ ] Ensure host issues appear in editor diagnostics.
- [ ] Ensure source anchors survive host eval/template parse.
- [ ] Update compile paths to use new pipeline.

### Phase J: Deletion and cleanup

- [ ] Delete old source-string `region_compose` implementation.
- [ ] Delete duplicated RegionFragValue definitions.
- [ ] Remove artificial expansion/dependency hacks in `host_quote.lua`, `grammar.mlua`, `parser.mlua`.
- [ ] Remove tests that assert source quote behavior as primary.
- [ ] Replace with ASDL-value tests.

---

## 15. Acceptance criteria

The rewrite is complete when these statements are true:

1. A hosted region island becomes a canonical RegionFragValue wrapping ASDL.
2. A builder-created region and source-created region have the same host value
   shape.
3. `region_compose` never calls `Host.source`.
4. `region_compose` never constructs `region ... end` text.
5. Composition of fragments returns a real fragment value with metadata and deps.
6. Parser combinators live outside the generic region algebra.
7. Lua antiquote evaluation is represented as explicit ASDL HostStep /
   TemplateSplice phase data.
8. Host eval errors and compose errors are structured ASDL issues.
9. Fragment dependencies are closed structurally, not by string side tables.
10. The compiler pipeline can be explained entirely as ASDL/PVM phases plus an
    explicit effectful host-eval phase.

---

## 16. Design summary

The clean model is:

```text
Source text is syntax.
Lua evaluation is an explicit host phase.
Splices are typed ASDL slots.
Fragments are ASDL values.
Composition is typed continuation routing over ASDL fragments.
Open expansion consumes ASDL fragment environments, not source-generated ghosts.
```

This makes `region_compose` small and honest, but more importantly it makes
MoonLift itself consistent with its ASDL/PVM philosophy.
