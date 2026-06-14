# Zyn Synth UI-Side Projection Architecture

Status: approved.

Decision: the Zyn UI-side projection is a shared typed projection/control schema compiler. The schema is the canonical source of UI-visible Zyn synth control facts. The architecture does not use a performance-panel catalog, an ad hoc UI metadata table, or direct projection from `ParamAddress`.

## Problem

The synth exposes native control and ABI types, but not enough truthful UI facts to generate a durable UI:

- `ParamAddress` is a numeric routing key, not a UI model.
- `ParamPolicy` gives range/default/smoothing/read-only, but not label, unit, display kind, widget kind, value kind, enum choices, grouping, automation semantics, or source/product ownership.
- Existing parameter resolution advertises more writable space than parameter mutation actually changes.
- `AbiStatus.ok` is lossy and cannot drive precise UI feedback.
- `PreparedProgram` is immutable render-ready product state, not editable UI source.
- UI IDs, `ProgramRef.generation`, `Synth.generation`, and native handle lifetimes have different stability rules.
- UI state must not retain native pointers or `view(...)` handles.

The UI must preserve Moonlift's compiler-shaped UI contract:

```text
Auth.Node
  -> Layout.Node
  -> View.Op[]
  -> Interact.Report
  -> Interact.Event[]
  -> application/model update
  -> next Auth.Node
```

Widget constructors, style code, paint code, and event routers must not hide direct synth mutation.

## Rejected trap

A small hand-authored performance panel would be fast, but establishes the wrong source of truth:

- UI labels/widget hints live in Lua-only tables.
- Parameter mutation lives in Moonlift synth code.
- Command lowering lives in separate handwritten routing.
- Tests have to prove consistency after drift is possible.

That path defers the real design choice and creates migration debt. It is rejected.

## Chosen source of truth

The canonical source is a shared typed Zyn control/projection schema, conceptually near the synth example, e.g.:

```text
examples/synth/zyn_control_surface.lua
```

or a Moonlift-shaped schema source. The file format is subordinate to the architectural role: one typed source of projection/control facts.

The schema owns UI-visible control facts:

- stable control ids,
- group/page/section structure,
- value kind,
- unit/display/format policy,
- widget hint,
- mutability/read-only classification,
- binding kind,
- runtime parameter binding,
- authored patch field binding,
- meter binding,
- transport/program/note command binding,
- instance dimensions such as part/layer/fx slot,
- binding epoch/generation invalidation policy.

The schema is not a decorative UI DSL. It describes real synth/control facts.

## Derived products

From the schema, derive or generate:

- synth parameter descriptors,
- `ParamAddress` mappings,
- `resolve_parameter` behavior,
- `apply_parameter_event` mutation paths,
- UI projection descriptors,
- snapshot extraction rules,
- semantic event to control-intent lowering,
- tests proving descriptor/binding/mutation consistency.

For every declared writable runtime control:

```text
schema control
  -> descriptor
  -> binding/address
  -> resolve policy
  -> apply mutation
  -> copied snapshot observes new value
```

A writable descriptor without observable mutation is invalid.

## Source/product boundaries

- **Schema**: source of UI-visible control facts.
- **Authored patch state**: source model for patch/program editing.
- **PreparedProgram**: immutable compiled render product; never edited directly by UI.
- **Synth runtime state**: mutable runtime state, observed by copied snapshots and changed by typed commands.
- **Auth.Node**: UI product projected from schema descriptors, snapshots, and UI/app state.

The schema must classify each visible item as one of:

1. runtime parameter,
2. authored patch field,
3. read-only runtime fact,
4. meter,
5. transport/program/note command,
6. prepared-product-derived read-only fact.

Runtime edits and patch edits lower through different command paths.

## Identity and generation policy

UI IDs derive from schema control identity plus full instance keys:

```text
control-id + part + layer + bus + slot + optional subpart
```

Generations are binding guards, not primary UI identity.

Use:

```text
stable UI id
+ descriptor/binding epoch
+ ProgramRef.generation / Synth.generation guards where relevant
```

This preserves focus/hover/text/drag state while preventing stale command routing.

On epoch/generation changes:

- invalidate stale bindings,
- reject commands carrying stale binding epochs,
- repair or close menus/text edits/drags by app policy,
- preserve focus only when logical descriptor identity remains valid.

## Snapshot and lifetime policy

UI projection consumes copied host-owned snapshots, never raw native pointers/views.

```text
native synth/runtime state
  -> safe copy/query boundary
  -> generation-stamped host snapshot
  -> UI projection
```

Snapshots may contain:

- current program ref,
- synth generation,
- descriptor/binding epoch,
- runtime control values,
- transport state,
- meter values,
- read-only/value policy facts needed for disabled UI state.

Meters are read-only runtime facts. Transport is mutable runtime state but not a parameter.

## Event and command flow

Approved flow:

```text
schema descriptors + copied snapshot + UI/app state
  -> Auth.Node
  -> lower/render/runtime/interact
  -> semantic UI/widget events
  -> ControlIntent
  -> command compiler
  -> ABI call / HostEvent queue / patch edit / app transition
  -> next snapshot
  -> next Auth.Node
```

Representative intents:

```text
SetRuntimeParam
EditPatchField
PublishPatch
SetTransport
TriggerNote
SelectProgram
```

Only the command compiler lowers UI events to synth effects. Widgets do not call synth ABI functions directly.

## Verification contract

The architecture is valid only when the complete projection spine is verified:

- schema ids are unique and stable;
- descriptor instance keys avoid collisions;
- value kind and widget hint are compatible;
- read-only controls cannot lower to writes;
- every writable runtime descriptor resolves to matching policy;
- every writable runtime descriptor mutates observable state;
- snapshots contain copies, not retained native pointers/views;
- stale binding epochs reject commands;
- projected authored trees pass UI id validation;
- representative widget event -> `ControlIntent` -> synth mutation/snapshot -> next projection loop.

Existing synth tests and UI tests are necessary but not sufficient; the composed projection loop needs dedicated coverage.

## Complete control-domain coverage

The target architecture represents the full Zyn control domain in the schema:

- global controls,
- program controls,
- part controls,
- layer controls,
- additive oscillator controls,
- subtractive controls,
- PAD controls,
- envelopes,
- LFOs,
- filters,
- modulation routes,
- effects,
- transport,
- meters,
- note actions,
- program selection,
- patch publication.

Every schema item has an explicit ownership/binding classification:

- authored patch source,
- immutable prepared product,
- mutable runtime parameter,
- read-only runtime fact,
- meter,
- transport/program/note command,
- non-writable capability.

Absence is not a control-state encoding. A visible or semantically relevant fact appears in the schema with its ownership and binding classification. Mutability is granted only by a runtime-parameter binding whose mutation path and snapshot observation are part of the same derived control surface.

## Architectural invariants

1. The schema is the only source of UI-visible Zyn control facts.
2. Every Zyn control domain is represented in the schema.
3. Every represented fact has an ownership/binding classification.
4. `PreparedProgram` is never an editable UI source.
5. Runtime parameter writes exist only for schema items with mutable runtime bindings.
6. Authored patch edits and runtime parameter edits are different control intents.
7. UI IDs are stable logical identities; generations and epochs are binding guards.
8. UI projection consumes copied snapshots, never retained native pointers or views.
9. Widgets emit semantic events; only the command compiler lowers them to synth effects.
10. Derived artifacts remain inspectable and ownership-preserving.
11. Decorative UI metadata cannot exist without a corresponding control fact.
12. A declared writable control without observable mutation is architecturally invalid.
