# Investigate Lalin synth compile memory
Find why compiling examples/synth F.synth_render_block consumes ~1.1GB RSS. Gather facts only: pipeline phases, PVM caches, bundle sizes, command counts, memory measurements, likely retention points. Do not propose fixes yet.
**Workflow ID**: wf-zyn-synth-memory
**Started**: 2026-06-13 22:53:32
---

## Scout Output — 2026-06-13 23:02:47

## Files Retrieved

1. `lua/lalin/host_module_values.lua` (lines 47-91, 305-369) — bundle dependency packing, `_lower_program`, `compile`.
2. `lua/lalin/frontend_pipeline.lua` (lines 55-123) — hosted lower pipeline phase order.
3. `lua/lalin/pvm.lua` (lines 350-631, 843-887) — PVM cache/pending tables, phase method attachment, drain behavior.
4. `lua/lalin/chain.lua` (lines 95-139) — `_dep_values` records only actually used splices.
5. `lua/lalin/region_normal_form.lua` (lines 430-500, 622-645) — `emit @{region}` imports/hoists region CFG blocks.
6. `lua/lalin/tree_to_back.lua` (lines 2171-2243, 3117-3155) — statement-if phi generation and module lowering.
7. `examples/synth/zyn_lalin_synth_impl.mlua` (lines 3195-4060) — render/effects/voice orchestration and `F.synth_render_block`.
8. `tests/test_zyn_lalin_synth_impl.lua` (lines 1-83) — compile coverage deliberately split into child processes.

## Key Code

### Bundle compile path

`CallableFunc:compile()` creates a fresh bundle, packs only explicit deps, then JITs:

```lua
local b = api.bundle(self.name .. "_auto")
b:pack(self)
local artifact = b:jit(opts)
```

`BundleValue:_lower_program()`:

```lua
local Pipeline = require("lalin.frontend_pipeline").Define(self.session.T)
local lower_opts = {
    site = "host module",
    layout_env = self:layout_env(),
}
...
if #region_frags > 0 then
    local O = T.LalinOpen
    lower_opts.expand_env = O.ExpandEnv(region_frags, {}, O.FillSet({}), {}, {}, "")
end
return Pipeline.lower_module(self:to_asdl(), lower_opts).program
```

### Pipeline order

`frontend_pipeline.lower_module()`:

```lua
expanded = OpenExpand.module(...)
open_report = OpenValidate.validate(OpenFacts.facts_of_module(expanded), ...)
closed = ClosureConvert.module(expanded)
checked = Typecheck.check_module(closed, ...)
resolved = Layout.module(checked.module, ...)
program, provenance = Lower.module(resolved, ...)
back_report = Validate.validate(program, ...)
```

### PVM cache retention shape

`pvm.phase()` creates per-boundary caches:

```lua
local keyed_cache = setmetatable({}, { __mode = "k" })
local keyed_pending = setmetatable({}, { __mode = "k" })
...
if dispatch ~= nil then
    for cls, _ in pairs(dispatch) do
        rawset(cls, name, function(node, ...)
            return call(boundary, node, ...)
        end)
    end
end
```

That `rawset` makes dispatch phase boundaries reachable from ASDL classes.

### RNF expansion

`region_normal_form.normalize_region_frag_use()` imports emitted region fragments into caller CFG, alpha-renames labels, creates runtime/capture params, and hoists blocks:

```lua
local map = label_map_for_frag(frag, child_path)
local capture_params, capture_args = capture_runtime_params(frag, env)
...
blocks[#blocks + 1] = Tr.ControlBlock(map[frag.entry.label.name], entry_params, entry_body2)
...
return Tr.StmtJump(..., map[frag.entry.label.name], entry_args), blocks
```

### Backend command explosion point

`tree_to_back.lua` statement `if` lowering emits phi block params for mutated local cells:

```lua
for i = 1, #env.locals do
    local local_entry = env.locals[i]
    ...
    if changed then
        cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
        ...
        out_locals[#out_locals + 1] = Tr.TreeBackScalarLocal(local_entry.binding, phi_val, local_entry.ty)
    end
end
```

## Measurements

Commands run locally, no code edits.

### Whole ABI compile suite

```sh
/usr/bin/time -v env ZYN_SYNTH_TEST_MODE=compile_abi luajit tests/test_zyn_lalin_synth_impl.lua
```

Result:

- Elapsed: `0:56.25`
- Max RSS: `1,364,516 KB`

### Single `F.synth_render_block:compile()`

```sh
/usr/bin/time -v luajit /tmp/measure_zyn_one.lua synth_render_block
```

Result:

- Elapsed: `0:19.98`
- Max RSS: `1,202,400 KB`

### Phase-by-phase for `F.synth_render_block`

Key marks:

| Phase | Lua heap KB | RSS KB |
|---|---:|---:|
| after `require lalin` | 48,867 | 57,500 |
| after `lalin.dofile impl` | 101,312 | 114,256 |
| post-load GC | 48,595 | 114,256 |
| bundle pack | 48,607 | 114,256 |
| layout_env | 50,103 | 114,532 |
| OpenExpand.module | 82,309 | 115,308 |
| OpenFacts.facts | 86,907 | 113,956 |
| ClosureConvert.module | 88,939 | 114,524 |
| Typecheck.check_module | 174,165 | 200,432 |
| Layout.module | 190,901 | 218,872 |
| Lower.module | 684,308 | 781,600 |
| BackValidate.validate | 929,844 | 1,053,788 |
| binary.encode | 962,600 | 1,086,580 |
| jit.compile | 982,903 | 1,168,296 |
| final GC | 797,519 | 1,075,688 |

`/usr/bin/time` for the instrumented full path: max RSS `1,204,384 KB`.

### Normal compile/free retention check

After `v:compile(); v:free(); collectgarbage()`:

- after compile: Lua heap `795,392 KB`, RSS `1,089,764 KB`
- after free: Lua heap `794,619 KB`, RSS `1,088,996 KB`
- after nil/module cleanup: Lua heap `794,328 KB`, RSS `1,088,804 KB`

So freeing the JIT artifact does not release most retained Lua heap.

## Bundle / Dependency Facts

For `F.synth_render_block`:

- `_dep_values` closure: `38`
  - `func=1`
  - `region_frag=36`
  - `expr_frag=1`
- bundle after `pack`:
  - `items=1`
  - `type_values=0`
  - `region_frags=36`
  - `exports=1`

Dependency names include:

- `render_block`, `render_block_ready`, `render_all_parts`, `render_one_program_part`
- `render_part_voices`, `render_one_part_voice`, `render_voice`
- `route_layer_tone_generators`
- `render_additive_field`, `render_subtractive_field`, `render_pad_field`
- `apply_host_events`, `apply_send_effects`, `apply_effect_bus`, `apply_effect_slot`
- `clear_audio_block`, `clear_scratch`, `finalize_audio_block`
- `retire_dead_voices_after_block`, `retire_one_dead_voice`, `retire_voice`
- `clamp_f32`

Other dependency totals:

- `F.synth_prepare_program`: `20`
- `F.synth_render_block`: `38`
- `F.synth_note_on`: `10`
- `R.render_block`: `37`
- `R.render_all_parts`: `22`
- `R.render_part_voices`: `19`
- `R.render_voice`: `16`

## Size / Command Counts

For `F.synth_render_block`:

| Artifact | Count |
|---|---:|
| initial module ASDL nodes | `237` |
| expanded ASDL nodes | `4,714` |
| checked module ASDL nodes | `54,686` |
| resolved ASDL nodes | `54,722` |
| backend program ASDL nodes | `312,156` |
| backend commands | `154,799` |
| binary wire payload | `3,622,020 bytes` |

Control-region expansion:

- original module: `1` entry, `18` blocks, `76` block params
- after OpenExpand/RNF: `1` entry, `265` blocks, `8,919` block params
- max block params on one block: `77`

Backend command histogram top entries:

```text
CmdAppendBlockParam  140538
CmdConst               4628
CmdPtrOffset           1515
CmdLoadInfo            1167
CmdIntBinary           1081
CmdCreateBlock         1057
CmdSwitchToBlock       1057
CmdSealBlock           1057
CmdJump                 793
CmdCompare              475
CmdCast                 440
CmdBrIf                 263
CmdSelect               231
```

`CmdAppendBlockParam` is ~91% of all commands.

Top `CmdAppendBlockParam` blocks showed geometric concentration:

```text
ctl.if.join364  65280
ctl.if.join361  32640
ctl.if.join358  16320
ctl.if.join355   8160
ctl.if.join352   4080
ctl.if.join349   2040
ctl.if.join346   1020
ctl.if.join343    510
ctl.if.join340    255
```

ABI command counts:

```text
synth_required_storage   777
synth_init              2818
synth_prepare_program  19283
synth_render_block    154799
synth_set_parameter      668
synth_note_on           4275
synth_note_off           281
synth_all_notes_off      263
synth_panic              317
```

## Relationships

- `F.synth_render_block` is a single exported function item.
- Its body emits `render_block_region`.
- `render_block` emits `enter_render_memory` and `render_block_ready`.
- `render_block_ready` emits:
  - `clear_audio_block`
  - `clear_scratch`
  - `apply_host_events`
  - `render_all_parts`
  - `apply_send_effects`
  - `finalize_audio_block`
  - optional retirement path
- `render_all_parts` expands into part/voice/tone/effects paths.
- RNF hoists every emitted region into one composed control region, producing 265 blocks.
- Backend lowering then turns that large CFG into 154,799 flat `BackCmd`s, dominated by phi/block-param commands.
- Back validation and binary encoding retain large Lua structures before Rust JIT is called; JIT adds memory but is not the main source.

## Observations

- The largest memory jump is Lua-side backend lowering/validation, not Rust JIT:
  - Lower: RSS ~219 MB → ~782 MB.
  - BackValidate: ~782 MB → ~1,054 MB.
  - JIT: ~1,087 MB → ~1,168 MB.
- `F.synth_render_block` compiles one module item, but its explicit region dependency closure pulls in nearly the whole render graph.
- PVM phase caches are reachable via ASDL class methods installed by `pvm.phase`; after `v:free()` most Lua heap remains retained.
- The command stream is unusually dominated by `CmdAppendBlockParam`.
- The top append-param blocks form a doubling/geometric pattern on synthetic `ctl.if.join*` blocks.
- Test suite already avoids compiling too much in one process; `tests/test_zyn_lalin_synth_impl.lua` splits compile phases into subprocesses and notes render wrapper duplication is avoided for memory reasons.
