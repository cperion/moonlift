# MLUI Lua Authoring API

Status: superseded by
[`experiments/mlui-llpvm/mlui_llpvm_stack_blueprint.md`](../mlui-llpvm/mlui_llpvm_stack_blueprint.md)
for current architecture. This file is retained as historical authoring-API
input from the pre-LLPVM design. Current API work must feed the semantic
domain-world pipeline, not the old lower/solve/interact split.

Historical scope: design specification for the Lua authoring surface above the
Moonlift UI kernel.

Historical companion docs:

- [`mlui_lua_api_reference.md`](mlui_lua_api_reference.md) documents the old
  `require "mlui"` API.
- [`mlui_usage_guide.md`](mlui_usage_guide.md) documents the old retained-kernel
  usage model.

This API follows the same decision as `chain.lua` and the MWUI blueprint:
tree-shaped authoring is built with Lua callable tables and no parentheses.
Moonlift owns the typed kernel protocols underneath.

## Doctrine

```text
Lua writes authored UI trees.
Moonlift owns resource lifetimes, phase protocols, and native buffers.
Widgets route typed events; they do not mutate application state.
Backends draw typed view ops; they do not own UI semantics.
```

The public API is not a bag of functions.  It is a set of callable builder
objects whose call shape says what is being authored.

## Immediate Mode, Memoized Kernel

The Lua API is immediate-mode:

```lua
local root = ui.box "main" {
    W.slider "gain" {
        value = app.gain,
        model = model,
        report = report,
    }.node,
}
```

The native kernel is allowed to be retained and memoized.  The distinction is
the design:

```text
Lua rebuilds semantic authoring values.
Moonlift memoizes imported buffers, style, text layout, measurement, solve, and render products.
```

Stable ids and explicit epochs make that cache sound:

```lua
ui.text_ref "patch_name" {
    content = patch_name_content,
    epoch = app.patch_name_epoch,
}

ui.paint "scope" {
    epoch = oscilloscope_epoch,
    paint.polyline { points = samples },
}
```

The API should never force authors into retained widget objects just to get
performance.  If a workflow needs phases, it may use a state-machine noun, but
that is a semantic protocol choice, not the default rendering model.

There is no author-facing `memo` wrapper around widget functions.  Reuse is a
kernel concern:

```text
W.slider "gain" { ... }        -- builds semantic authoring data
ui_import_auth                 -- may hit imported-node cache
ui_resolve_style               -- may hit style cache
ui_measure_node                -- may hit text/layout cache
ui_solve_scene / ui_render_ops -- may hit phase-product caches
```

That keeps Lua immediate-mode and keeps cache ownership in Moonlift products
where stale/missing/oom outcomes can be named.

## No-Parens Law

Author-facing construction should read like Lua data:

```lua
local ui = require "mlui"
local tw = ui.tw
local W = ui.widgets

local gain = W.slider "gain" {
    label = "Gain",
    value = app.gain,
    min = 0,
    max = 1,
    step = 0.01,
    model = model,
    report = report,
}

local root = ui.box "main" {
    tw.flex, tw.col, tw.gap.y[4], tw.p[6],
    tw.bg.slate[950], tw.fg.white,
    ui.text "Oscillator" { tw.text.lg, tw.font.semibold },
    gain.node,
}
```

Lua only permits no-parentheses calls with string literals and table
constructors.  Therefore dynamic or non-string values are passed in a table:

```lua
W.slider {
    id = dynamic_id,
    value = current_value,
    model = model,
    report = report,
}
```

Do not invent pseudo-Lua like `W.slider dynamic_id`.  Use either staged string
calls for literal ids or table calls for dynamic facts.

## Call Grammar

All tree-shaped builders obey the same grammar:

```lua
builder "name"          -- stage id/name/content
builder { ... }         -- build from an option/list table
builder "name" { ... }  -- stage then build
builder.key             -- specialize the builder
builder.key "name"      -- stage specialized builder
builder.key { ... }     -- build specialized fragment
builder.key "name" { ... }
```

The staged result is another callable builder.  It accumulates only authoring
facts, not hidden mutable UI state.

Meaning by argument shape:

| Shape | Meaning |
| --- | --- |
| string call | literal id/name/content, depending on builder |
| table call | terminal product or fragment with children/options |
| indexed field | token lookup such as `tw.p[4]` or `tw.bg.slate[950]` |
| dot field | namespace specialization such as `tw.hover` or `ui.scroll.y` |

False and nil entries in child/style arrays are ignored so build-time Lua can
conditionally include fragments without changing the grammar.

## Facade

```lua
local ui = require "mlui"
local tw = ui.tw
local paint = ui.paint
local W = ui.widgets
```

The facade exports:

| Name | Role |
| --- | --- |
| `ui.box`, `ui.text`, `ui.text_ref`, `ui.paint`, `ui.empty`, `ui.fragment` | authored core nodes |
| `ui.scroll`, `ui.input`, `ui.drag`, `ui.drop`, `ui.state`, `ui.layer`, `ui.overlay`, `ui.modal`, `ui.focus` | authored wrappers and interaction nouns |
| `ui.compose` | panel/split/workbench composition nouns |
| `ui.tw` | style token builders |
| `ui.widgets` | canonical widget bundles |
| `ui.theme`, `ui.env` | theme/environment products |
| `ui.kernel` | native kernel/session bridge |

## Authored Nodes

Core nodes:

```lua
ui.box "root" {
    tw.flex, tw.row, tw.items.center,
    ui.text "Ready",
}

ui.text "Ready" {
    tw.fg.green[400],
    tw.font.mono,
}

ui.text_ref "status_text" {
    style = { tw.fg.gray[200] },
}

ui.paint "scope" {
    tw.w.fill, tw.h[120],
    paint.polyline {
        points = samples,
        stroke = paint.stroke { color = 0xff66ccff, width = 1.5 },
    },
}

ui.fragment {
    ui.text "A",
    ui.text "B",
}
```

Wrappers preserve the current `lua/ui/asdl.lua` richness:

```lua
ui.scroll.y "preset_list" {
    tw.h[240],
    child = preset_list,
}

ui.input.activate "save" {
    keys = { "Enter", "Space" },
    child = save_button,
}

ui.drag.source "osc_handle" {
    payload = { kind = "oscillator", id = osc_id },
    child = handle_node,
}

ui.drop.target "rack_slot" {
    accepts = { "oscillator", "effect" },
    child = slot_node,
}

ui.focus.scope "main_scope" {
    trap = false,
    child = root_node,
}

ui.layer "popup_layer" {
    order = 20,
    child = popup_node,
}

ui.overlay "menu" {
    anchor = "menu_button",
    placement = ui.place.below,
    modal = false,
    child = menu_node,
}

ui.modal "settings" {
    child = settings_panel,
}
```

Every authored constructor produces a Lua ASDL value first.  Import into
Moonlift happens through named regions such as `ui_import_auth`; the Lua builder
does not smuggle native ownership through side tables.

## Style API

Style is a token DSL, not a CSS string layer:

```lua
tw.flex
tw.col
tw.gap.y[4]
tw.p[6]
tw.w.fill
tw.h[120]
tw.bg.slate[950]
tw.fg.white
tw.border[1]
tw.radius.md
tw.opacity[80]
```

State and environment conditions are callable token groups:

```lua
tw.hover {
    tw.bg.blue[600],
}

tw.focus {
    tw.ring[2],
    tw.ring.sky[400],
}

tw.disabled {
    tw.opacity[40],
}

tw.dark {
    tw.bg.slate[950],
    tw.fg.gray[100],
}

tw.md {
    tw.row,
    tw.gap.x[6],
}
```

The output is still `Style.Token` / `Style.Atom` richness.  The native ABI may
encode tokens into rows, but only `ui_visit_style_atom` and `ui_resolve_style`
own the interpretation.

## Compose API

Composition nouns remain first-class instead of being flattened into boxes:

```lua
ui.compose.panel "transport" {
    title = ui.text "Transport",
    body = ui.box {
        play_button.node,
        stop_button.node,
    },
}

ui.compose.hsplit "workspace" {
    left = browser_panel,
    right = editor_panel,
    ratio = 0.32,
}

ui.compose.workbench "synth" {
    toolbar = toolbar,
    sidebar = preset_browser,
    main = patch_editor,
    bottom = modulation_panel,
}
```

These build `Compose.Node` values and lower through `ui_expand_compose`.  They
are not Lua-only sugar that disappears before the protocol design.

## Widget API

Widgets return canonical bundles:

```text
{ kind, id, node, surfaces, model, events, style_slots,
  route_ui_event, route_ui_events, validate }
```

The bundle is data plus routing helpers.  It does not call application
callbacks.

Examples:

```lua
local save = W.button "save" {
    label = "Save",
    disabled = not can_save,
    model = model,
    report = report,
}

local bypass = W.toggle "bypass" {
    label = "Bypass",
    selected = app.bypass,
    model = model,
    report = report,
}

local cutoff = W.knob "cutoff" {
    label = "Cutoff",
    value = app.cutoff,
    min = 20,
    max = 20000,
    scale = "log",
    model = model,
    report = report,
}

local name = W.text_input "patch_name" {
    value = app.patch_name,
    edit = text_edit_state,
    model = model,
    report = report,
}
```

Routing stays explicit:

```lua
for _, ev in ipairs(save:route_ui_events { events = ui_events }) do
    if ev.kind == "activate" then app.save_requested = true end
end

for _, ev in ipairs(cutoff:route_ui_events { events = ui_events }) do
    if ev.kind == "change" then app.cutoff = ev.value end
end
```

The no-parens rule is preserved by using a table call for dynamic event arrays.

## Paint API

Paint programs are authored as typed commands:

```lua
local scope = ui.paint "scope" {
    paint.stroke { color = 0xff66ccff, width = 1.25 },
    paint.polyline { points = samples },
    paint.circle { cx = 24, cy = 24, r = 8 },
    paint.mesh {
        vertices = mesh_vertices,
        indices = mesh_indices,
    },
    paint.image "logo" {
        image = logo_ref,
        fit = "contain",
    },
}
```

Point arrays, meshes, images, and text layouts become retained or borrowed
kernel resources according to the ownership protocols in `mlui_design.md`.

## Kernel API

The kernel/session object is the only Lua API that crosses into native Moonlift.
It is still no-parens at public call sites:

```lua
local kernel = ui.kernel {
    backend = backend,
    theme = ui.theme.default,
}

local frame = kernel:frame {
    root = root,
    env = ui.env {
        width = 1280,
        height = 720,
        dpi = 1.0,
        scheme = "dark",
    },
    input = raw_input,
    model = model,
}

backend:draw {
    ops = frame.ops,
    text = frame.text,
    images = frame.images,
}

model = frame.model
local ui_events = frame.events
```

`kernel:frame` is a facade over the explicit region sequence:

```text
ui_import_auth
ui_expand_compose
ui_resolve_style
ui_lower_scene
ui_measure_node
ui_solve_scene
ui_render_ops
ui_runtime_report
ui_interact_step
```

The convenience call may exist in Lua, but the architecture remains the typed
protocol chain.  Failures are returned as typed diagnostics or edge status
objects, not thrown from arbitrary phase internals.

## Historical C Boundary Sketch

Compiled artifacts expose sealed ABI calls, not the Lua builder DSL:

```c
mlui_status mlui_kernel_init_ex(const mlui_kernel_config *config, mlui_kernel **out);
void        mlui_kernel_close(mlui_kernel *kernel);
mlui_status mlui_import_auth_buffer(mlui_kernel *kernel, const mlui_auth_buffer *auth, mlui_node_ref *out_root);
mlui_status mlui_frame(mlui_kernel *kernel, mlui_node_ref root, double w, double h, const mlui_raw_input *raw);
mlui_status mlui_view_ops(mlui_kernel *kernel, const mlui_view_op **ops, size_t *n);
mlui_status mlui_report_get(mlui_kernel *kernel, const mlui_report **report);
mlui_status mlui_events(mlui_kernel *kernel, const mlui_event **events, size_t *n);
```

This old sketch mentioned browser typed arrays. That is not a current MLUI ABI
claim. In the current design, emitted C may be compiled by external C-to-WASM
toolchains, and JavaScript bindings are host-owned.

The browser is an op applier and input producer.  It is not a hidden second UI
object model.

For C embedding, the artifact target is:

```text
single generated C file
optional extracted header
opaque mlui_kernel
stable public row structs
caller-configurable allocator
borrowed output buffers valid until next frame/reset/close
```

The C program is a backend/app host.  It imports auth buffers, calls `mlui_frame`,
draws `mlui_view_op` rows, and applies `mlui_event` rows to its app state.  It
does not see Lua builders or Moonlift internal stores.

More generally, MLUI has a VM frontend contract:

```text
Lua DSL          -> mlui_program rows
C builder        -> mlui_program rows
serialized asset -> mlui_program rows
mlui_frame       -> mlui_view_op rows + mlui_event rows
```

So the no-parens Lua API is one frontend compiler, not the VM itself.  C can
emit the same authored opcode rows directly when a Lua authoring layer is not
wanted.

The row/opcode format is specified in
[`mlui_bytecode.md`](mlui_bytecode.md).  Lua authoring must compile to that
format, and C frontends may fill the same rows directly using
[`mlui_c_api.h`](mlui_c_api.h).

Implementation work should follow
[`mlui_implementation_plan.md`](mlui_implementation_plan.md); the plan requires
region bodies for the whole VM, not declaration-only smoke tests.

## Frame IO

The Lua facade sees frame-level products; it should not expose backend-specific
event tables as the kernel API:

```lua
local raw = ui.input.pointer_moved {
    x = host_x,
    y = host_y,
}

local frame = kernel:frame {
    root = root,
    env = env,
    input = raw,
    model = model,
}

backend:draw {
    ops = frame.ops,
    images = frame.images,
    fonts = frame.fonts,
}
```

Input constructors stay no-parens and product-shaped:

```lua
ui.input.pointer_moved { x = x, y = y }
ui.input.pointer_pressed { button = ui.button.left, x = x, y = y }
ui.input.pointer_released { button = ui.button.left, x = x, y = y }
ui.input.wheel_moved { dx = dx, dy = dy, x = x, y = y }
ui.input.key_pressed { key = ui.key.tab, mods = mods, repeat_ = false }
ui.input.text_input { text = text }
ui.input.text_editing { text = text, start = start, length = length }
ui.input.focus_lost {}
ui.input.cancel_interaction {}
```

The frame output contains the same operation stream used for drawing and runtime
reporting.  Widget routing consumes `frame.events`; drawing consumes `frame.ops`.
There is no second hidden event or render tree.

## API Laws

```text
Callable tables are the authoring surface.
No-parens string/table call sites are the default style.
Dynamic values go inside table calls.
Tree builders produce ASDL values before native import.
Style tokens remain typed facts, not strings.
Widgets return bundles and route typed events; no app callbacks.
Composition nouns remain first-class ASDL.
Kernel convenience APIs are facades over named Moonlift regions.
Native ownership lives in UiKernel stores and owned Ui*Ref protocols.
C exports expose typed buffers, not Lua authoring objects.
```
