# LLB Codegen Approach

LLB codegen compiles the language workbench itself.

It does not generate user program code. User programs are still authored through
ordinary Lua values, staged heads, roles, fragments, and family zones. The
codegen target is the machinery that LLB already describes declaratively:
region machines, protocol exits, role normalizers, staged heads, fragment
expanders, family projectors, diagnostics, indexers, formatters, and environment
installers.

The invariant is:

```text
reflective LLB runtime defines the semantics
compiled LLB runtime specializes those semantics
```

The architectural substrate is the region workbench model in
[`LLB_REGION_WORKBENCH_DESIGN.md`](LLB_REGION_WORKBENCH_DESIGN.md):

```text
region is the semantic control machine
protocol names the exits
GPS is one lowering ABI
materialized IR/report/index/diagnostic arrays are explicit materializers
```

Codegen therefore compiles region machines and their protocol consumers. It
should not bake in eager intermediate representations unless the generated
materializer is explicitly the consumer's requested artifact.

Semantic compatibility is governed by
[`LLB_GENERIC_REGION_ALGEBRA.md`](LLB_GENERIC_REGION_ALGEBRA.md). A codegen
backend must preserve protocol exit identity, exit class, origin metadata, and
diagnostic replay behavior declared by the generic region.

Fast paths are allowed to be small, direct, and allocation-light. Error paths
must replay through the reflective runtime so diagnostics keep the same semantic
context: language, head, slot, role, event, origin, comments, and related notes.

## Layers

The complete codegen stack is deliberately layered:

```text
1. region/protocol machines
2. role normalizers
3. fragment/spread expanders
4. staged head slot machines
5. family/project/tooling walkers
6. diagnostics/index/format pipelines
7. whole-language compiled runtime
```

Each layer specializes already-declared LLB metadata. There is no stringly
semantic side channel and no callback registry that hides meaning from ASDL,
families, LSP, or diagnostics.

## Region And GPS ABI

Region is the semantic machine:

```text
region R(input_product, state_product; protocol)
```

Protocol exits describe the possible results:

```text
item(next_state, value)
done
failed(diagnostic)
```

GPS is the low-level LuaJIT lowering ABI for pull-shaped region protocols:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

A GPS machine stores the generator, parameter object, and current state. This
makes processes and tooling pipelines compatible with direct LuaJIT-friendly
generators instead of requiring coroutine resume/yield for every event.

The consumer controls progress. A generated GPS lowering computes only the next
protocol exit required by the downstream materializer, which lets tooling
short-circuit, fusion remove intermediate arrays, and diagnostics stop after the
first hard failure when that is the requested materializer.

The target public surface is split between semantic region specs and lowering
objects:

```lua
role.region { ... }
llb.protocol. pull { ... }
llb.gps.compile(region_plan)
llb.gps.materializer.array()
```

Region specs describe semantics. GPS objects describe one lowering. Materializers
consume protocol exits into arrays, maps, text, diagnostic bags, or backend
buffers.

Current implementation:

- Public pull execution is exposed through `llb.gps`.
- Semantic implementation hooks are named `region`.
- Array-source GPS plans can be compiled into a direct generator.
- Unsupported plans explicitly fall back to fused interpretation unless strict
  codegen is requested.

## Role Normalizer Codegen

Roles are the first authoring-hot-path codegen target after the region/GPS ABI
because every completed head normalizes its slots through roles. This does not
make role codegen the whole project. It is the dependency that makes generated
heads, fragments, formatters, and family walkers worth doing.

Generic reflective normalization is intentionally broad:

```text
normalize_role(ctx, role_name, value)
  -> lookup role spec
  -> dispatch by role kind
  -> normalize nested roles
  -> run checks
```

Compiled role normalizers remove the role lookup and kind dispatch:

```lua
local norm_items = Mini.compiled.roles.items
local out = norm_items(ctx, raw_items)
```

For an array role with an item role, the generated closure performs the hot
shape directly:

```text
check table
numeric loop
expand spreads
normalize item role
run optional check
```

Current implementation:

- `llb.codegen.compile_language(lang)` builds `lang.compiled`.
- `lang.compiled.roles[name]` contains a specialized normalizer closure.
- `normalize_role` uses the compiled normalizer unless `ctx.reflective == true`
  or `ctx.codegen == false`.
- Reflective normalization remains available through the same public API.

This is closure codegen rather than source-string codegen. It is still codegen:
the grammar is compiled into specialized executable functions, but without
embedding user text in generated source.

## Fragment And Spread Codegen

Fragments and spreads are role-shaped, so their fast path belongs beside role
normalizers.

The reflective rule is:

```text
Spread(Fragment(role, items)) -> require matching role, append items
Spread(table)                 -> normalize table as current role, append output
other                         -> diagnostic
```

The compiled form should be emitted per role:

```text
expand_spread__decls(ctx, out, n, spread)
```

That function can inline the role name, the fragment role check, the append loop,
and the fallback normalization call. The failure path replays through the
reflective spread diagnostic builder.

Current implementation:

- `lang.compiled.spreads[name]` contains a per-role spread expander.
- Compiled array role normalizers call the per-role expander with a numeric
  output cursor.
- Compiled product role normalizers call the per-role expander and preserve
  duplicate-field checks.
- Compiled sum/protocol role normalizers call the per-role expander and preserve
  direct variant checks.
- Fragment spreads inline the role check and append loop.
- Table spreads normalize through the current role and append the normalized
  items.

Next hard-yank target:

- Specialize mixed/record-heavy role shapes where they are hot, then move to
  staged head machines.

## Staged Head Codegen

Heads are staged slot machines:

```lua
fn. add { a [i32], b [i32] } [i32] { ret (a + b) }
```

The reflective runtime consumes channel events:

```text
index:name
call:table
index:type
call:table
```

It checks each event against the current slot, skips optional slots when legal,
copies stage state, and eventually normalizes all slots.

Compiled heads should turn a declared head into explicit metamethod states:

```text
Head0.__index       consumes name
AfterName.__call    consumes params
AfterParams.__index consumes optional result
AfterParams.__call  skips result and consumes body
AfterResult.__call  consumes body
```

The hot success path then avoids:

- slot scanning
- generic channel fitting
- shallow stage-table copies
- generic seen/raw/origin maps by slot name
- generic `maybe_finish`

The failure path must keep enough raw stage state to replay through the
reflective head runtime.

Current implementation:

- `llb.codegen.compile_heads(lang)` builds `lang.compiled.heads`.
- Normal language exports install compiled head machines after `llb.define`.
- Compiled heads use direct compiled stage objects and compiled role
  normalizers on completion.
- Bad slot paths replay through the reflective head runtime for diagnostics.
- `:at(origin)` remains supported and reuses reflective origin-aware replay.

Next hard-yank target:

- Generate source-specialized per-head metamethod states for the hottest stable
  grammar shapes, removing the remaining per-event slot loop.

## Family Projector Codegen

Families are not just conflict resolution. They are semantic interop contracts:
shared symbols, shared types, shared origins, shared fragments, and explicit
member zones.

The reflective family walker handles:

```text
plain tables
zones
family bundles
member-owned values
member tooling hooks
```

Compiled projectors should be generated per family. A stable family can inline
member names, zone ownership, collision policy, and accepted projections.

Current implementation:

- Family projection remains reflective.

Next hard-yank target:

- Compile family zone/bundle projectors for the default Lalin family.

## Diagnostics

Generated fast paths must be diagnostically lazy.

They should not allocate rich diagnostic objects on success. On failure they
should call a replay thunk with enough semantic identity to recover the full
diagnostic:

```text
language id
role id
head id
slot id
stage snapshot
raw value
origin
```

The reflective runtime remains the source of truth for diagnostic shape and
rendering.

## Formatter And Indexer Codegen

Formatting and indexing are region-shaped tooling passes.

They should compile from semantic tags and language/family metadata:

```text
walk semantic values
classify tag
emit tokens, symbols, hovers, references, diagnostics
```

Compiled formatters and indexers should use GPS lowerings of their region
protocols so LSP can receive incremental events without coroutine overhead in
hot paths.

Current implementation:

- Family diagnostics and index already behave as pull-shaped routers with
  materializing sinks.
- LLB render/format expose pull-shaped forms; string formatting is the
  materializer.
- Deeper formatter/indexer codegen remains future work.

## Environment Installer Codegen

The family environment installer exports heads, symbols, helpers, namespaces,
capabilities, and unknown-name behavior.

For a stable family, this can become a generated installer:

```lua
install_lalin_family(env, opts)
```

The installer should use direct assignments for known exports and explicit
namespace tables for member languages. `region`, `protocol`, `exit`,
`materializer`, and `gps` are LLB workbench vocabulary. `stream` is not a family
language head. LLPVM uses `tape` for its typed bytecode sequence vocabulary.

## Trust Boundary

Generated source is internal and grammar-derived.

Rules:

- Never paste user source into generated Lua.
- Keep user hooks in parameter tables or closures.
- Use source code generation only for trusted plans.
- Expose generated source for inspection when available.
- Allow codegen to be disabled with `ctx.codegen = false` or process options.

The current role codegen uses closures, not generated source text. The old
array-plan backend uses trusted plan-derived source and stores user functions in
the parameter object; under the region model this is a GPS plan backend.

## Completion Checklist

- [x] GPS ABI.
- [x] Pull-shaped implementation API exists in committed code.
- [x] Array GPS plan source codegen.
- [x] Whole-language compiled runtime container: `lang.compiled`.
- [x] Compiled role normalizers.
- [x] Per-role compiled spread expanders for array/product/sum roles.
- [x] Compiled staged head machines installed as language exports.
- [x] Family projectors expose pull-shaped routers.
- [ ] Lazy diagnostic replay thunks with ids.
- [x] Diagnostics/index/format expose pull-shaped surfaces and materializers.
- [ ] Formatter/indexer source-generated region/GPS codegen.
- [x] Public API rename from old stream names to region/protocol/GPS names.
- [ ] Generated environment installers.
- [ ] Whole-language compiled runtime mode selection.
