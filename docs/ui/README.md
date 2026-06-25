# `lua/ui`

`lua/ui` is Lalin's ASDL-first UI kit.  It is organized like a small compiler:
authored UI trees are lowered to layout trees, measured and rendered to typed
view operations, executed by a backend/runtime, and reduced with typed
interaction events back into application state.

The current productization target is a general-purpose SDL3-ready UI library for
synth/workbench-style interfaces, while preserving backend-independent contracts
for authoring, layout, render ops, interaction, text, and widgets.

## Contract documents

- [`CONTRACT.md`](CONTRACT.md) — kernel lifecycle, IDs, input, focus, pointer
  capture, state propagation, layers/overlays, text lifecycle, and layout subset.
- [`BACKEND_CONTRACT.md`](BACKEND_CONTRACT.md) — runtime/host/text backend
  capabilities and conformance expectations.
- [`widgets/README.md`](widgets/README.md) — canonical widget bundle/event
  contract and catalog guide.
- [`../../experiments/mlui/mlui_design.md`](../../experiments/mlui/mlui_design.md)
  — Lalin-native translation experiment.  It treats this rich UI ASDL as the
  source architecture and projects it to typed native buffers/protocols.
- [`../../experiments/mlui/mlui_lua_api.md`](../../experiments/mlui/mlui_lua_api.md)
  — proposed MLUI Lua authoring API: callable tables, no-parentheses builders,
  widget bundles, and kernel/session facade.

## Pipeline

```text
Auth.Node
  -> lower.root / lower.phase
  -> Scene.Node(Layout.Node layout, Decor.Node decor)
  -> measure(layout) / solve(layout)
  -> render(Solve.Node, Decor.Node)
  -> View.Op[] typed variants
  -> runtime.run(driver, opts, ops...)
  -> Interact.Report
  -> interact.step(model, report, raw)
  -> semantic Interact.Event[] + next Interact.Model
  -> widget bundle routing / application state update
```

Meaningful UI state is represented in ASDL (`ui.asdl`) rather than hidden in
callbacks or backend-specific tables. Style normalization splits layout spec from
decor spec; layout, decor, solve, view, and interaction facts have separate typed
products. Backends consume the typed view op stream; widgets consume typed
interaction events.

## Public modules

Main facade: `local ui = require("ui")`.

| Module | Purpose |
| --- | --- |
| `ui.asdl`, `ui.T` | Typed vocabulary for authored, layout, decor, solve, view, interaction, text, paint, theme, and session data. |
| `ui.build` | Immediate-mode builders for `Auth.Node`: boxes, text, text refs, paint, scroll, input, drag/drop, state, layers, overlays, focus scopes. |
| `ui.tw`, `ui.normalize`, `ui.resolve`, `ui.theme` | Tailwind-like style authoring, normalization, concrete theme resolution, and default env/theme helpers. |
| `ui.compose` | ASDL composition nouns such as panels/splits/workbench lowered to `Auth.Node`. |
| `ui.id` | Full-tree ID collection/validation and deterministic child ID helpers. |
| `ui.state` | Canonical bridge from `Interact.Model`/`Interact.Report` plus app flags to `Style.State`. |
| `ui.input` | Backend-independent key/modifier/raw input constructors and host-event conversion. |
| `ui.lower` | Authored tree lowering with ID validation and interaction-derived style state (`lower.root`). |
| `ui.measure`, `ui.plan`, `ui.solve`, `ui.render` | Layout measurement, shared planning, solved placement, and typed `View.Op` stream generation. |
| `ui.runtime` | Backend-independent op consumer that draws through a driver and records interaction facts. |
| `ui.interact` | Pure reducer from typed raw input + runtime report to semantic events and next interaction model. |
| `ui.paint` | Typed paint programs: lines, polylines, polygons, circles, arcs, Beziers, meshes, images. |
| `ui.text`, `ui.text_*`, `ui.text_field*` | Text system registry, SDL/Love measurement adapters, navigation/editing, and editable field drawing helpers. |
| `ui.widget`, `ui.widgets` | Canonical widget core and catalog. |
| `ui.recipes` | Lower-level reusable interaction recipes used by widgets and custom controls. |
| `ui.session`, `ui.backends` | Multi-window session loop and backend packages. |
| `ui.backend_contract` | Runtime/host/text capability validation helpers. |

## Authoring example

```lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local b = ui.build
local tw = ui.tw
local W = ui.widgets

local interact_model = ui.interact.model()
local last_report = nil
local app = { gain = 0.75, bypass = false }

local gain = W.slider.bundle {
    id = "gain",
    label = "Gain",
    value = app.gain,
    min = 0,
    max = 1,
    step = 0.01,
    model = interact_model,
    report = last_report,
}

local bypass = W.toggle.bundle {
    id = "bypass",
    label = "Bypass",
    selected = app.bypass,
    model = interact_model,
    report = last_report,
}

local auth = b.box {
    b.id("root"),
    tw.flex, tw.col, tw.gap_y_4, tw.p_6,
    tw.bg.slate[950], tw.fg.white,
    gain.node,
    bypass.node,
}

local theme = ui.theme.default()
local env = ui.theme.env { width = 640, height = 480 }
local scene = ui.lower.root(auth, theme, env, {
    model = interact_model,
    report = last_report,
})[1]
local solved = pvm.one(ui.solve.root(scene.layout, ui.T.Solve.Env(640, 480), text_key))
local g, p, c = ui.render.root(solved, scene.decor)
```

Use `ui.solve.root(...)` to produce placed layout, `ui.render.root(...)` to
produce ops, `ui.runtime.run(...)` with a backend driver to draw and collect a
report, then feed host raw input through `ui.input`/`ui.interact.step(...)`.
Widget bundles route the resulting semantic UI events to app-level events:

```lua
local next_model, ui_events = ui.interact.step(interact_model, last_report, raw)
interact_model = next_model

for _, ev in ipairs(gain:route_ui_events(ui_events)) do
    if ev.kind == "change" then app.gain = ev.value end
end
for _, ev in ipairs(bypass:route_ui_events(ui_events)) do
    if ev.kind == "change" then app.bypass = ev.value end
end
```

## IDs and state

IDs are global within an authored tree.  They are shared by hit testing, focus,
scroll state, drag/drop, text editing, widget surfaces, and state styling.  Use
stable non-empty IDs for every interactive or persistent surface, generate child
IDs deterministically, and validate trees with `ui.id.assert_auth` or
`ui.lower.root`.

`ui.state` derives hover/focus/active/selected/disabled style conditions from
interaction facts plus app flags.  Widgets accept `model`/`interact_model`,
`report`, `selected`, `disabled`, `active`, and ID maps so state styling is
consistent across the catalog.

## Layout and rendering

Supported layout vocabulary includes:

- flow containers
- flex rows/columns with wrapping, grow/shrink/basis, gaps, alignment, and fixed
  or automatic sizing semantics
- grid tracks with authored and implicit tracks
- structural scroll regions (`Auth.Scroll` / `b.scroll_*`)
- typed text and text references backed by an explicit content store
- typed paint nodes
- layers, overlays, modal barriers, and focus scopes as authored wrappers that
  become view ops

This is a deliberate layout subset, not a browser-equivalent CSS engine.  Known
limitations are listed below.

## Widgets

`ui.widgets` currently exports:

- activation/choice: `button`, `toggle`/`switch`, `checkbox`, `radio`
- value controls: `slider`, `fader`, `value_drag`, `knob`
- displays: `meter`/`level`, `progress`
- collections: `list`, `listbox`, `tabs`, `menu`/`context_menu`, `select`/`dropdown`
- overlays: `popup`, `overlay`, `tooltip`, `popover`, `modal`/`dialog`
- composition: `panel`, `toolbar`, `property_row`, `form_field`, `split_pane`,
  `scroll_panel`, `canvas`
- text: `text_input`, `text_area`

All catalog widgets return canonical bundles with `{ kind, id, node, surfaces,
model, events, style_slots, route_ui_event, route_ui_events, validate }`.  See
[`widgets/README.md`](widgets/README.md) for event shapes and per-widget examples.

## Backends

### SDL3

SDL3 is the primary productization backend:

- `ui.backends.sdl3` package wrappers
- `ui._sdl3` FFI bindings
- `ui.host_sdl3` host/window/event/clipboard/IME layer
- `ui.runtime_sdl3` renderer driver
- `ui.text_sdl3` SDL_ttf text system
- `ui.session_sdl3` SDL session convenience wrapper

SDL3 currently supports rounded/capsule boxes, clipping, transforms, scrolling,
cursors, layers through the generic runtime, typed paint primitives, texture/BMP
image resolution, SDL_ttf measurement/drawing/hit testing/ranges, clipboard, IME,
and typed host-event raw input attachment.

Use dummy video for headless smoke tests:

```sh
SDL_VIDEODRIVER=dummy luajit tests/ui/test_ui_sdl3_paint.lua
AUTO_QUIT_MS=50 SDL_VIDEODRIVER=dummy luajit examples/ui/text_field_sdl3_demo.lua
```

### Love2D

`ui.runtime_love` and `ui.text_love` remain available and carry capability
metadata, but current product examples are SDL3-focused.  Treat Love support as a
secondary/optional backend unless a workflow explicitly targets it.

## Text lifecycle

`ui.text` maintains explicit registered text systems and a default key.  Sessions
that create an SDL text system register a default session text key, store it on
the session/window, and unregister it on close.  Approximate text layout remains
available explicitly, but real text backends should not be bypassed accidentally.

Editable text is split between:

- `ui.text_field` for backend-neutral editing state and commands
- `ui.text_field_view` for geometry, selection/caret/composition drawing, and
  field hit testing
- `ui.widgets.text_input` / `text_area` for authored shells and widget routing

## Examples

Current examples under `examples/ui/`:

- `text_sdl3_probe.lua` — headless/probe-style SDL_ttf measurement and text API
  check.
- `text_field_sdl3_demo.lua` — SDL3 editable text field demo; supports
  `AUTO_QUIT_MS` and dummy video for CI smoke runs.
- `paint_sdl3_demo.lua` — SDL3 paint/runtime demo for typed paint primitives.

Historical Love demo names such as `examples/ui_love_demo` and
`examples/ui_studio_demo` are not present in the current tree and should not be
used as completion signals.

## Tests

Current baseline checks:

```sh
luajit tests/ui/test_ui_smoke.lua
SDL_VIDEODRIVER=dummy luajit tests/ui/test_ui_sdl3_paint.lua
AUTO_QUIT_MS=50 SDL_VIDEODRIVER=dummy luajit examples/ui/text_field_sdl3_demo.lua
```

The completion plan is adding focused contract tests for interaction, IDs, state
bridging, overlays/layers, layout goldens, backend conformance, text/session
lifecycle, widget contracts/catalog, and examples.

## Known limitations

- Layout is intentionally a supported subset, not full CSS.  Missing or limited
  areas include baseline alignment, `align-content`, main-axis auto margins,
  dense grid placement, and sophisticated multi-span track resolution.
- Hit testing is rectangular for semantic surfaces, even when visuals are rounded
  or paint-backed.  Complex controls should model finer semantic regions with
  explicit child surfaces.
- Accessibility/semantic roles beyond interaction roles are not yet a complete
  contract.
- Overlays/layers are typed and reported, but higher-level popup/menu/modal app
  policies are still widget/application conventions rather than a full window
  manager.
- Text field caret/selection/IME overlays are drawn through the text field view
  helper after the main op stream, so they are a deliberate second rendering path.
- Performance work remains for large trees and text-heavy UIs; current focus is
  contract correctness and productized SDL readiness.

## Design rules

- ASDL first: meaningful UI/input/focus/layer/widget state belongs in typed
  vocabulary.
- Pure reducers: `ui.interact` does not call host, backend, or widget callbacks.
- Fail loud on IDs and unsupported backend capabilities.
- Keep backend-specific behavior behind `ui.backends.*`, `ui.session`, and the
  generic runtime/text contracts.
- Widgets return canonical bundles and do not mutate application state.
