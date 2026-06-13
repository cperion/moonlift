# Zyn Moonlift Synth Implementation Spec

Sibling contract for `zyn_moonlift_synth_headers.mlua`.

This file is the behavioral contract required before `zyn_moonlift_synth_impl.mlua`
can exist. The header declares the product forest, protocol graph, and ABI seals.
This document fixes the concrete machine rules that bodies must transcribe.

## Design Boundary

The synth is a fixed-capacity, host-allocated, block-rendered stereo engine.
Moonlift code owns no hidden global state. The host owns raw memory and audio/event
buffers. `SynthStorage` owns all persistent engine memory after `F.synth_init`.
`RenderScratch` owns temporary per-block memory. Prepared programs are immutable
after publication.

Internal behavior composes through regions. ABI functions return `AbiStatus`
integers only at the boundary.

## ABI Status Mapping

`F.*` functions map internal protocol outcomes to `E.AbiStatus` exactly once:

| Status | Value | Meaning |
|---|---:|---|
| `ok` | `0` | The requested operation completed. Silence is success for render. |
| `bad_state` | `1` | `Synth`, `SynthStorage`, or a handle generation is invalid for this operation. |
| `bad_buffer` | `2` | A required view/pointer is null, too short, mis-strided, or over configured limits. |
| `bad_patch` | `3` | Patch bytes are structurally malformed or fail validation. |
| `unsupported_patch` | `4` | Patch format/version/feature is recognized as unsupported by this engine version. |
| `exhausted_storage` | `5` | Arena, pool, cache, slot, or configured capacity is insufficient. |
| `stale_handle` | `6` | A typed handle names an object whose generation no longer matches. |

Boundary mapping:

| ABI function | Internal operation | Non-ok mapping |
|---|---|---|
| `synth_required_storage` | Pure size calculation from `SynthConfig` | Returns `0` if config is invalid or overflows `index`. |
| `synth_init` | Lay out `SynthStorage`, reset pools/caches, install policy | `bad_buffer`, `exhausted_storage`, `bad_state`. |
| `synth_prepare_program` | Decode, prepare, validate, publish | `bad_patch`, `unsupported_patch`, `exhausted_storage`, `bad_state`, `stale_handle`. |
| `synth_render_block` | Enter render memory, events, voices, effects, finalize | `bad_buffer`, `bad_state`, `stale_handle`, `ok` for silent/clipped/rendered. |
| `synth_set_parameter` | Resolve and apply one parameter event | `bad_state`, `stale_handle`, `ok` for unchanged/smoothed/changed. |
| `synth_note_on` | Allocate/start all matching note layers | `bad_state`, `exhausted_storage`, `ok` for muted/no-layer. |
| `synth_note_off` | Release matching voices | `bad_state`, `stale_handle`, `ok` for none/released. |
| `synth_all_notes_off` | Release all channel voices | `bad_state`, `ok` for none/released. |
| `synth_panic` | Clear all voices and effect state | `bad_state`, `ok` for already silent/cleared. |

## Host Storage Contract

`F.synth_required_storage(config)` returns the total byte count required for one
contiguous host allocation that backs `SynthStorage.arena`.

`F.synth_init(s, storage, config, policy, sample_rate_hz)` requires:

- `s` is a valid pointer to writable `Synth`.
- `storage.arena.data` points to at least `storage.arena.cap` bytes.
- `storage.arena.cap >= synth_required_storage(config)`.
- `storage.arena.used` is ignored on entry and set by initialization.
- `sample_rate_hz > 0`.
- Every count in `SynthConfig` is nonzero except `macro_count`,
  `pad_table_count`, `pad_total_frames`, `effect_bus_count`, and
  `effect_slots_per_bus`, which may be zero together.

Initialization lays out storage in this order, each allocation aligned to its
element alignment and the whole arena aligned at least to 16 bytes:

1. `ProgramSlot[program_banks * programs_per_bank]`
2. `VoiceState[max_voices]`
3. `u16[max_voices]` voice generations
4. `VoiceRef[max_voices]` active voice list
5. `u32[max_voices]` free-list next indices
6. `ControlState[channel_count]`
7. `u8[channel_count * 128]` MIDI CC values
8. `f32[macro_count]` macro values
9. `f32[pad_total_frames]` pad cache table data
10. `index[pad_table_count]` pad table offsets
11. `index[pad_table_count]` pad table lengths
12. `u16[pad_table_count]` pad table generations
13. `EffectState[effect_bus_count * effect_slots_per_bus]`
14. `index[effect_bus_count]` effect bus offsets
15. `index[effect_bus_count]` effect bus slot counts

Initialization sets:

- all program slots unoccupied with null program pointers and generation `1`;
- all voice generations to `1`;
- `VoicePool.active_count = 0`;
- free list as `0 -> 1 -> ... -> max_voices - 1`, with empty encoded by
  `0xffffffff`;
- channel controls to pitch bend `0`, pressure `0`, sustain `false`,
  expression/volume `1`, pan `0`, CC values `0`, macros `0`;
- pad cache used frames `0`, generation `1`;
- effect states bypassed, generation `1`, delay/filter accumulators zero;
- `Synth.current_program` to bank `0`, program `0`, generation `0`;
- `Synth.generation = 1`, transport stopped, meter zero.

`close_synth_storage` invalidates publication by bumping `Synth.generation` and
clearing active voices. It does not free host memory.

## Patch Format V1

`PatchSource.format_id` must be `0x5a594e4d` (`ZYNM`) and `version` must be `1`.
All multi-byte fields are little-endian. All offsets are byte offsets from the
start of `PatchSource.bytes`. All section payloads are 4-byte aligned.

File layout:

```text
0x00  u32 magic       = 0x5a594e4d
0x04  u32 version     = 1
0x08  u32 flags       = 0
0x0c  u32 section_count
0x10  SectionDir[section_count]
...   section payload bytes
```

`SectionDir`:

```text
u8  kind       -- E.PatchSectionKind
u8  reserved0  -- must be 0
u16 index      -- part/layer/bus/slot index where applicable
u32 offset
u32 len
```

Directory entries must be sorted by `(kind, index)`, non-overlapping, inside the
source byte range, and aligned. Unknown kinds produce `unsupported_section`.
Malformed headers, offsets, overlaps, or short records produce `malformed`.

Section payloads use fixed records, no nested self-describing format:

| Section | Index meaning | Payload |
|---|---|---|
| `header` | `0` | `PatchHeaderV1` |
| `tuning` | `0` | `TuningV1` followed by `f32[count]` ratios |
| `part` | part index | `PartV1` |
| `layer` | `(part << 8) | layer` | `LayerV1` |
| `modulation` | layer index encoding | `u32 route_count` followed by `ModRouteV1[route_count]` |
| `additive` | layer index encoding | `AdditiveV1` followed by arrays |
| `subtractive` | layer index encoding | `SubtractiveV1` followed by arrays |
| `pad` | layer index encoding | `PadV1` |
| `effect_bus` | bus index | `EffectBusV1` followed by `EffectSlotV1[slot_count]` |
| `end_marker` | `0` | zero-length payload |

Layer index encoding stores `part_index` in the high byte and `layer_index` in
the low byte of the directory `index` field. If either index exceeds `255`, the
patch is unsupported.

`PatchHeaderV1`:

```text
u16 part_count
u16 insert_count
u16 send_count
u16 reserved0
u32 flags
```

`TuningV1`:

```text
u8  root_midi_note
u8  reserved0
u16 count
f32 root_hz
```

`PartV1`:

```text
u8  midi_channel
u8  enabled
u16 layer_count
u16 max_polyphony
u8  steal_mode
u8  reserved0
f32 gain
f32 pan
f32 same_note_bonus
f32 release_bonus
f32 age_weight
f32 level_weight
```

`LayerV1`:

```text
u8  first_note
u8  last_note
u8  mono
u8  legato
i16 transpose_semitones
u8  tone_mask
u8  reserved0
f32 pitch_bend_range_cents
EnvelopePlan amp_env
EnvelopePlan pitch_env
EnvelopePlan filter_env
LfoPlan lfo1
LfoPlan lfo2
FilterPlan filter
f32 nominal_gain
f32 pan
```

`ModRouteV1`, `EnvelopePlan`, `LfoPlan`, `FilterPlan`, `EffectSlotV1`, and the
field order for corresponding Moonlift products are byte-identical to the
Moonlift product fields, with natural alignment and no padding beyond the
alignment required by the fields.

`AdditiveV1`:

```text
u16 partial_count
u16 reserved0
f32 detune_cents
f32 stereo_spread
f32 phase_random
f32 ratios[partial_count]
f32 gains[partial_count]
f32 phase_offsets[partial_count]
f32 pan[partial_count]
```

`SubtractiveV1`:

```text
u16 band_count
u16 reserved0
f32 source_color
f32 stereo_width
f32 center_hz[band_count]
f32 bandwidth_hz[band_count]
f32 gains[band_count]
f32 pan[band_count]
```

`PadV1`:

```text
u32 table_index
u32 table_length
u32 table_count
f32 base_frequency_hz
f32 morph
f32 position_lfo_amount
```

`EffectBusV1`:

```text
u16 slot_count
u16 reserved0
f32 send_gain
EffectSlotV1 slots[slot_count]
```

Validation rules:

- `midi_channel < channel_count`.
- `first_note <= last_note`.
- `tone_mask` uses only AD/SUB/PAD bits.
- route source/destination tags must be known.
- effect kind tags must be known.
- counts must not exceed `SynthConfig`.
- every enabled layer must have at least one tone bit set.
- all f32 parameters must be finite.

## Program Preparation

`prepare_program` decodes sections, allocates all prepared products in
`SynthStorage.arena`, and constructs a single immutable `PreparedProgram`.

Arena allocation is monotonic. Preparing a program uses the unused tail of
`SynthStorage.arena`; publishing makes those bytes owned by the target
`ProgramSlot`. If preparation fails, `arena.used` is restored to its value at
the start of preparation.

Publication rules:

- `target.bank < ProgramStore.bank_count`.
- `target.program < ProgramStore.programs_per_bank`.
- `target.generation` must be `0` for a new/empty slot or match the occupied
  slot generation for replacement.
- Publishing increments the slot generation, stores the program pointer, sets
  `occupied = true`, and returns the new `ProgramRef`.
- Retiring the current program returns `current_program`.
- Retiring any other occupied slot clears it and increments its generation.

The render thread observes a program only through `borrow_published_program`.
Program pointers borrowed for one block are valid until `render_block` exits.

## Event Semantics

`classify_host_event` dispatches by `HostEvent.kind`:

- `midi` -> `midi(ev.midi)`
- `parameter` -> `parameter(ev.parameter)`
- `program_change` -> `program_change(ev.program, ev.frame)`
- `transport` -> `transport(ev.transport, ev.frame)`
- `all_notes_off` -> `all_notes_off(ev.frame)`
- `panic` -> `panic(ev.frame)`
- unknown -> `ignored`

`classify_midi_event` dispatches by the high nibble of `MidiEvent.kind`.
Velocity-zero note-on is note-off. Pitch bend combines bytes as
`((b << 7) | a) - 8192`, normalized to `[-1.0, 1.0]`.

`apply_host_events` processes events in view order. Event frames must be
`<= RenderCtx.shape.frame_count`; out-of-range events are ignored. The first
program-change request exits `requested_program`; panic exits `panic_requested`
after clearing voices.

## Voice Pool

`VoiceRef.index` indexes `VoicePool.states` and `VoicePool.generations`.
`VoiceRef.generation` must equal `generations[index]`.

Allocation:

- If the part is disabled or velocity is `0`, exit `muted`.
- If the free list is non-empty, pop one index and return `allocated`.
- If full, run `choose_voice_to_steal`.
- If a candidate exists, retire the previous voice at that index and return
  `stolen(v, previous)`.
- Otherwise exit `full`.

Active voices are stored densely in `VoicePool.active[0..active_count)`.
Retiring swaps the last active entry into the removed entry's position, pushes
the index onto the free list, increments its generation, and clears `gate`.

Steal score:

```text
score =
    age_weight * normalized_age
  + level_weight * (1.0 - last_mod.amp)
  + same_note_bonus if note/channel match
  + release_bonus if stage is release/fadeout/retiring
```

The highest score wins. Ties choose the lowest voice index.

Voice start sets:

- part/layer refs from allocation;
- note, channel, velocity;
- `gate = true`;
- `stage = attack`;
- `age_frames = 0`;
- oscillator phases and filter/envelope/LFO state to zero;
- `base_frequency_hz` from tuning and transpose facts.

Voice lifecycle:

- attack/decay/sustain remain `alive` while gate is true;
- note-off sets gate false and stage release;
- release/fadeout transition to `dead` when amp envelope finishes;
- stale handles exit `stale_ref`.

## DSP Semantics

All DSP is deterministic for the same input facts. Denormal protection clamps
absolute values below `DspPolicy.denormal_floor` to `0`.

Envelope:

- `delay`, `attack`, `hold`, `decay`, and `release` are seconds converted to
  samples by `RenderCtx.sample_rate_hz`.
- `linear`, `exponential`, `logarithmic`, `analog`, and `stepped` are consumed
  by `eval_envelope_sample`.
- Finished release exits `finished(x = 0.0)`.

LFO:

- Phase is `[0, 1)`.
- `rate_hz` advances by `rate_hz * inv_sample_rate`.
- `sine`, `triangle`, `square`, `saw_up`, `saw_down`, `random`, and
  `sample_hold` are the only valid shapes.
- Random sources use `LfoState.rng` and are deterministic.

Tone fields:

- AD uses additive partials: `sin(phase * ratio + phase_offset) * gain`.
- SUB uses deterministic noise shaped by band gains.
- PAD reads prepared pad cache tables, interpolating linearly between samples.
- A layer with no matching tone bit is silent.
- Every tone renderer writes exactly `RenderCtx.shape.frame_count` samples.

Filter:

- `bypass` copies input to output.
- `one_pole_lp` and `one_pole_hp` are one-pole filters.
- `svf_lp`, `svf_hp`, `svf_bp`, and `notch` use one state-variable filter core.
- `formant` uses three fixed bandpass stages derived from `cutoff_hz`.
- Invalid model exits `invalid_model`.

Mixing and effects:

- `clear_audio_block` writes zero to both channels for the block frame count.
- `mix_stereo` adds `src * gain` into `dst`.
- `apply_pan_gain` uses equal-power pan in `[-1, 1]`.
- Effects are processed in slot order. `bypass` copies input to output.
- `finalize_audio_block` applies nominal gain, computes peak/RMS, clips to
  `[-clip_ceiling, clip_ceiling]`, and updates `MeterFrame`.

## Render Order

`render_block` is the root render protocol and has this fixed order:

1. `enter_render_memory`
2. `clear_audio_block`
3. `clear_scratch`
4. `apply_host_events`
5. `render_all_parts`
6. `apply_send_effects`
7. `finalize_audio_block`
8. retire dead voices when `RenderPolicy.retire_dead_voices_after_block` is true

`render_all_parts` iterates prepared parts in ascending part index.
`render_part_voices` iterates active voices in active-list order and renders only
voices whose part ref matches the requested part.

## Parameter Semantics

`ParamAddress.scope` owns dispatch in `resolve_parameter`:

- `global`: engine/global parameters
- `part`: `PartPlan` indexed by `part`
- `layer`: `LayerPlan` indexed by `part/layer`
- `modulation`: route indexed by `part/layer/param`
- `insert_fx`: insert bus/slot parameter
- `send_fx`: send bus/slot parameter
- `master_fx`: master effect parameter

`ParamPolicy` gives clamp range and smoothing. `read_only = true` exits
`read_only`. Unknown addresses exit `unknown`.

`apply_parameter_event` clamps to `[min_value, max_value]`. If smoothing is
nonzero, it exits `smoothed`; otherwise it applies the value immediately and
exits `changed`. Applying a value must update only mutable runtime/control
state, not immutable `PreparedProgram` products.

## Implementation Admission Rule

An implementation file may be added only when each body either:

1. transcribes a rule in this spec, or
2. exits a named protocol because this spec explicitly says the input is
   malformed, unsupported, exhausted, stale, or invalid.

Bodies that merely choose a convenient exit without a rule in this document are
not implementation.
