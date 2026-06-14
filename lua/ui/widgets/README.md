# `ui.widgets`

`ui.widgets` is the canonical catalog for reusable authored UI controls.  Each
widget builds typed `Auth.Node` trees and exposes a small routing contract so
applications can keep state outside the widget and feed semantic events back into
that state.

```lua
local ui = require("ui")
local W = ui.widgets

local gain = W.slider.bundle {
    id = "gain",
    label = "Gain",
    value = model.gain,
    min = -24,
    max = 24,
    step = 0.1,
    model = interact_model,
    report = last_report,
}

-- add gain.node to your authored tree, then after ui.interact.step:
for _, ev in ipairs(gain:route_ui_events(ui_events)) do
    if ev.kind == "change" then model.gain = ev.value end
end
```

## Canonical widget shape

Every catalog widget provides the same public entry points unless noted:

- `node(opts) -> Auth.Node` builds only the authored node tree.
- `surfaces(opts) -> table` returns routable surface metadata keyed by surface
  group and ID.
- `route_one(surfaces, ui_event, bundle) -> event?` converts one
  `ui.interact` event into a widget event.
- `bundle(opts) -> table` returns the complete canonical bundle.

A bundle has at least:

```lua
{
    kind = "slider",             -- widget kind
    id = Core.IdValue("gain"),   -- canonical widget id
    node = auth_node,             -- authored tree
    surfaces = surfaces,          -- surface metadata
    model = opts.model,           -- app/widget model passthrough
    events = opts.events or {},   -- optional pending app events
    disabled = false,
    selected = false,
    style_slots = {},             -- named style override slots
    role = "slider",
    label = opts.label,
    route_ui_event = function(self, ui_event) ... end,
    route_ui_events = function(self, ui_events) ... end,
    validate = function(self, opts) ... end,
}
```

The implementation lives in `ui.widget`; direct consumers can use helpers such
as `ui.widget.require_id`, `ui.widget.child_id`, `ui.widget.bundle`,
`ui.widget.value_event`, and `ui.widget.route_interact_event` for custom
widgets.

## IDs and child IDs

Widget `id` values must be stable and non-empty.  Strings are converted to
`Core.IdValue`; callers may also pass ASDL IDs directly.  Widgets generate child
IDs by appending semantic suffixes such as `:label`, `:track`, `:thumb`,
`:item:<key>`, `:popup`, or `:scroll` via `ui.widget.child_id`.

The full authored tree should be validated by `ui.id.assert_auth` or by
`ui.lower.root` with default validation enabled.  Duplicate IDs are errors
because hits, focus, scroll state, drag/drop, text editing, and state styling all
share the same identity space.

Use `Core.NoId` only for leaves that are intentionally not interactive and do
not carry persistent state.

## Styling and state

Catalog widgets expose named `style_slots` so callers can replace or extend the
style tokens used by the widget.  Common slot names are:

- `root` — outer widget box.
- `label` — label text.
- `field` — text field body.
- `track`, `fill`, `thumb` — sliders, faders, knobs, meters, progress bars.
- `item` — list, menu, tab, and select rows.
- `header`, `body`, `footer` — panels/modals where applicable.

Most widgets accept `styles` plus slot-specific overrides such as
`label_styles`, `field_styles`, `track_styles`, `thumb_styles`, `row_styles`,
`item_styles`, `header_styles`, `body_styles`, and `footer_styles`.

Interactive visual state is derived through `ui.state` from
`Interact.Model`/`Interact.Report` and explicit widget flags.  Pass
`model`/`interact_model`, `report`, `selected`, `disabled`, `active`, or the
corresponding ID maps (`selected_ids`, `disabled_ids`, `active_ids`) to have
`hover`, `focus`, `active`, `selected`, and `disabled` style conditions resolved
consistently.  Explicit `Auth.WithState` wrappers are merged with derived state.

## Event routing

Widgets do not mutate application state.  They convert lower-level interaction
events into widget events.  Common widget event kinds are:

| Kind | Meaning |
| --- | --- |
| `activate` | Button-like activation from pointer or keyboard. |
| `change` | Value changed; payload usually includes `value`. |
| `input` | Text committed; payload includes `text`. |
| `edit` | Text composition/edit update; payload includes `text`, `start`, `length`. |
| `focus` / `blur` | Focus entered or left. |
| `select` | Item/list/menu/tab/select choice; payload includes `value`/`key`. |
| `navigate` | Keyboard navigation intent for item collections. |
| `scroll` | Scroll surface event; payload includes `dx`, `dy`. |
| `open` / `close` | Popup/menu/select/modal visibility intent. |
| `drag_start`, `drag_move`, `drop`, `drag_cancel` | Drag surface lifecycle. |

All events include `kind`, `type` (same value), `id`, and `widget_id` where
possible.  Most include the original `source` interaction event and `surface`
metadata.

## Keyboard and focus behavior

The interaction reducer emits typed keyboard events (`KeyPressed`,
`KeyReleased`, `TextInput`, `TextEditing`) and abstract focus/activation events
(`SetFocus`, `ClearFocus`, `Activate`, `ScrollBy`, drag events).  Widgets route
only the events that are relevant to their surfaces.

Conventions used by the catalog:

- `Tab` / `Shift+Tab` are handled by the reducer as focus traversal.
- `Return` and `Space` activate focused controls and select focused items.
- `Escape` closes popups, popovers, selects, menus, and modals.
- Arrow keys move list/menu/tab/select focus or adjust sliders/knobs.
- `Home`/`End` jump to min/max or first/last item.
- `PageUp`/`PageDown` produce larger slider/list movements where supported.
- Disabled widgets use passive input roles and suppress routed events unless a
  widget explicitly documents otherwise.

Text widgets receive `TextInput` and `TextEditing` for focused edit targets.
Their overlay drawing should use the active session/window text key to avoid
accidental approximate layout.

## Catalog

### `button`

Activation control.

```lua
local save = W.button.bundle { id = "save", label = "Save" }
```

Routes `Activate` to `activate`, and focus changes to `focus`/`blur`.  Style
slots: `root`, `label`.

### `toggle`, `checkbox`, `radio`

Boolean or mutually-exclusive selection controls.

```lua
local bypass = W.toggle.bundle { id = "bypass", label = "Bypass", selected = model.bypass }
local agree = W.checkbox.bundle { id = "agree", label = "I agree", selected = model.agree }
local osc_a = W.radio.bundle { id = "osc-a", label = "Osc A", selected = model.osc == "a" }
```

Routes activation to `change`/selection-style events with a boolean `value`.
Use stable IDs per radio option and resolve exclusivity in application state.

### `slider`, `fader`, `value_drag`

Continuous numeric controls.  `fader` is a vertical slider preset;
`value_drag` uses the same value contract with drag-oriented styling.

```lua
local cutoff = W.slider.bundle { id = "cutoff", value = model.cutoff, min = 20, max = 20000, step = 1 }
local volume = W.fader.bundle { id = "volume", value = model.volume, min = 0, max = 1 }
local cents = W.value_drag.bundle { id = "fine", label = "Fine", value = model.fine, min = -100, max = 100 }
```

Routes pointer drags and keyboard adjustment to `change` with `value`.  Helpers:
`clamp`, `normalized`, `value_from_normalized`, `value_from_point`, and
`increment`.  Style slots: `root`, `label`, `track`, `fill`, `thumb`, `value`.

### `knob`

Paint-backed rotary numeric control.

```lua
local res = W.knob.bundle { id = "res", label = "Res", value = model.res, min = 0, max = 1 }
```

Uses the same numeric/event conventions as sliders, with knob-specific paint
visuals.

### `meter`, `progress`

Read-only value displays.  `progress` is a progress-bar preset.

```lua
local level = W.meter.bundle { id = "level", value = rms, min = 0, max = 1 }
local load = W.progress.bundle { id = "load", value = compile_progress }
```

These usually do not route interaction events.  They provide `normalized` and
`program` helpers for paint/layout construction.  Style slots include `root`,
`track`, `fill`, and `label`.

### `list`, `listbox`, `tabs`

Item collections.  `listbox` and `tabs` are activatable/selectable presets.

```lua
local waves = W.listbox.bundle {
    id = "wave",
    items = { "sine", "saw", "square" },
    selected_key = model.wave,
}
local pages = W.tabs.bundle { id = "pages", items = { "osc", "filter", "env" }, selected_key = model.page }
```

Items may be plain values or tables with `key`, `id`, `value`, `label`, `text`,
`name`, or `disabled`.  Override `key_of`, `label_of`, or `render_item` for
custom rows.  Routes activation to `select` and arrows/Home/End to `navigate`.
Style slots: `root`, `item`, `label`.

### `menu`, `select`

Popup item collections.  `select` is a dropdown/select preset built on menu.

```lua
local menu = W.menu.bundle { id = "file-menu", open = model.file_open, items = { "New", "Open" } }
local theme = W.select.bundle { id = "theme", value = model.theme, items = { "dark", "light" }, open = model.theme_open }
```

Routes item activation to `select` and escape/cancel/outside-close semantics to
`close` where available.  Use application state to control `open`.

### `popup`, `overlay`, `tooltip`, `popover`, `modal`

Layered/overlay containers.

```lua
local tip = W.tooltip.bundle { id = "gain-tip", open = hovering_gain, content = "Gain in dB" }
local dialog = W.modal.bundle { id = "confirm", open = model.confirm_open, child = dialog_node }
```

These widgets emit typed `Layer`, `Overlay`, and `FocusScope` authored wrappers.
`modal` uses modal layer/focus policy defaults.  Escape and cancel route to
`close`.  `tooltip` is passive; `popover` and `modal` are interactive overlays.

### `panel`, `toolbar`, `property_row`, `form_field`, `split_pane`, `scroll_panel`

Composition helpers for application layout.

```lua
local bar = W.toolbar.bundle { id = "main-toolbar", children = { save.node, undo.node } }
local row = W.property_row.bundle { id = "cutoff-row", label = "Cutoff", child = cutoff.node }
local split = W.split_pane.bundle { id = "editor", first = left.node, second = right.node, ratio = 0.35 }
local scroller = W.scroll_panel.bundle { id = "patch-list", child = patch_list.node }
```

`split_pane` routes splitter drags to `change` with a ratio/value.  `scroll_panel`
registers a scroll surface and routes scroll events.  Other composition widgets
mostly preserve child events through their child bundles and provide structure and
style slots.

### `canvas`

Paint/custom drawing surface with input metadata.

```lua
local scope = W.canvas.bundle {
    id = "scope",
    paint = my_paint_program,
    width = 320,
    height = 120,
}
```

Use `local_point`, `contains`, and `find_hit` to map pointer events back into
canvas-local coordinates.  Canvas is intentionally rectangular at the semantic
hit level; richer hit testing should be modeled explicitly by the application or
with child surfaces.

### `text_input`, `text_area`

Editable text shells around `ui.text_field` and `ui.text_field_view`.

```lua
local name = W.text_input.bundle { id = "patch-name", label = "Name", placeholder = "Init" }
local notes = W.text_area.bundle { id = "notes", label = "Notes", min_h = 160 }
```

Routes `InputText`, `EditText`, and focus events for edit surfaces.  Draw the
caret/selection/IME overlay with `text_input.draw(host_or_window, report, field,
opts)` or `text_area.draw(...)` after the main op stream has been rendered.
Helpers `contains` and `local_point` work on draw results.

## Building custom widgets

Prefer composing the same primitives used by the catalog:

1. Require a stable ID with `ui.widget.require_id`.
2. Generate deterministic child IDs with `ui.widget.child_id`.
3. Build an `Auth.Node` with `ui.build` and wrap interactive regions in
   `b.with_input`, `b.drag_source`, `b.drop_target`, or typed layer wrappers.
4. Add surface metadata with `ui.widget.add_surface`.
5. Return `ui.widget.bundle { ... }` and route reducer events through
   `ui.widget.route_interact_event` or a widget-specific `route_one`.
6. Validate authored IDs in tests with `ui.id.assert_auth` or through
   `ui.lower.root`.

This keeps custom controls compatible with the same interaction reducer, state
bridge, style conditions, and backend/runtime reports as the built-in catalog.
