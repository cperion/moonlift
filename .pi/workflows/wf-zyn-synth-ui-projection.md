# Zyn synth UI side projection design 
Design the UI-side projection layer for the Zyn Lalin synth: how synth/program/control state should become typed UI authored tree, semantic widget events, and ABI/control events without violating Lalin's compiler-shaped UI contracts.
**Workflow ID**: wf-zyn-synth-ui-projection
**Started**: 2026-06-14 04:31:17
---

## Scout Output — 2026-06-14 04:34:32

## Files Retrieved

1. `lua/ui/README.md` (lines 1-340) — UI kit overview, compiler-shaped pipeline, widget catalog, SDL3 backend status, current limitations.
2. `lua/ui/CONTRACT.md` (lines 1-430) — authoritative UI kernel contract: authored tree → layout → view ops → runtime report → interaction reducer → next authored tree.
3. `lua/ui/BACKEND_CONTRACT.md` (lines 1-435) — runtime/host/text backend contracts; SDL3 product-readiness requirements.
4. `lua/ui/asdl.lua` (lines 1-1090) — typed ASDL vocabulary for Core IDs, Auth/Layout/View/Interact/Text/Paint/Solve.
5. `lua/ui/build.lua` (lines 1-420) — authored tree builders: box/text/paint/scroll/input/drag/drop.
6. `lua/ui/lower.lua` (lines 1-520) — Auth → Layout lowering, style/state resolution, ID validation hook.
7. `lua/ui/render.lua` (lines 1-440) — Layout → `View.Op` stream generation.
8. `lua/ui/runtime.lua` (lines 1-520) — consumes view ops, draws via backend driver, builds `Interact.Report`.
9. `lua/ui/interact.lua` (lines 1-720) — pure reducer from `Interact.Raw` + report + model to semantic events/model.
10. `lua/ui/input.lua` (lines 1-260) — host event → typed raw input conversion.
11. `lua/ui/id.lua` (lines 1-322) — ID collection/validation for Auth/Layout/Compose/surface maps.
12. `lua/ui/state.lua` (lines 1-260) — bridge from interaction model/report/app flags to `Style.State`.
13. `lua/ui/widget.lua` (lines 1-400) — canonical widget bundle/surface/event routing helpers.
14. `lua/ui/widgets/README.md` (lines 1-320) — canonical widget bundle/event contract and catalog docs.
15. `lua/ui/widgets/{button,toggle,slider,knob,meter,menu,canvas,text_input}.lua` — concrete widget implementations and event routing.
16. `lua/ui/recipes/{activatable,selectable_list,scroll_view}.lua` — lower-level reusable interaction recipes.
17. `lua/ui/session.lua` (lines 1-540) — multi-window loop, typed raw dispatch, redraw scheduling, text lifecycle.
18. `lua/ui/backends/sdl3/init.lua` (lines 1-80) — SDL3 backend package/capabilities.
19. `lua/ui/host_sdl3.lua` (lines 1-473) — SDL host event normalization, typed raw attachment, host lifecycle.
20. `lua/ui/runtime_sdl3.lua` (lines 1-798) — SDL3 renderer driver and capabilities.
21. `lua/ui/text.lua` (lines 1-890) — text system registry/default/fallback policy.
22. `lua/ui/text_field.lua` (lines 1-190), `lua/ui/widgets/_text_common.lua` (lines 1-330) — editable text field state, overlay draw helpers.
23. `lua/ui/compose.lua` (lines 1-130) — typed composition nodes lowered to Auth trees.
24. `lua/ui/theme.lua` (lines 1-220), `lua/ui/tw.lua` (lines 1-666) — theme/env factories and Tailwind-like style tokens/state conditions.
25. `lua/ui/paint.lua` (lines 1-147) — typed paint program builders.
26. `examples/ui/{paint_sdl3_demo,text_field_sdl3_demo,text_sdl3_probe}.lua` — current UI examples; no Zyn/synth UI example exists.
27. `tests/test_ui_{smoke,id_validation,interact_contract,state_bridge,sdl3_paint}.lua` — current UI tests.
28. `.pi/workflows/wf-a6d2de07.md` + `.edit-plans/ui-completion.json` — prior UI completion workflow; notes many synth-readiness tasks now done, but synth demo still todo.
29. `.pi/workflows/wf-zyn-synth-ui-projection.md` — current workflow stub only.
30. `examples/synth/zyn_lalin_synth_spec.md` (lines 1-500) — behavioral contract for synth implementation.
31. `examples/synth/zyn_lalin_synth_headers.mlua` (lines 1-1201) — complete synth product/control/protocol/ABI surface.
32. `examples/synth/zyn_lalin_synth_impl.mlua` key ranges around controls/events/ABI — current implementation bodies.
33. `tests/test_zyn_lalin_synth_impl.lua` (lines 1-690+) — synth compile/behavior smoke coverage and host-side FFI shapes.

## Key Code

### UI pipeline contract

```text
Auth.Node
  -> lower.root / lower.phase
  -> Layout.Node
  -> measure / render
  -> View.Op[]
  -> runtime.run(driver, opts, ops...)
  -> Interact.Report
  -> interact.step(model, report, raw)
  -> semantic Interact.Event[] + next Interact.Model
  -> widget bundle routing / application state update
```

From `lua/ui/README.md` and `lua/ui/CONTRACT.md`.

### Core UI ASDL surfaces

`lua/ui/asdl.lua` defines:

```lua
module Auth {
  Node = Box(...) | Text(...) | TextRef(...) | Paint(...) | Scroll(...)
       | WithState(...) | WithInput(...)
       | WithDragSource(...) | WithDropTarget(...) | WithDropSlot(...)
       | FocusScope(...) | Layer(...) | Overlay(...) | Modal(...)
       | Fragment(...) | Empty
}

module View {
  Kind = KBox | KText | KPaint | KPushClipRect | KPopClip | KPushTx | KPopTx
       | KPushScroll | KPopScroll
       | KHit | KFocus | KCursor
       | KDragSource | KDropTarget | KDropSlot
       | KFocusScope | KEndFocusScope
       | KPushLayer | KPopLayer | KOverlay | KModalBarrier
}

module Interact {
  Raw = PointerMoved(...) | PointerPressed(...) | PointerReleased(...)
      | WheelMoved(...) | KeyPressed(...) | KeyReleased(...)
      | TextInput(...) | TextEditing(...)
      | FocusNext | FocusPrev | ActivateFocus | CancelPointer

  Event = SetPointer(...) | SetHover(...) | SetFocus(...) | Activate(...)
        | InputText(...) | EditText(...) | DragMoved(...) | ScrollBy(...)
}
```

### Widget bundle contract

`lua/ui/widget.lua` builds bundles shaped like:

```lua
{
  kind = spec.kind,
  id = id,
  node = spec.node,
  surfaces = spec.surfaces or {},
  model = spec.model,
  events = spec.events or {},
  disabled = ...,
  selected = ...,
  style_slots = ...,
  route_ui_event = function(self, ui_event) ... end,
  route_ui_events = function(self, ui_events) ... end,
}
```

Common widget events include `activate`, `change`, `input`, `edit`, `focus`, `blur`, `select`, `scroll`, `open`, `close`, `drag_*`.

### Synth control/ABI surface

`examples/synth/zyn_lalin_synth_headers.mlua` defines product/control types:

```lalin
T.ParamAddress = struct
    scope: u8,
    part: u16,
    layer: u16,
    bus: u16,
    slot: u16,
    param: u16,
end

T.ParameterEvent = struct
    address: ParamAddress,
    value: f32,
    frame: index,
end

T.HostEvent = struct
    kind: u8,
    midi: MidiEvent,
    parameter: ParameterEvent,
    program: ProgramRef,
    transport: TransportState,
    frame: index,
end

T.Synth = struct
    current_program: ProgramRef,
    storage: SynthStorage,
    policy: EnginePolicy,
    transport: TransportState,
    last_meter: MeterFrame,
    generation: u64,
end
```

ABI functions:

```lalin
F.synth_prepare_program(...)
F.synth_render_block(...)
F.synth_set_parameter(s: ptr(Synth), ev: ParameterEvent): i32
F.synth_note_on(...)
F.synth_note_off(...)
F.synth_all_notes_off(...)
F.synth_panic(...)
```

Parameter scopes:

```lua
E.ParamScope = {
  global = 1, part = 2, layer = 3, modulation = 4,
  insert_fx = 5, send_fx = 6, master_fx = 7,
}
```

### Current synth parameter implementation facts

`zyn_lalin_synth_impl.mlua`:

- `resolve_parameter` returns a generic `[0,1]` `ParamPolicy`; global param `0` is read/write, global param `1` read-only; other known scopes resolve to generic writable policy.
- `apply_parameter_event` only writes `controls.macro_values[param]` for global parameters within `macro_count`.
- `apply_host_events` similarly special-cases global macro writes.
- `F.synth_set_parameter` maps changed/unchanged/smoothed/read_only/out_of_range to ABI `ok`; unknown/no_program/bad_state to `bad_state`.

## Relationships

- `ui.build` authors `Auth.Node`; widgets also produce `Auth.Node`.
- `ui.lower.root` validates IDs, optionally applies state bridge, resolves styles, and returns `Layout.Node[]`.
- `ui.render.root` emits `View.Op` triplets.
- `ui.runtime.run` consumes view ops, draws through backend driver, and builds `Interact.Report`.
- `ui.interact.step` consumes one typed raw input and returns semantic `Interact.Event[]` plus next `Interact.Model`.
- Widgets route reducer events through their `surfaces` tables into widget-level events.
- Apps own final state mutation and author the next tree.
- SDL3 host events are normalized into Lua host tables and attach `ev.raw` / `ev.raws` via `ui.input`.
- Zyn synth ABI consumes typed Lalin structs/events (`ParameterEvent`, `MidiEvent`, `HostEvent`, `ProgramRef`) and returns integer `AbiStatus` at ABI boundary only.
- There is no existing `examples/ui/synth_sdl3_demo.lua` and no Zyn-specific UI projection module found.

## Observations

- UI contracts explicitly require meaningful UI/input/focus/widget state to be ASDL-shaped, not hidden in callbacks/string events.
- IDs are global per authored tree; validation covers Auth nodes, wrappers, layers, overlays, content refs, and widget-generated child IDs.
- SDL3 is the product backend and declares capabilities for rounded/capsule boxes, clipping, scrolling, paint primitives, text layout/hit/ranges, clipboard, IME, timers.
- Prior workflow notes that synth-oriented widgets were previously missing; current tree now has slider, fader, value_drag, knob, meter/progress, menu/select, canvas, text widgets.
- Remaining UI examples are generic paint/text probes; synth controls demo is still marked todo in UI completion sidecar.
- Runtime currently records some layer/overlay facts less richly than Auth/Layout carry them: e.g. `runtime.lua` hardcodes focus scope policy to `FocusWrap`, layer kind to `LayerOverlay`, and overlay anchor/placement/modal to defaults when constructing report facts.
- Several widgets have `KeyPressed` routing branches, but `interact.step` usually consumes key raw input and emits higher-level events only for Tab/Return/Space/Escape; arrow-key widget adjustment may require routing raw key events separately.
- Text widget caret/selection/IME drawing is intentionally a second rendering path after the main op stream.
- Synth exposes control/event ABI, but no UI-side parameter metadata catalog was found: no labels, units, grouping, ranges beyond generic `ParamPolicy`, display formatting, or mapping table from widget IDs to `ParamAddress`.
- Prepared synth programs are immutable native products; mutable control state lives in `ControlBank`, `VoicePool`, `EffectRack`, `Synth.last_meter`, `Synth.transport`, etc.
- Host/UI can plausibly read/write through ABI/FFI, but existing synth tests only exercise low-level compiled functions and FFI smoke shapes, not a UI projection.

## Scout Output — 2026-06-14 04:34:40

## Files Retrieved

1. `examples/synth/zyn_lalin_synth_headers.mlua` (lines 1-1203) - Full public synth surface: encoding tables, product structs, region protocols, ABI seal functions.
2. `examples/synth/zyn_lalin_synth_spec.md` (lines 1-454) - Behavioral contract: storage, patch format, event semantics, parameter semantics, render order, ABI status mapping.
3. `examples/synth/zyn_lalin_synth_impl.mlua` (lines 1-940, 935-2114, 2115-3514, 4315-4946) - Implementation of storage/init, patch prep, event/control paths, modulation path, render orchestration, ABI status mapping.
4. `tests/test_zyn_lalin_synth_impl.lua` (lines 1-688) - Compile coverage and FFI behavioral smoke for ABI, events, voice lifecycle, render, DSP/modulation.
5. `LALIN_COMPILER_PATTERN.md` (lines 1-140, 220-520, 780-1070) - Live compiler/UI projection doctrine: authored source products → phases/facts → sealed loop; UI rendering example.
6. `THE_LALIN_DESIGN_BIBLE.md` (lines 36-106, 346-446) - Design doctrine: type forest/control graph, encoded tags with one owner region, protocol ownership.
7. `LANGUAGE_REFERENCE.md` (lines 3195-3245, 3480-3530) - View ABI and host-owned buffer boundary semantics.

## Key Code

### Header-level machine sentence / contract

`examples/synth/zyn_lalin_synth_headers.mlua` lines 16-23:

```lua
-- Machine sentence:
--   This system consumes patch/program bytes, MIDI/host events, controller and
--   transport facts, persistent synth state, and output views; it produces
--   stereo audio blocks by preparing AD/SUB/PAD tone plans, scheduling events,
--   advancing voices through explicit lifecycle protocols, rendering tone
--   fields, applying effect graphs, mixing parts, reporting meters, and sealing
--   host-visible outcomes as ABI status integers only at the boundary.
```

### Encoding tables and owners

Header encodings are Lua documentation tables, not Lalin semantic unions. Each has an owner region.

Examples:

```lua
-- Owner: R.classify_host_event.
E.HostEventKind = {
    midi            = 1,
    parameter       = 2,
    program_change  = 3,
    transport       = 4,
    all_notes_off   = 5,
    panic           = 6,
}

-- Owner: R.resolve_parameter.
E.ParamScope = {
    global      = 1,
    part        = 2,
    layer       = 3,
    modulation  = 4,
    insert_fx   = 5,
    send_fx     = 6,
    master_fx   = 7,
}

-- Owner: F.* ABI functions only.
E.AbiStatus = {
    ok                  = 0,
    bad_state           = 1,
    bad_buffer          = 2,
    bad_patch           = 3,
    unsupported_patch   = 4,
    exhausted_storage   = 5,
    stale_handle        = 6,
}
```

Other public encodings: `MidiKind`, `ToneMask`, `VoiceStage`, `EnvelopeCurve`, `LfoShape`, `FilterModel`, `ModSource`, `ModDest`, `EffectKind`, `PatchSectionKind`, `VoiceStealMode`.

### Core refs / handles

`examples/synth/zyn_lalin_synth_headers.mlua` lines 315-345:

```lalin
T.ProgramRef = struct
    bank: u16,
    program: u16,
    generation: u16,
end

T.PartRef = struct
    index: u16,
    generation: u16,
end

T.LayerRef = struct
    part_index: u16,
    layer_index: u16,
    generation: u16,
end

T.VoiceRef = struct
    index: u32,
    generation: u16,
end

T.PadTableRef = struct
    index: u32,
    generation: u16,
end

T.EffectRef = struct
    bus: u16,
    slot: u16,
    generation: u16,
end
```

### Program / parameter / event products

`ParamAddress` is raw numeric addressing, not descriptive metadata:

```lalin
T.ParamAddress = struct
    scope: u8,
    part: u16,
    layer: u16,
    bus: u16,
    slot: u16,
    param: u16,
end

T.ParamPolicy = struct
    min_value: f32,
    max_value: f32,
    default_value: f32,
    smoothing_ms: f32,
    read_only: bool,
end
```

Events:

```lalin
T.MidiEvent = struct
    kind: u8,
    channel: u8,
    a: u8,
    b: u8,
    frame: index,
end

T.ParameterEvent = struct
    address: ParamAddress,
    value: f32,
    frame: index,
end

T.HostEvent = struct
    kind: u8,
    midi: MidiEvent,
    parameter: ParameterEvent,
    program: ProgramRef,
    transport: TransportState,
    frame: index,
end
```

Control state:

```lalin
T.ControlState = struct
    pitch_bend: f32,
    channel_pressure: f32,
    sustain: bool,
    expression: f32,
    mod_wheel: f32,
    volume: f32,
    pan: f32,
end

T.ControlBank = struct
    states: ptr(ControlState),
    cc_values: ptr(u8),
    macro_values: ptr(f32),
    channel_count: index,
    macro_count: index,
end
```

### Prepared program representation

`examples/synth/zyn_lalin_synth_headers.mlua` lines 569-578:

```lalin
-- Immutable prepared program/patch.  Any cached derived data lives in explicit
-- caches below, not beside source facts except as phase output references.
T.PreparedProgram = struct
    parts: view(PartPlan),
    part_count: index,
    effects: EffectGraphPlan,
    tuning: TuningTable,
    generation: u16,
end
```

`PatchSource` is host-owned bytes:

```lalin
T.PatchSource = struct
    bytes: ByteSlice,
    format_id: u32,
    version: u32,
end
```

### Runtime state root

```lalin
T.SynthStorage = struct
    arena: ByteArena,
    programs: ProgramStore,
    voices: VoicePool,
    controls: ControlBank,
    pad_cache: PadCache,
    effects: EffectRack,
end

T.Synth = struct
    current_program: ProgramRef,
    storage: SynthStorage,
    policy: EnginePolicy,
    transport: TransportState,
    last_meter: MeterFrame,
    generation: u64,
end
```

### Public ABI seals

`examples/synth/zyn_lalin_synth_headers.mlua` lines 1185-1201:

```lalin
F.synth_required_storage = func(config: SynthConfig): index end
F.synth_init = func(s: ptr(Synth), storage: SynthStorage, config: SynthConfig, policy: EnginePolicy, sample_rate_hz: f32): i32 end
F.synth_prepare_program = func(s: ptr(Synth), target: ProgramRef, src: PatchSource): i32 end
F.synth_render_block = func(s: ptr(Synth), events: view(HostEvent), ctx: RenderCtx, scratch: ptr(RenderScratch), out_l: view(f32), out_r: view(f32)): i32 end
F.synth_set_parameter = func(s: ptr(Synth), ev: ParameterEvent): i32 end
F.synth_note_on = func(s: ptr(Synth), channel: u8, note: u8, velocity: f32): i32 end
F.synth_note_off = func(s: ptr(Synth), channel: u8, note: u8): i32 end
F.synth_all_notes_off = func(s: ptr(Synth), channel: u8): i32 end
F.synth_panic = func(s: ptr(Synth)): i32 end
```

### Parameter resolution / update implementation

`examples/synth/zyn_lalin_synth_impl.mlua` lines 2447-2482:

```lalin
R.resolve_parameter = R.resolve_parameter(BODY)[[
entry start()
    let rw: ParamPolicy = { min_value = as(f32, 0.0), max_value = as(f32, 1.0), default_value = as(f32, 0.0), smoothing_ms = as(f32, 5.0), read_only = false }
    let ro: ParamPolicy = { min_value = as(f32, 0.0), max_value = as(f32, 1.0), default_value = as(f32, 0.0), smoothing_ms = as(f32, 0.0), read_only = true }
    if address.scope == @{PARAM_SCOPE_GLOBAL} then
        if address.param == 0 then jump resolved(policy = rw) end
        if address.param == 1 then jump read_only(policy = ro) end
    end
    if address.scope == @{PARAM_SCOPE_PART} or address.scope == @{PARAM_SCOPE_LAYER} or address.scope == @{PARAM_SCOPE_MODULATION} or address.scope == @{PARAM_SCOPE_INSERT_FX} or address.scope == @{PARAM_SCOPE_SEND_FX} or address.scope == @{PARAM_SCOPE_MASTER_FX} then jump resolved(policy = rw) end
    jump unknown(address = address)
end
]]
```

`apply_parameter_event` only writes global macro values:

```lalin
if controls ~= nil and ev.address.scope == @{PARAM_SCOPE_GLOBAL} and as(index, ev.address.param) < (*controls).macro_count then
    controls[0].macro_values[as(index, ev.address.param)] = clamped
end
```

### Host/MIDI classification

`classify_host_event` maps `HostEvent.kind` to typed exits; unknown becomes `ignored`.

`classify_midi_event` masks high nibble and handles note-on velocity 0 as note-off; pitch bend normalized from 14-bit center.

### Render root order

Spec lines 410-419:

```text
1. enter_render_memory
2. clear_audio_block
3. clear_scratch
4. apply_host_events
5. render_all_parts
6. apply_send_effects
7. finalize_audio_block
8. retire dead voices when RenderPolicy.retire_dead_voices_after_block is true
```

Implementation follows this via `HLP.render_block_ready`: clear output, clear scratch, apply render events, render parts, apply sends, finalize meter/clipping, optionally retire dead voices.

### View ABI reference

`LANGUAGE_REFERENCE.md` lines 3197-3214:

```c
typedef struct LalinView_T {
    T* data;
    intptr_t len;
    intptr_t stride;
} LalinView_T;
```

Views may be exposed as descriptor, data/len/stride, or pointer policy depending on host/API exposure.

## Relationships

### Public state surface

- `Synth` is the root persistent state.
- `Synth.storage` owns:
  - `ProgramStore` of `ProgramSlot` entries pointing to immutable `PreparedProgram`.
  - `VoicePool` with dense active list, generation array, free list.
  - `ControlBank` with channel controls, CC array, macro array.
  - `PadCache` and `EffectRack`.
- `Synth.current_program: ProgramRef` selects the active published program.
- `Synth.transport` and `Synth.last_meter` are directly stored observable runtime facts.
- `Synth.generation` is bumped on close.

### Program lifecycle

1. Host supplies `PatchSource` bytes.
2. `R.decode_patch_source` / `R.next_patch_section` validate `ZYNM` v1 directory.
3. `R.prepare_program` allocates prepared products into `SynthStorage.arena`.
4. `R.validate_program` checks structural constraints.
5. `R.rebuild_pad_cache` updates pad cache if needed.
6. `R.publish_prepared_program` stores pointer in `ProgramStore`.
7. `F.synth_prepare_program` sets `s.current_program` to the published `ProgramRef`.

Prepared data is immutable after publication; parameter updates are supposed to hit mutable control/runtime state only.

### Event/control path

Host event path:

```text
view(HostEvent)
  -> classify_host_event
  -> apply_midi_event / apply_parameter_event / apply_transport_event
  -> voice pool / control bank / synth transport changes
```

Render path uses `HLP.apply_host_events_in_render`, which has `RenderCtx` and can filter `frame < 0` or `frame > ctx.shape.frame_count`.

Non-render `R.apply_host_events` has a comment that it lacks `RenderCtx`, so it can reject negative frames but cannot compare to block length.

### Parameter path

```text
ParamAddress(scope, part, layer, bus, slot, param)
  -> R.resolve_parameter
  -> ParamPolicy(min/max/default/smoothing/read_only)
  -> R.apply_parameter_event
  -> ControlBank.macro_values for global macro params
```

The implementation currently treats most non-global scopes as writable/resolved but does not mutate prepared part/layer/fx products.

### Note path

Direct ABI `F.synth_note_on`:

```text
borrow_published_program
  -> start_all_note_voices
  -> next_note_layer
  -> allocate_voice
  -> start_voice
```

MIDI note-on during render uses `apply_midi_event` and the same start voice helper.

Note-off/all-notes-off set `gate = false`, `stage = release`, and `release_frame`.

### Render ABI

`F.synth_render_block` takes:

- `s: ptr(Synth)`
- `events: view(HostEvent)`
- `ctx: RenderCtx`
- `scratch: ptr(RenderScratch)`
- `out_l/out_r: view(f32)`

It returns `i32` `AbiStatus`. Rendered, silent, and clipped all map to `0`. Requested program maps to `6` (`stale_handle`) in current implementation.

## Observations

- There is no UI-authored tree yet in the synth files. The existing source language is patch bytes (`PatchSource`) plus fixed section records.
- There is no parameter descriptor table with labels, display names, units, enum choices, UI grouping, automation flags, or widget hints.
- `ParamPolicy` contains numeric min/max/default/smoothing/read_only only.
- `ParamAddress` is purely numeric: scope + part/layer/bus/slot/param.
- `E.enc` tables are Lua-side documentation values and compile-time constants. They are not runtime metadata exposed through ABI.
- `PreparedProgram` is render-ready: parts/layers/effects/tuning views and refs. It is not an authoring representation.
- The spec explicitly says applying parameter values must not mutate immutable `PreparedProgram`; implementation only actually stores global macro values.
- `RenderPolicy.clear_outputs_first` and `smooth_block_events` exist in products, but the read implementation always clears output and processes events before render; only `retire_dead_voices_after_block` is visibly branched on in render finalization.
- Tests cover compileability of all ABI seals, header implementation completion, storage/init smoke, malformed patch mapping, event classification, voice lifecycle, silent render clearing, modulation, envelope/LFO/filter/effect/tone fidelity.
- Compiler-pattern docs frame UI as authored source products + event facts + pure apply + phase iterators + sealed render loop. This is directly relevant, but no such UI projection layer is present for Zyn yet.

## Knowledge-builder Output — 2026-06-14 04:35:50

### What Matters Most for This Problem

- **State ownership boundaries**: what belongs to immutable program products, mutable synth runtime state, UI interaction state, and host/UI projection state.
- **Contract preservation**: UI must remain compiler-shaped: authored tree → typed reports/events → application state → next authored tree; no hidden callbacks or stringly side channels.
- **Projection truthfulness**: UI controls must not imply writable, named, ranged, or persistent parameters unless the synth surface actually supports that.
- **ABI/event lossiness**: synth ABI status codes and `ParamAddress` are too coarse to serve as full UI semantics.
- **Identity stability**: UI IDs, synth refs/generations, and parameter addresses have different stability rules and can easily be conflated.
- **Runtime synchronization**: audio/render state, UI redraw cadence, meters, transport, and parameter events live on different timing axes.

### Non-Obvious Observations

- **`ParamAddress` is not a UI model.**  
  It is a numeric routing key into synth control logic. It carries no label, unit, display format, grouping, widget kind, enum choices, automation flags, or even reliable writability semantics beyond `resolve_parameter`. A UI projection that treats addresses as self-describing would necessarily invent meaning outside the ABI.

- **`ParamPolicy` is too weak to author controls safely.**  
  It only gives min/max/default/smoothing/read-only. It cannot distinguish logarithmic vs linear controls, bipolar controls, stepped/enumerated values, normalized-vs-physical units, or display precision. The current generic `[0,1]` policy for most scopes makes this especially risky: many controls would look valid while being semantically meaningless.

- **The synth currently advertises more writable parameter space than it mutates.**  
  `resolve_parameter` resolves most non-global scopes as writable, but `apply_parameter_event` only writes global macro values. A UI that projects part/layer/fx controls from addressability alone could show apparently editable controls whose ABI calls return `ok` but produce no observable state change.

- **`AbiStatus.ok` is lossy for UI feedback.**  
  The implementation maps changed, unchanged, smoothed, read-only, and out-of-range/clamped outcomes to `ok` in some paths. Therefore UI cannot infer “the user’s edit succeeded exactly as requested” from ABI status alone.

- **Read-only parameters need to affect UI authoring before interaction, not after ABI failure.**  
  Because read-only can collapse to `ok`, disabled/read-only widget state must be known at projection time. Otherwise the UI may allow interaction and then have no precise way to explain why the value did not change.

- **Prepared programs should be projected as immutable facts, not edited state.**  
  The spec says prepared products are immutable phase outputs. UI must not treat `PreparedProgram.parts`, effect plans, or tuning as mutable source-of-truth controls. Editable state currently lives in `ControlBank`, transport, selected program refs, and explicit host events.

- **Patch/source authoring and runtime control editing are different domains.**  
  `PatchSource` is host-owned bytes and `PreparedProgram` is render-ready output. There is no current authored patch tree in the synth. A UI-side projection cannot honestly provide deep patch editing unless an authored patch model exists outside the current ABI.

- **UI IDs and synth references have incompatible lifetime semantics.**  
  UI IDs must be globally unique and stable enough for focus/hover/input state. Synth refs include generations to detect stale native handles. Including generations in UI IDs may cause focus/state churn after program changes; excluding them risks routing UI events to stale parameter mappings if the projection cache is not invalidated correctly.

- **Parameter address identity is multidimensional and collision-prone in UI trees.**  
  `scope`, `part`, `layer`, `bus`, `slot`, and `param` all matter. Any abbreviated ID scheme risks collisions, especially with widget-generated child IDs and global authored-tree validation.

- **Meters are read-only runtime facts, not controls.**  
  `last_meter` should project differently from parameters. Meter widgets must reflect sampled synth output state and should not emit parameter writes. Their redraw cadence depends on audio/render progress, not normal pointer/key interaction.

- **Transport state is mutable synth state but not a parameter.**  
  It travels through `HostEvent.transport` / `Synth.transport`, not `ParamAddress`. Treating transport controls as ordinary parameters would blur event ownership and make frame/block semantics ambiguous.

- **UI semantic events and synth ABI events are not the same layer.**  
  Widget events like `change`, `activate`, `input`, `scroll`, `focus`, etc. are UI facts. Synth events like `ParameterEvent`, `MidiEvent`, and `HostEvent` are ABI/control facts. A projection layer must preserve that boundary; otherwise widget routing becomes coupled directly to native ABI mutation.

- **The UI contract forbids hiding behavior in widget callbacks.**  
  The existing UI architecture expects authored nodes, reducer reports, semantic events, and app-owned state updates. Direct FFI calls from widget constructors, route handlers, paint callbacks, or style resolution would violate the compiler-shaped loop.

- **Application state must bridge three different state kinds explicitly.**  
  There is synth state, UI interaction model state, and projection/view-model state. Hover/focus/active/drag/text-edit state belongs to UI interaction; parameter values/meters/transport belong to synth snapshots; labels/grouping/display belong to projection metadata. Mixing them will create invalidation bugs.

- **Text entry for numeric parameters has special state ownership pressure.**  
  Text widgets have caret/selection/IME state and a secondary rendering path. A numeric text-entry control cannot be modeled as “just a parameter value”; it also needs transient edit text, validation state, focus state, and commit/cancel semantics.

- **Keyboard interaction may not pass through widget-level raw key handling as expected.**  
  Some widgets contain `KeyPressed` routing branches, but the reducer generally emits higher-level events only for Tab/Return/Space/Escape. Arrow-key or fine-adjust parameter editing may fail unless the design accounts for what semantic events are actually produced.

- **Layer/modal/overlay report facts are currently less expressive than authored nodes.**  
  Runtime hardcodes or defaults some layer/focus/overlay information when constructing reports. Any synth UI depending on precise modal placement, overlay anchoring, or custom focus-scope policy may not get enough runtime feedback today.

- **Dynamic menus/dropdowns stress ID and focus invariants.**  
  Program selectors, part selectors, effect-slot menus, and parameter popovers will create conditional authored subtrees. If IDs change shape across open/close or program changes, focus, hover, text input, and drag state may be invalidated unexpectedly.

- **Audio-frame timing and UI-event timing do not naturally align.**  
  `HostEvent.frame` is meaningful inside render blocks. SDL/UI events occur on wall-clock/UI frames. Assigning frame values incorrectly can cause rejected events, block-edge jitter, or misleading automation semantics.

- **Render-path and non-render parameter application have different validation context.**  
  Render event handling can compare event frame to block length; non-render application cannot fully validate against `RenderCtx`. UI-originated parameter changes therefore need clear semantics about whether they are immediate state writes or scheduled render events.

- **Concurrency/lifetime hazards are likely around FFI snapshots.**  
  Synth structs contain pointers and views into host/native storage. UI-authored trees should not retain raw native pointers or views across program prepare, close, storage reuse, or generation changes. Projection probably needs snapshot semantics, but the key observation is that direct pointer projection is unsafe.

- **`ProgramRef.generation` and `Synth.generation` are different invalidation signals.**  
  Program refs use `u16` generations for program handles; `Synth.generation` is a broader lifecycle counter. UI caches that treat all generations as equivalent may either over-invalidate or miss stale-handle cases.

- **The encoding tables are not runtime metadata.**  
  `E.ParamScope`, `E.HostEventKind`, etc. are Lua documentation/constants with owner regions. UI code that treats them as extensible schema or discoverable runtime catalogs would violate the “one owner region” discipline.

- **The ABI boundary intentionally seals rich internal outcomes into integers.**  
  This is good for native boundary stability but bad for UI diagnostics. If UI needs precise failure reasons, the current ABI does not expose them. That limitation should be recognized rather than papered over with guesses.

- **The existing tests do not prove UI projection safety.**  
  They cover synth behavior and generic UI contracts separately, but not the composed loop: widget event → semantic UI event → parameter/control event → synth mutation → projected next tree.

- **A synth UI can easily become stringly despite typed internals.**  
  The danger point is mapping widget IDs/event names to `ParamAddress` and ABI calls. If that mapping lives in ad hoc strings, the UI may technically use `Auth.Node` while still violating the project’s explicit-ASDL philosophy at the projection boundary.

### Knowledge Gaps

- What authored metadata, if any, should define parameter labels, groups, units, display formatting, and widget hints?
- Which synth state is safe and intended to read from Lua/FFI for projection snapshots?
- What threading model is expected between SDL UI, LuaJIT FFI, and audio rendering?
- Are UI-originated parameter changes meant to call `synth_set_parameter` immediately, enqueue `HostEvent.parameter`, or both in different contexts?
- How should program changes invalidate UI focus, open menus, text edits, drag gestures, and cached parameter mappings?
- Should non-global parameter scopes become real mutable controls, or should the first UI only expose currently functional global macros?
- What redraw source should drive meters and transport display when there is no pointer/key input?

## Approach-proposer Output — 2026-06-14 04:36:33

### Approach A: Safe Performance-Panel Projection

- **Core idea**: Build a UI-owned, typed projection catalog for only the synth facts that are currently truthful and mutable: global macros, transport, meters, program selection, and note/control actions.

- **Key changes**:
  - Add a Lua-side Zyn UI projection module, e.g. `examples/synth/zyn_ui_projection.lua`.
  - Define typed Lua descriptor records for controls:
    - stable UI id
    - `ParamAddress`
    - label/group/widget hint/unit/display formatter
    - read-only flag
    - value source
  - Author UI trees using existing widgets: knob/slider/meter/toggle/menu/button.
  - Route widget semantic events into explicit UI commands:
    - `SetParameter(address, value)`
    - `SetTransport(state)`
    - `NoteOn/NoteOff`
    - `ProgramSelect`
  - Convert commands to `synth_set_parameter` or `HostEvent` outside widget constructors/routing.

- **Tradeoff**: Optimizes for correctness and contract safety; sacrifices deep patch/program editing and broad parameter coverage.

- **Risk**: The UI-owned metadata can drift from the synth unless kept deliberately small and tested against actual mutable behavior.

- **Rough sketch**:
  - Define a `ZynUi.Model` with:
    - UI interaction model
    - projection snapshot
    - open menus/editing state
    - pending synth commands
  - Sample synth facts into a plain snapshot:
    - current program ref
    - macro values
    - transport
    - `last_meter`
    - synth/program generations
  - Project snapshot + static descriptor catalog into `Auth.Node`.
  - Use widget bundle routing to produce semantic UI events.
  - Translate only approved events into typed synth commands, then into ABI calls or queued `HostEvent`s.
  - Invalidate descriptor bindings on program/synth generation changes, but keep stable UI IDs where possible to preserve focus.

---

### Approach B: Synth-Declared Parameter Schema Projection

- **Core idea**: Make the synth expose a real typed parameter/control schema, then let the UI projection derive controls from synth-declared metadata instead of hand-authored UI tables.

- **Key changes**:
  - Extend synth headers with metadata/product types such as:
    - `ParamDescriptor`
    - `ParamGroup`
    - `ParamDisplay`
    - `ParamWidgetHint`
    - `ParamValueKind`
  - Add ABI/query functions or host-readable views:
    - enumerate descriptors for current program
    - query current value/policy
    - maybe query read-only/writable state precisely
  - Change `resolve_parameter`/`apply_parameter_event` so writable declared parameters actually mutate real runtime control state.
  - Add a projection layer that turns descriptor views into widget bundles.
  - Add tests for descriptor → widget → parameter event → synth mutation → next snapshot.

- **Tradeoff**: Optimizes for truthful, scalable, program-aware UI generation; sacrifices implementation simplicity because the synth ABI/control model must grow.

- **Risk**: If descriptor metadata and actual parameter mutation are implemented by separate paths, the UI can still advertise controls that do not really work.

- **Rough sketch**:
  - Add synth-owned parameter metadata as compiler-shaped products, not ad hoc Lua strings.
  - During program preparation or synth init, produce descriptor tables for global/part/layer/fx controls.
  - Expose descriptors through safe snapshot/query APIs, not raw long-lived pointers.
  - UI projection maps each descriptor to a stable full-address UI id:
    - scope/part/layer/bus/slot/param
    - separate generation guard in binding table, not necessarily in visible UI id.
  - Widget events produce typed `ParameterEdit` facts.
  - A command reducer validates against descriptor/policy, emits `ParameterEvent`, applies through render queue or immediate ABI path.
  - Program generation changes invalidate descriptor snapshots and close/repair menus, drags, and text edits.

---

### Approach C: Host-Side Authored Patch/Program Editor Projection

- **Core idea**: Introduce a separate host-owned authored patch/program model, and make the UI edit that source model; the synth receives compiled `PatchSource`/prepared programs only on publish or preview.

- **Key changes**:
  - Add an authored Zyn patch model on the Lua/UI side:
    - parts
    - layers
    - oscillators/tone plans
    - envelopes
    - LFOs
    - filters
    - effects
    - modulation routes
  - Add a compiler/serializer from authored patch model to existing Zyn patch bytes / `PatchSource`.
  - UI projection authors trees from the patch model plus runtime snapshot.
  - Distinguish edit commands from runtime commands:
    - `EditPatchField`
    - `AddLayer`
    - `SetEnvelopePoint`
    - `SetModRoute`
    - `PublishProgram`
    - `SetPerformanceMacro`
  - Keep `PreparedProgram` immutable and replace it only via prepare/publish.

- **Tradeoff**: Optimizes for full patch-editing power and clean source/product separation; sacrifices immediacy and requires a substantial authored patch schema plus compiler.

- **Risk**: The authored patch model can become a second synth language that diverges from the existing binary patch format and prepared-program semantics.

- **Rough sketch**:
  - Define a typed Lua-side `PatchAuth` tree separate from native `PreparedProgram`.
  - Build UI pages from `PatchAuth`:
    - program browser
    - part/layer editor
    - modulation matrix
    - FX racks
    - envelope/LFO editors
  - UI events mutate `PatchAuth` through a pure reducer.
  - On commit/publish, serialize `PatchAuth` to `PatchSource` and call `synth_prepare_program`.
  - Runtime controls remain separate:
    - meters read from synth snapshot
    - transport from synth state
    - live macros via `ParameterEvent`
  - Invalidation is coarse:
    - patch edit changes invalidate affected authored subtree
    - publish changes program generation and refreshes runtime bindings
    - failed publish keeps previous prepared program active.

---

### Comparison

- **Approach A** is a conservative live-performance UI: safest now, limited to controls the current synth can honestly support.
- **Approach B** is a generated parameter UI: best when the synth itself should declare a broad, truthful control surface.
- **Approach C** is a full editor architecture: best when the goal is patch/program authoring, with runtime synth state treated as compiled output plus live performance facts.

## Critique Output — 2026-06-14 04:37:13

Scoring note: for **Coupling / Migration cost / Risk**, higher means worse. For **Cohesion / Philosophy fit / Testability**, higher means better.

### Approach A: Safe Performance-Panel Projection

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | Keeps UI projection, widget routing, and synth ABI mutation separated through explicit commands. Some coupling remains in the hand-authored descriptor catalog. |
| **Cohesion** | 5/5 | Clean split between snapshot sampling, UI-authored tree projection, semantic UI events, and synth command emission. |
| **Migration cost** | 1/5 | Mostly additive. Does not require changing synth ABI, parameter resolver, patch format, or UI kernel contracts. |
| **Philosophy fit** | 5/5 | Best immediate fit with Lalin/UI principles: authored tree in, typed semantic events out, app-owned state update, no callbacks or stringly ABI shortcuts. |
| **Risk** | 2/5 | Main risk is metadata drift, but the small truthful surface makes this manageable. Avoids pretending the current broad parameter space is actually mutable. |
| **Testability** | 5/5 | Highly incremental: fake snapshots, widget events, command translation, and ABI smoke tests can be validated independently. |

**Verdict**: Strong yes  
**Key concern**: Keep the catalog deliberately narrow and prove every exposed control maps to real mutable synth state.

---

### Approach B: Synth-Declared Parameter Schema Projection

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Couples UI generation to synth-declared metadata, but in a principled way. The risk is tight dependence between descriptor schema, ABI query APIs, and actual mutation semantics. |
| **Cohesion** | 4/5 | Strong conceptual cohesion if descriptors, values, policies, and mutation are owned by the synth. Cohesion fails if metadata and behavior are maintained separately. |
| **Migration cost** | 4/5 | Requires new synth product/schema types, ABI/query surface, descriptor snapshots, and real implementation of currently fake-writable parameter scopes. |
| **Philosophy fit** | 5/5 | Very strong fit if descriptors are compiler-shaped products rather than Lua side tables. Aligns with typed facts, owner regions, and generated projections. |
| **Risk** | 4/5 | High correctness risk until parameter mutability, read-only state, display semantics, and ABI outcomes become truthful. Current `resolve_parameter` already over-advertises writability. |
| **Testability** | 3/5 | Testable, but only after significant synth-surface work. Requires end-to-end tests from descriptor → widget → event → mutation → snapshot. |

**Verdict**: Yes with caveats  
**Key concern**: The synth-declared schema must be the same truth source as parameter mutation; otherwise the UI will become beautifully typed but semantically dishonest.

---

### Approach C: Host-Side Authored Patch/Program Editor Projection

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Decouples UI editing from immutable `PreparedProgram`, but introduces a new host-authored patch language that must stay aligned with synth patch bytes and preparation semantics. |
| **Cohesion** | 4/5 | Clean source/product separation: edit authored patch state, compile to `PatchSource`, publish to synth. Runtime controls remain separate. |
| **Migration cost** | 5/5 | Largest change by far: authored patch schema, serializer/compiler, editor pages, publish/preview flow, validation, and divergence management. |
| **Philosophy fit** | 4/5 | Architecturally compatible with Lalin’s source → phase → product model, but only if the patch authoring model is typed and explicit rather than an ad hoc Lua object graph. |
| **Risk** | 5/5 | Very high. The authored model can diverge from the binary patch format, prepared-program behavior, and live runtime controls. Also much broader UI/state invalidation surface. |
| **Testability** | 2/5 | Hard to validate incrementally without first defining the whole patch authoring schema and compiler boundary. Many failure modes are semantic, not just structural. |

**Verdict**: Significant concerns  
**Key concern**: Prevent the host-authored patch model from becoming a second, drifting synth language.

---

### Summary

- **Recommended**: **Approach A**, likely as the first stage. It is the only option that is immediately truthful against the current synth implementation while preserving the compiler-shaped UI contract.
- **Dark horse**: **Approach B**. It has the best long-term upside for scalable generated control surfaces, but only after the synth owns truthful parameter descriptors and real mutation semantics.
- **Avoid**: **Approach C** for now. It is architecturally valid in principle, but too large and too divergence-prone before the runtime/performance projection and parameter schema are stabilized.

## Approach-proposer Output — 2026-06-14 04:40:09

### Approach A: Synth-Owned Control Surface ABI

- **Core idea**: The synth owns all UI-visible control metadata and exposes immutable descriptor snapshots plus value snapshots; the UI is a typed projection/rendering layer over synth-declared facts.

- **Key changes**:
  - Add synth-level types such as `ControlDescriptor`, `ControlGroup`, `ControlValueKind`, `ControlWidgetHint`, `ControlBinding`, `ControlSnapshot`.
  - Extend the Zyn ABI with safe snapshot/query functions that copy descriptor/value data into host-owned buffers.
  - Make `resolve_parameter`, `apply_parameter_event`, and descriptors share the same truth source.
  - Treat `PreparedProgram` as immutable phase output; descriptors may be derived from it, but UI never mutates it directly.
  - UI IDs derive from full descriptor identity:
    - stable control id / scope / part / layer / bus / slot / param
    - generations live in binding epochs, not in user-facing IDs.
  - Widget events lower into typed `SynthCommand` values:
    - `SetParameter`
    - `SetTransport`
    - `ProgramChange`
    - `NoteOn`
    - `NoteOff`
  - Snapshots are copied Lua-owned/plain structs, never retained raw native pointers or `view(...)` handles.

- **Tradeoff**: Optimizes for truthfulness and long-term generated UI coverage; sacrifices fast implementation because the synth ABI and parameter implementation must become real.

- **Risk**: If descriptors and mutation semantics drift, the UI becomes formally typed but semantically dishonest.

- **Rough sketch**:
  - Define synth-owned descriptor structs in `examples/synth/zyn_lalin_synth_headers.mlua`.
  - Generate/control descriptors during synth init or program preparation.
  - Add ABI calls like:
    - `synth_control_descriptor_count`
    - `synth_copy_control_descriptors`
    - `synth_copy_control_snapshot`
  - UI projection builds authored widget trees from descriptors + copied values.
  - UI reducer emits semantic widget events, then an app reducer translates them into typed synth commands.
  - Commands are applied via immediate ABI calls or queued `HostEvent`s, depending on timing semantics.
  - Program/synth generation changes invalidate bindings but preserve focus where descriptor identity remains stable.

---

### Approach B: Authored Patch Tree as Source of Truth

- **Core idea**: Introduce a typed host-side authored patch/program model, make the UI edit that source tree, and treat `PreparedProgram` as a compiled product.

- **Key changes**:
  - Add a `PatchAuth` / `ProgramAuth` model containing parts, layers, envelopes, LFOs, filters, FX, modulation routes, macros, and display metadata.
  - UI-visible parameter metadata lives on the authored patch schema, not in `ParamAddress`.
  - Add validation/lowering/serialization from `PatchAuth` to existing `PatchSource`.
  - `PreparedProgram` remains immutable and is only replaced by calling `synth_prepare_program`.
  - UI IDs derive from authored patch node identity/path:
    - `program.parts[0].layers[1].filter.cutoff`
    - plus stable node ids for dynamic lists.
  - Program generations are binding guards after publish, not primary UI identity.
  - Semantic UI events become typed edit commands:
    - `EditPatchField`
    - `AddLayer`
    - `RemoveModRoute`
    - `SetEnvelopePoint`
    - `PublishProgram`
    - `PreviewChange`
  - Runtime commands remain separate:
    - `SetTransport`
    - `SetPerformanceMacro`
    - `NoteOn`
    - `NoteOff`.

- **Tradeoff**: Optimizes for a real editor architecture and clean source/product separation; sacrifices simplicity and requires defining a full authored patch language.

- **Risk**: The authored patch model can diverge from the binary patch format or synth preparation semantics unless the compiler/serializer is heavily tested.

- **Rough sketch**:
  - Define typed Lua/ASDL-like patch authoring records.
  - Build UI trees from `PatchAuth + RuntimeSnapshot`.
  - Use pure reducers for UI events → patch edit commands → next `PatchAuth`.
  - On publish, validate and serialize `PatchAuth` to `PatchSource`.
  - Call `synth_prepare_program`; if it succeeds, update `ProgramRef`/generation bindings.
  - Runtime snapshots copy only safe facts: current program ref, meters, transport, macro/control values.
  - Never retain native prepared-program pointers in UI state.

---

### Approach C: Shared Projection Schema Compiler

- **Core idea**: Create a shared typed control/projection schema that generates both synth control plumbing and UI projection metadata, preventing drift by construction.

- **Key changes**:
  - Add a canonical schema module, e.g. `examples/synth/zyn_control_surface.lua` or `.mlua`.
  - The schema defines:
    - control ids
    - groups/pages
    - value kinds
    - units/display formatting
    - widget hints
    - patch-field bindings
    - runtime-parameter bindings
    - meter bindings
    - command bindings.
  - Generate or derive:
    - synth parameter descriptors
    - `resolve_parameter`
    - `apply_parameter_event`
    - UI descriptor catalog
    - snapshot extraction rules
    - command lowering tables/tests.
  - `PreparedProgram` is one compiled product of schema-backed authored/program state.
  - The schema explicitly distinguishes:
    - authored patch fields
    - immutable prepared products
    - mutable runtime controls
    - read-only runtime facts.
  - UI IDs derive from schema ids plus instance keys:
    - control id + part/layer/fx slot
    - generations are stored only in binding epochs.
  - UI events lower to `ControlIntent` values:
    - `SetRuntimeParam`
    - `EditPatchField`
    - `PublishPatch`
    - `SetTransport`
    - `TriggerNote`
    - `SelectProgram`.

- **Tradeoff**: Optimizes for consistency across synth, UI, tests, and future editors; sacrifices directness by introducing a new schema/compiler layer.

- **Risk**: The projection schema can become a large meta-language if not kept disciplined and generated artifacts may obscure ownership boundaries.

- **Rough sketch**:
  - Define a small typed schema vocabulary for controls, groups, patch fields, commands, and meters.
  - Generate full-address parameter bindings from schema nodes.
  - Generate UI projection descriptors from the same schema.
  - Generate tests proving every declared writable runtime control mutates observable state.
  - UI projection consumes:
    - schema descriptors
    - copied runtime snapshots
    - authored patch state.
  - Reducers turn widget events into typed `ControlIntent`s.
  - A command compiler lowers each intent into patch edits, ABI calls, or render-queued `HostEvent`s.
  - Snapshot extractors copy native state into generation-stamped host-owned tables.

---

### Comparison

- Pick **Approach A** if the synth should be the canonical owner of live control metadata and the UI should reflect whatever the current prepared program exposes.
- Pick **Approach B** if the product goal is a real patch/program editor where authored source state matters more than native runtime descriptors.
- Pick **Approach C** if the project wants one canonical typed schema that drives synth behavior, UI metadata, command lowering, and tests together.

All three avoid the temporary-panel trap: each makes a foundational decision about metadata ownership, authored state, identity, events, snapshots, and compiler-shaped projection.

## Critique Output — 2026-06-14 04:40:49

### Approach A: Synth-Owned Control Surface ABI

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | UI becomes coupled to synth descriptor ABI, but that coupling is legitimate if the synth owns live runtime controls. |
| **Cohesion** | 4/5 | Strong for performance/runtime controls: descriptors, values, policies, and mutation can live under one synth-owned truth source. Weaker for authored patch editing. |
| **Migration cost** | 4/5 | Requires real descriptor structs, copy/snapshot ABI, value queries, and fixing current fake-writable parameter behavior. |
| **Philosophy fit** | 4/5 | Fits typed facts and ABI sealing well, but risks making the synth ABI carry UI-ish display concerns unless ownership is disciplined. |
| **Risk** | 3/5 | The central danger is descriptor/mutation drift. If `resolve_parameter` says writable but mutation is still partial, the architecture lies. |
| **Testability** | 4/5 | Can be validated with descriptor → command → ABI mutation → snapshot tests, but only after meaningful synth changes. |

**Verdict**: Yes with caveats  
**Key concern**: This must not become “better metadata over the same fake parameter surface.” The synth must make declared controls actually mutable and observable.

---

### Approach B: Authored Patch Tree as Source of Truth

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Decouples UI from `PreparedProgram`, but couples the host editor model tightly to patch serialization and synth preparation semantics. |
| **Cohesion** | 4/5 | Excellent source/product split: edit authored source, compile/publish to synth product. Runtime controls remain separate. |
| **Migration cost** | 5/5 | Very large: new authored patch schema, serializer/lowering, validation, editor state, publish/preview semantics. |
| **Philosophy fit** | 5/5 | Deeply Lalin-shaped if implemented as explicit typed source → compiler phases → prepared product. |
| **Risk** | 5/5 | Highest divergence risk. The authored patch model can become a second Zyn language that only approximately matches binary patch bytes and prepared-program behavior. |
| **Testability** | 2/5 | Hard to test meaningfully until the authored schema and compiler boundary exist. Many bugs will be semantic, not structural. |

**Verdict**: Significant concerns  
**Key concern**: This is only correct if the project is committing now to a full patch-authoring language. Otherwise it is grand architecture as deferral.

---

### Approach C: Shared Projection Schema Compiler

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Intentionally couples synth control plumbing, UI metadata, command lowering, and tests through one canonical schema. That is powerful but dangerous. |
| **Cohesion** | 5/5 | Best conceptual cohesion: one typed source describes authored fields, runtime parameters, meters, commands, and projection identity. |
| **Migration cost** | 5/5 | Highest practical cost. It introduces a new schema/compiler layer and generated/derived artifacts across synth and UI. |
| **Philosophy fit** | 5/5 | Best Lalin fit if the schema is a real typed source product, not a loose Lua table convention. It embraces compiler-shaped projection instead of bolting UI metadata on afterward. |
| **Risk** | 4/5 | Meta-language creep is the major risk. If undisciplined, it becomes an opaque framework that hides ownership instead of clarifying it. |
| **Testability** | 4/5 | Strong upside: schema can generate tests proving every writable control has descriptor, binding, command lowering, and observable mutation. Initial bootstrap is nontrivial. |

**Verdict**: Strong yes, but only as an explicit foundational commitment  
**Key concern**: Keep the schema small, typed, and ownership-oriented. It must describe real control facts, not become a decorative UI DSL.

---

### Summary

- **Recommended**: **Approach C: Shared Projection Schema Compiler**.  
  This is the real architectural choice. It accepts that Zyn needs a canonical typed control/projection source, not a temporary UI catalog and not two drifting worlds. It best matches Lalin’s philosophy: explicit source facts, generated/derived phase products, typed command lowering, and testable ownership boundaries.

- **Dark horse**: **Approach A**.  
  If the immediate product scope is strictly live synth control, A is cleaner and cheaper. But it risks lazy deferral of the deeper authored/control schema decision. It is acceptable only if the project is explicitly choosing “synth-owned runtime controls” as the long-term source of truth.

- **Avoid**: **Approach B** as the first foundation.  
  It is philosophically clean, but too broad and too likely to create a second Zyn language before runtime controls, parameter truth, and UI projection identity are stabilized.

Bluntly: pick **C** if the goal is a durable Zyn synth/UI architecture. Pick **A** only if the product is a runtime control surface. Do not pretend B is “just the editor version later”; it is a separate language-design commitment.

## Documenter Output — 2026-06-14 04:44:52

# Architecture Decision: Zyn Synth UI-Side Projection

**Status:** Approved  
**Decision:** Build a shared typed projection/control schema compiler as the canonical source of UI-visible Zyn synth control facts.

## Goal

Enable the Zyn Lalin synth UI to project synth/program/control state into typed authored UI trees, semantic widget events, and ABI/control events through a shared compiler-shaped schema, without violating Lalin’s UI contract or inventing ad hoc UI metadata outside the synth/control architecture.

## Problem

The Zyn synth currently exposes a native control and ABI surface, but it does not expose enough truthful, typed information to safely generate a real UI control surface.

The UI side needs to know:

- what controls exist,
- how they are grouped,
- how they should be displayed,
- whether they are writable,
- what runtime state they read/write,
- how UI events lower into synth commands,
- how identities remain stable across program and synth generation changes.

Today, those facts are split or missing. `ParamAddress` is only a numeric routing key. `ParamPolicy` only contains numeric range/default/smoothing/read-only. The current synth implementation resolves many non-global parameter scopes as writable, but only global macro parameters actually mutate `ControlBank.macro_values`. The UI cannot truthfully infer labels, units, widget types, value kinds, grouping, or observability from the ABI alone.

At the same time, Lalin’s UI architecture is explicitly compiler-shaped:

```text
Auth.Node
  -> lower.root / lower.phase
  -> Layout.Node
  -> render.root
  -> View.Op[]
  -> runtime.run(...)
  -> Interact.Report
  -> interact.step(...)
  -> semantic Interact.Event[]
  -> application state update
  -> next Auth.Node
```

A Zyn UI projection must preserve that shape. It must not hide behavior in widget callbacks, stringly IDs, direct FFI calls from widget constructors, or mutable side tables.

## Incentives

This matters because the obvious quick path would create a dishonest or fragile UI.

Specific current pain points:

- `ParamAddress` has no UI semantics: no labels, units, display format, grouping, widget hints, enum choices, or automation flags.
- `ParamPolicy` is too weak to author controls safely. It cannot distinguish linear/logarithmic, normalized/physical, bipolar, stepped, enum, or textual values.
- `resolve_parameter` currently advertises broad writable parameter space, while `apply_parameter_event` only mutates global macro values.
- `AbiStatus.ok` is lossy: changed, unchanged, clamped, smoothed, or read-only outcomes may collapse to `ok`.
- `PreparedProgram` is immutable render-ready product state, not an editable UI source model.
- UI IDs, synth refs, `ProgramRef.generation`, and `Synth.generation` have different lifetime rules and must not be conflated.
- FFI/native structs contain pointers and views that must not be retained in UI-authored trees or long-lived Lua state.
- Existing tests cover synth ABI behavior and generic UI contracts separately, but not the composed projection loop from widget event to synth mutation to next projected UI tree.

The approved architecture addresses these by making UI-visible control facts explicit, typed, generated/derived, and testable.

## Current State

### UI kernel

The UI system lives under `lua/ui/`.

Important files:

- `lua/ui/CONTRACT.md`
- `lua/ui/BACKEND_CONTRACT.md`
- `lua/ui/asdl.lua`
- `lua/ui/build.lua`
- `lua/ui/lower.lua`
- `lua/ui/render.lua`
- `lua/ui/runtime.lua`
- `lua/ui/interact.lua`
- `lua/ui/widget.lua`
- `lua/ui/widgets/*`

The core contract is:

```text
Auth.Node
  -> Layout.Node
  -> View.Op[]
  -> Interact.Report
  -> Interact.Event[]
  -> next Auth.Node
```

The authored tree is explicit ASDL-shaped UI data. Widgets produce authored nodes plus routing metadata. The interaction reducer consumes typed raw input and runtime reports, then emits semantic UI events such as activation, focus, hover, text input, drag, and scroll.

The UI system already has useful widgets for synth-like interfaces: sliders, knobs, meters, menus, buttons, toggles, canvas, text input, and value-drag style controls. However, there is currently no Zyn-specific projection module or synth demo.

### Widget event boundary

`lua/ui/widget.lua` defines widget bundles roughly shaped as:

```lua
{
  kind = spec.kind,
  id = id,
  node = spec.node,
  surfaces = spec.surfaces or {},
  model = spec.model,
  events = spec.events or {},
  route_ui_event = function(self, ui_event) ... end,
  route_ui_events = function(self, ui_events) ... end,
}
```

Widget routing maps low-level semantic UI events into widget-level events such as:

- `activate`
- `change`
- `input`
- `edit`
- `focus`
- `blur`
- `select`
- `scroll`
- `open`
- `close`
- drag events

The application, not the widget constructor, owns state mutation and external effects. For the Zyn UI, this means widget events must lower into typed synth commands before any ABI call or render-event enqueue happens.

### Synth ABI and runtime state

The Zyn synth surface is defined primarily in:

- `examples/synth/zyn_lalin_synth_headers.mlua`
- `examples/synth/zyn_lalin_synth_impl.mlua`
- `examples/synth/zyn_lalin_synth_spec.md`
- `tests/test_zyn_lalin_synth_impl.lua`

Key public types include:

```lalin
T.ParamAddress = struct
    scope: u8,
    part: u16,
    layer: u16,
    bus: u16,
    slot: u16,
    param: u16,
end

T.ParamPolicy = struct
    min_value: f32,
    max_value: f32,
    default_value: f32,
    smoothing_ms: f32,
    read_only: bool,
end

T.ParameterEvent = struct
    address: ParamAddress,
    value: f32,
    frame: index,
end

T.HostEvent = struct
    kind: u8,
    midi: MidiEvent,
    parameter: ParameterEvent,
    program: ProgramRef,
    transport: TransportState,
    frame: index,
end
```

Persistent runtime state is rooted at:

```lalin
T.Synth = struct
    current_program: ProgramRef,
    storage: SynthStorage,
    policy: EnginePolicy,
    transport: TransportState,
    last_meter: MeterFrame,
    generation: u64,
end
```

`Synth.storage` owns the `ProgramStore`, `VoicePool`, `ControlBank`, `PadCache`, and `EffectRack`.

### Prepared program boundary

`PreparedProgram` is immutable render-ready product state:

```lalin
T.PreparedProgram = struct
    parts: view(PartPlan),
    part_count: index,
    effects: EffectGraphPlan,
    tuning: TuningTable,
    generation: u16,
end
```

The spec explicitly treats prepared programs as phase outputs. UI code must not mutate them directly. Runtime controls and authored patch fields are separate concepts.

### Current parameter implementation tension

`R.resolve_parameter` currently returns a generic writable `[0,1]` policy for most known scopes, but actual mutation is narrow:

```lalin
if controls ~= nil
   and ev.address.scope == @{PARAM_SCOPE_GLOBAL}
   and as(index, ev.address.param) < (*controls).macro_count then
    controls[0].macro_values[as(index, ev.address.param)] = clamped
end
```

This means a UI generated directly from `ParamAddress` or `resolve_parameter` would show controls that appear writable but may have no observable effect.

That mismatch is the central correctness problem this decision addresses.

## Rejected Trap

The rejected trap is a temporary performance panel or ad hoc Lua metadata table that hand-authors UI facts separately from synth/control behavior.

That trap would look superficially safe because it could expose only a small number of controls at first, but it would establish the wrong source of truth:

- UI-visible labels and widget hints would live in Lua-only tables.
- Parameter mutation behavior would live in Lalin synth code.
- Command lowering would live in separate handwritten routing logic.
- Tests would need to prove consistency after the fact.
- The architecture would be vulnerable to schema drift as soon as more controls, pages, patch fields, meters, or program-specific controls are added.

The approved design does not use a throwaway catalog as the foundation. It introduces one shared typed projection/control schema that drives both sides.

## Chosen Target

### Approach

The approved approach is the **Shared Projection Schema Compiler**.

The Zyn control/projection schema becomes the canonical source for UI-visible synth control facts. The schema is not a decorative UI DSL and not an informal Lua table. It is a typed source product that describes real control facts and from which the implementation derives synth bindings, UI descriptors, command lowering, snapshot extraction, and tests.

The schema explicitly distinguishes:

- authored patch fields,
- immutable prepared products,
- mutable runtime controls,
- read-only runtime facts,
- meters,
- transport state,
- program selection,
- note/control actions.

### Chosen source of truth

The canonical source of truth is a shared typed schema module, conceptually located near the synth example, for example:

```text
examples/synth/zyn_control_surface.lua
```

or, if implemented in Lalin-shaped source form:

```text
examples/synth/zyn_control_surface.mlua
```

The exact file layout is implementation work, but the architectural role is fixed: this schema is the source from which both synth-side and UI-side artifacts are derived.

The schema owns stable logical facts such as:

- control IDs,
- control groups/pages,
- value kinds,
- units,
- display formatting policy,
- widget hints,
- runtime parameter bindings,
- authored patch field bindings,
- meter bindings,
- transport bindings,
- command bindings,
- read/write classification,
- instance dimensions such as part/layer/fx slot where applicable.

### Schema responsibilities

The schema must describe real control facts, not just UI decoration.

It is responsible for defining:

| Responsibility | Meaning |
|---|---|
| Control identity | Stable logical control IDs plus instance keys such as part/layer/slot. |
| Grouping | Pages, sections, panels, or groups used to author the UI tree. |
| Value kind | Float, normalized float, bipolar, stepped, enum, boolean, text, meter, etc. |
| Display policy | Unit, precision, labels, formatting behavior. |
| Widget hint | Knob, slider, meter, toggle, menu, text input, canvas, etc. |
| Binding | Whether the control maps to runtime parameter state, authored patch state, meter state, transport, notes, or program selection. |
| Mutability | Writable, read-only, derived, or command-only. |
| Command lowering | How semantic UI events become typed synth/control intents. |
| Snapshot extraction | How current values are copied into host/UI-owned snapshots. |
| Tests | What must be proven for each declared writable or observable fact. |

The schema compiler derives artifacts rather than relying on independently maintained duplicates.

Expected derived artifacts include:

- synth parameter descriptors,
- `resolve_parameter` behavior,
- `apply_parameter_event` behavior for runtime-bound controls,
- UI projection descriptors,
- snapshot extraction rules,
- command lowering tables,
- tests proving descriptor/binding/mutation consistency.

### Architecture

The target architecture has five explicit layers.

#### 1. Schema source

The schema declares typed control facts.

Conceptual vocabulary:

```lua
ControlSurface
ControlGroup
ControlDescriptor
ControlBinding
ControlValueKind
ControlWidgetHint
ControlIntent
MeterBinding
PatchFieldBinding
RuntimeParamBinding
TransportBinding
ProgramBinding
```

These names are representative of the approved design vocabulary. The important requirement is that the schema has typed records for these concepts rather than stringly side tables.

#### 2. Derived synth/control products

From the schema, synth-facing artifacts are generated or derived:

- parameter descriptor data,
- full-address runtime bindings,
- `ParamAddress` mappings,
- `resolve_parameter` cases,
- `apply_parameter_event` mutation paths,
- read-only and range policy behavior,
- meter/value snapshot extraction,
- test fixtures.

This prevents the current failure mode where `resolve_parameter` advertises writable space that `apply_parameter_event` does not actually mutate.

For every declared writable runtime control, there must be one shared truth path:

```text
schema control
  -> descriptor
  -> parameter address / binding
  -> resolve policy
  -> apply mutation
  -> observable snapshot value
```

#### 3. Snapshot products

The UI must consume copied snapshots, not raw native pointers or long-lived `view(...)` handles.

A snapshot contains plain host-owned values such as:

- current program ref,
- program generation,
- synth generation,
- control values,
- meter values,
- transport state,
- descriptor/binding epoch,
- read-only/value policy facts needed to author disabled state.

Snapshots are copied at safe synchronization points. UI-authored trees may retain snapshot values, but not raw native memory.

#### 4. UI projection

The UI projection consumes:

```text
schema-derived UI descriptors
+ copied runtime snapshot
+ UI interaction model
+ app projection state
```

and produces an authored UI tree:

```text
Auth.Node
```

The projection uses existing UI builders and widgets from `lua/ui/`, preserving the standard UI compiler pipeline:

```text
Auth.Node
  -> lower.root
  -> Layout.Node
  -> render.root
  -> View.Op[]
  -> runtime.run
  -> Interact.Report
  -> interact.step
  -> Interact.Event[]
```

Widget event routing remains semantic. Widgets do not call synth ABI functions directly.

#### 5. Command compiler

Semantic widget events lower into typed control intents, for example:

```text
SetRuntimeParam
EditPatchField
PublishPatch
SetTransport
TriggerNote
SelectProgram
```

Those intents are then compiled into the appropriate effect:

- immediate ABI call,
- render-queued `HostEvent`,
- patch-authored state edit,
- publish/prepare action,
- local UI/app state transition.

The command compiler owns this lowering boundary. It is the only place where UI-level events become synth/control operations.

## Source/Product Boundaries

The architecture preserves Lalin’s source/product discipline.

### Authored UI tree

`Auth.Node` is a UI product authored from schema descriptors, snapshots, and UI/application state. It is not a place to hide synth effects.

### Schema

The shared projection/control schema is source. It defines control facts and derives products.

### Runtime synth state

`Synth`, `ControlBank`, `TransportState`, `MeterFrame`, and related mutable state are runtime state. They can be observed through copied snapshots and mutated through typed commands/ABI paths.

### PreparedProgram

`PreparedProgram` is immutable compiled product state. It may inform descriptors or instance availability, but the UI never edits it directly.

### Authored patch fields

Authored patch fields are distinct from runtime controls. A schema item may bind to a patch field, but edits to that field are source edits, not mutations of `PreparedProgram`.

Publishing patch edits remains a compile/prepare step:

```text
authored patch state
  -> validation/lowering/serialization
  -> PatchSource
  -> synth_prepare_program
  -> PreparedProgram
```

Runtime controls remain separate:

```text
UI event
  -> ControlIntent.SetRuntimeParam
  -> ParameterEvent / HostEvent
  -> mutable runtime state
```

## Identity and Generation Policy

UI identity, synth references, and native generations have different roles.

### UI IDs

UI IDs must be globally unique within an authored tree and stable enough to preserve hover, focus, drag, text editing, and open-menu state.

UI IDs derive from schema control identity plus instance keys, for example:

```text
control-id + part-index + layer-index + bus + slot
```

They must include the full multidimensional identity needed to avoid collisions. Abbreviated IDs are unsafe because `ParamAddress` identity includes:

```text
scope, part, layer, bus, slot, param
```

### Generations

Generations are binding guards, not primary UI identity.

Relevant generations include:

- `ProgramRef.generation`
- `Synth.generation`
- descriptor/binding epoch derived from the schema/snapshot layer

Including generations directly in visible UI IDs would cause unnecessary focus and interaction churn after program changes. Excluding them entirely would risk routing events through stale bindings.

Therefore:

```text
stable UI ID
+ separate binding epoch/generation guard
```

is the chosen policy.

On generation or descriptor epoch changes:

- stale bindings are invalidated,
- command lowering refuses outdated control bindings,
- menus, drags, or text edits may be repaired or closed according to app rules,
- focus is preserved where the logical descriptor identity remains valid.

## Snapshot and Lifetime Policy

UI projection must not retain raw native pointers, `view(...)` handles, or borrowed synth storage across frames, program prepares, synth close, storage reuse, or generation changes.

The snapshot policy is:

```text
native synth/runtime state
  -> safe copy/query boundary
  -> host/UI-owned plain snapshot
  -> UI projection
```

Snapshots must be generation-stamped. The UI may store snapshot values and descriptor copies, but must treat them as immutable facts for a projection pass.

This avoids hazards from:

- `PreparedProgram` views,
- `SynthStorage` pointer ownership,
- `ControlBank` arrays,
- program publication,
- stale handles,
- synth lifecycle changes,
- concurrent render/UI timing.

Meters are read-only runtime facts. They are sampled from `Synth.last_meter` or a derived snapshot path and projected into meter widgets. They do not emit parameter writes.

Transport is mutable runtime state, but it is not a parameter. It travels through transport-specific commands/events rather than `ParamAddress`.

## Event and Command Flow

The approved flow is:

```text
copied snapshot + schema descriptors + UI state
  -> project authored tree
  -> UI lower/render/runtime/interact pipeline
  -> semantic UI/widget events
  -> typed ControlIntent values
  -> command compiler
  -> ABI call, HostEvent queue, patch edit, or app-state update
  -> next snapshot
  -> next authored tree
```

Expanded:

```text
Auth.Node
  -> Layout.Node
  -> View.Op[]
  -> Interact.Report
  -> Interact.Event[]
  -> widget route_ui_events
  -> widget events
  -> ControlIntent
  -> SynthCommand / PatchEdit / AppTransition
```

No widget constructor, paint callback, style resolver, or widget route handler directly mutates the synth.

### Runtime parameter command

```text
widget change
  -> ControlIntent.SetRuntimeParam(control_id, instance_key, value)
  -> validate descriptor epoch and mutability
  -> lower to ParamAddress / ParameterEvent
  -> synth_set_parameter or queued HostEvent.parameter
  -> copied snapshot confirms observable state
```

### Transport command

```text
widget activate/change
  -> ControlIntent.SetTransport(...)
  -> HostEvent.transport or transport-specific ABI path
  -> Synth.transport snapshot
```

### Meter display

```text
render/audio state
  -> MeterFrame snapshot
  -> read-only meter descriptor
  -> meter widget
```

No command is emitted from meter display.

### Patch field edit

```text
widget edit/change
  -> ControlIntent.EditPatchField(...)
  -> authored patch state update
  -> later publish/prepare path
```

Patch edits do not mutate `PreparedProgram` directly.

## Relation to `PreparedProgram` and Authored Patch Fields

`PreparedProgram` remains immutable. The UI may reflect facts derived from it, such as available parts, layers, effects, or program-specific descriptor instances, but it does not edit `PreparedProgram.parts`, `EffectGraphPlan`, or `TuningTable`.

The schema must mark whether a control is:

1. a runtime parameter,
2. an authored patch field,
3. a read-only runtime fact,
4. a command/action,
5. a meter,
6. transport/program selection state.

This distinction prevents the UI from treating all visible controls as `ParamAddress` writes.

For authored patch fields, the schema describes the source field and UI projection. Edits update authored patch state. Publication compiles/serializes that authored state to `PatchSource` and calls `synth_prepare_program`.

For runtime controls, the schema describes a mutable runtime binding. Edits lower to `ParameterEvent`, `HostEvent`, or direct ABI mutation according to timing semantics.

For prepared products, the schema may derive read-only display facts, but not write bindings.

## Testing Obligations

The architecture requires tests that prove consistency across schema, synth behavior, UI projection, and command lowering.

At minimum, tests must cover:

### Schema integrity

- every control ID is stable and unique,
- full instance identity avoids collisions,
- every descriptor has a valid binding kind,
- widget hints match value kinds,
- read-only facts cannot lower to write commands.

### Descriptor-to-synth consistency

For every declared writable runtime parameter:

```text
descriptor exists
-> binding exists
-> resolve_parameter returns matching policy
-> apply_parameter_event mutates intended state
-> copied snapshot observes the new value
```

This directly guards against the current fake-writable parameter problem.

### UI projection

- schema descriptors plus snapshots author valid `Auth.Node` trees,
- generated IDs pass `lua/ui/id.lua` validation,
- conditional pages/menus do not create ID collisions,
- disabled/read-only controls are authored disabled before interaction.

### Event lowering

- widget events produce typed `ControlIntent` values,
- stale descriptor epochs/generation guards reject outdated commands,
- command lowering does not depend on string parsing,
- no widget path directly calls ABI functions.

### Snapshot lifetime

- UI snapshots contain copies, not retained native pointers/views,
- program generation changes invalidate bindings,
- synth generation changes invalidate lifecycle-sensitive state,
- meter snapshots remain read-only.

### End-to-end composed loop

A representative test should validate:

```text
widget event
  -> semantic UI event
  -> ControlIntent
  -> command lowering
  -> synth mutation or queued HostEvent
  -> copied snapshot
  -> next authored tree
```

Existing synth ABI tests and generic UI tests are not sufficient by themselves; the composed projection loop needs its own coverage.

## Phased Implementation Principles

Implementation may be incremental, but the foundation must remain the shared schema compiler.

Phased work should follow these principles:

1. **Start with a small schema vocabulary.**  
   Include only the control facts needed for the first truthful UI slice, but encode them in the final ownership model.

2. **Do not introduce a separate temporary UI catalog.**  
   Even the first visible controls must come from the shared schema path.

3. **Make declared mutability real.**  
   A writable descriptor must correspond to actual mutation and observable snapshot state.

4. **Prefer copied snapshots over convenience pointers.**  
   UI state must not retain native storage references.

5. **Keep generated/derived artifacts inspectable.**  
   The schema compiler should clarify ownership, not hide behavior in opaque framework magic.

6. **Separate runtime controls from patch authoring.**  
   Runtime parameter edits and authored patch edits may both appear in the UI, but they lower through different command paths.

7. **Use generation guards without destabilizing UI IDs.**  
   Stable logical IDs preserve interaction state; binding epochs protect correctness.

8. **Test each new declared control through the full loop.**  
   Adding a control means adding schema facts, projection behavior, command lowering, mutation/snapshot behavior, and tests.

## Tradeoffs Acknowledged

This decision sacrifices short-term speed. A temporary performance panel would be faster to display, and a hand-authored Lua descriptor table would be simpler at first.

That cost is accepted because the durable problem is not drawing knobs; it is establishing a truthful, typed, testable control/projection source shared by synth behavior and UI projection.

The decision also introduces a schema/compiler layer. That adds design and maintenance weight. The accepted constraint is that the schema must remain small, typed, and ownership-oriented. It must describe real synth/control facts, not become a broad decorative UI language.

## Risks Acknowledged

Known risks from critique:

- The schema could become a large meta-language if not disciplined.
- Generated artifacts could obscure ownership boundaries instead of clarifying them.
- Descriptor/mutation drift is still possible if generated/derived paths are bypassed.
- Migration cost is high because current parameter behavior must be made truthful.
- The architecture is only valuable if tests prove that writable controls actually mutate observable state.

The approved mitigation is architectural discipline: one canonical schema, derived artifacts, copied snapshots, explicit command lowering, and end-to-end tests for every exposed writable control.
