# MLUI Lua API Reference

Status: reference for the current `require "mlui"` authoring API.

The Lua API is a frontend compiler surface. It builds MLUI-owned ASDL values
from `lua/mlui/asdl.lua`, then `ui.program(root)` encodes those values into
row-shaped MLUI program data. It does not depend on `lua/ui`.

## Import

```lua
local ui = require "mlui"
local tw = ui.tw
local paint = ui.paint
local W = ui.widgets
```

Exports:

| Name | Meaning |
| --- | --- |
| `ui.T` | MLUI ASDL classes |
| `ui.B` | MLUI ASDL FastBuilders |
| `ui.id` | Build `Core.Id` |
| `ui.box`, `ui.text`, `ui.text_ref`, `ui.paint`, `ui.fragment`, `ui.empty` | Authored node builders |
| `ui.scroll`, `ui.input`, `ui.drag`, `ui.drop`, `ui.focus`, `ui.state`, `ui.layer`, `ui.overlay`, `ui.modal` | Authored wrapper builders |
| `ui.compose` | Compose-node builders |
| `ui.tw` | Style token DSL |
| `ui.paint` | Paint node builder and paint-program namespace |
| `ui.widgets` | Small canonical widget bundles |
| `ui.program`, `ui.encode` | ASDL tree to MLUI program rows |
| `ui.constants` | Auth/compose/paint opcode constants |

## Builder Grammar

All public tree builders use normal Lua no-parens call shapes:

```lua
builder "literal"          -- stage an id/content literal
builder { ... }            -- build from a table
builder "literal" { ... }  -- stage then build
builder.key                -- specialize a wrapper/token namespace
builder.key "id" { ... }   -- specialize, stage, build
```

Dynamic ids and dynamic values go inside table calls:

```lua
ui.box { id = dynamic_id, child }
ui.input.activate { id = dynamic_id, child = button_node }
```

False and nil array entries are ignored in child/style lists.

## Core Nodes

### `ui.id`

```lua
local id = ui.id "save"
```

Returns `Core.NoId` for nil/false, returns existing `Core.Id` unchanged, and
wraps other values as `Core.IdValue(tostring(value))`.

### `ui.box`

```lua
local root = ui.box "main" {
    tw.flex, tw.col, tw.gap.y[4],
    ui.text "Ready",
}
```

Builds `Auth.Box { id, styles, children }`.

Accepted array entries:

| Entry | Meaning |
| --- | --- |
| style token/group/list | appended to box style list |
| authored node | appended to children |
| string/number | converted to anonymous `Auth.Text` |
| nil/false | ignored |

Named fields:

| Field | Meaning |
| --- | --- |
| `id` | dynamic id |
| `style`, `styles` | token/group/list/table added before array styles |

### `ui.text`

```lua
ui.text "Ready"
ui.text "Ready" { tw.text.lg, tw.font.semibold }
ui.text { id = "title", content = dynamic_title, tw.fg.white }
```

Builds `Auth.Text { id, styles, content }`.

When staged with a string and used as a child, `ui.text "Ready"` finalizes to a
text node automatically.

### `ui.text_ref`

```lua
ui.text_ref "patch_name" { tw.fg.white }
ui.text_ref { content_id = dynamic_content_id, styles = title_styles }
```

Builds `Auth.TextRef { id, styles, content_id }`.

Use this when content is retained in the kernel/resource layer and the authored
tree should reference it by id.

### `ui.paint`

`ui.paint` is both an authored paint-node builder and a paint-program namespace.

```lua
local scope = ui.paint "scope" {
    tw.w.fill, tw.h[120],
    ui.paint.polyline {
        points = samples,
        stroke = ui.paint.stroke { color = 0xff66ccff, width = 1.5 },
    },
}
```

Builds `Auth.Paint { id, styles, paint = Paint.ProgramList }`.

### `ui.fragment`

```lua
ui.fragment {
    ui.text "A",
    maybe_node,
    ui.text "B",
}
```

Builds `Auth.Fragment { children }`.

## Wrappers

Wrappers take one child through `child`, `node`, `body`, or `content`.

### `ui.scroll`

```lua
ui.scroll.y "preset_list" { tw.h[240], child = list }
ui.scroll.x { id = dynamic_id, child = row }
ui.scroll.both "canvas" { child = canvas }
```

Builds `Auth.Scroll`. Variants:

| Variant | Axis |
| --- | --- |
| `x` | `Style.ScrollX` |
| `y` | `Style.ScrollY` |
| `both`, `xy` | `Style.ScrollBoth` |

### `ui.input`

```lua
ui.input.activate "save" { child = button }
ui.input.hit "row:42" { child = row }
ui.input.focus "field" { child = field }
ui.input.edit "name" { child = editor }
ui.input.passive "bg" { child = background }
```

Builds `Auth.WithInput`. Variants map to `Interact.Role`.

### Drag And Drop

```lua
ui.drag.source "osc_handle" { child = handle }
ui.drop.target "rack" { child = rack }
ui.drop.slot "slot:1" { child = slot }
```

Builds `Auth.WithDragSource`, `Auth.WithDropTarget`, or
`Auth.WithDropSlot`.

### Focus, State, Layers

```lua
ui.focus.scope "main" { trap = true, child = root }
ui.state { selected = true, child = row }
ui.layer.popup "menu_layer" { order = 20, child = menu }
ui.overlay "menu" { anchor = "button", placement = ui.place.below, child = menu }
ui.modal "settings" { child = settings }
```

Layer variants include `base`, `popup`, `tooltip`, `modal`, and
`drag_preview`.

Overlay placements:

```lua
ui.place.auto
ui.place.above
ui.place.below
ui.place.left
ui.place.right
ui.place.center
```

## Compose

Compose values are separate from auth nodes.

```lua
ui.compose.panel "transport" {
    header = ui.text "Transport",
    body = transport_body,
}

ui.compose.scroll_panel "browser" {
    header = ui.text "Presets",
    body = preset_list,
}

ui.compose.hsplit "workspace" {
    browser_panel,
    editor_panel,
}

ui.compose.vsplit "stack" {
    top_panel,
    bottom_panel,
}

ui.compose.workbench "synth" {
    toolbar = toolbar,
    sidebar = browser,
    main = editor,
    bottom = modulation,
}
```

Auth nodes passed to compose fields are wrapped as `Compose.Raw`.

## Style Tokens

`ui.tw` produces typed `Style.Token`, `Style.Group`, and `Style.TokenList`
values. It is not CSS string parsing.

Common tokens:

```lua
tw.flex
tw.grid
tw.flow
tw.row
tw.col
tw.wrap
tw.nowrap

tw.p[4]
tw.px[4]
tw.py[2]
tw.m[2]
tw.gap[4]
tw.gap.x[2]
tw.gap.y[6]

tw.w.fill
tw.w.hug
tw.w.auto
tw.w[120]
tw.w.frac["1/2"]
tw.h[240]

tw.grow[1]
tw.shrink[0]
tw.basis[160]

tw.items.center
tw.justify.between
tw.self.stretch

tw.bg.slate[950]
tw.fg.white
tw.border_color.sky[400]
tw.border[1]
tw.rounded.lg
tw.opacity[80]

tw.text.lg
tw.text.center
tw.font.semibold
tw.cursor.pointer
```

Conditional groups:

```lua
tw.hover { tw.bg.blue[600] }
tw.focus { tw.border_color.sky[400] }
tw.active { tw.opacity[90] }
tw.selected { tw.bg.slate[800] }
tw.disabled { tw.opacity[40] }
tw.dark { tw.bg.slate[950], tw.fg.white }
tw.md { tw.row, tw.gap.x[6] }
```

Utilities:

```lua
tw.group { token_a, token_b }
tw.list { token_a, token_b }
tw.state { hovered = true, selected = true }
```

## Paint Programs

```lua
ui.paint.stroke { color = 0xff66ccff, width = 1.5 }
ui.paint.fill { color = 0xff101827 }
ui.paint.line { x1 = 0, y1 = 0, x2 = 100, y2 = 20 }
ui.paint.polyline { points = { 0, 0, 10, 8, 20, 0 } }
ui.paint.polygon { points = points, fill = ui.paint.fill { color = color } }
ui.paint.circle { cx = 24, cy = 24, r = 8 }
ui.paint.arc { cx = 24, cy = 24, r = 8, a1 = 0, a2 = 3.14 }
ui.paint.bezier { points = points, segments = 24 }
ui.paint.vertex { x = 0, y = 0, u = 0, v = 0 }
ui.paint.mesh { vertices = vertices, image_id = "atlas" }
ui.paint.image { image = "logo", src_w = 128, src_h = 64 }
```

## Widgets

The current MLUI package includes a small canonical widget showcase.

```lua
local save = W.button "save" {
    label = "Save",
    model = model,
    report = report,
}

root = ui.box "main" {
    save.node,
}
```

Widget bundles have:

```text
kind
id
node
surfaces
events
model
report
```

Widgets are data bundles. They do not call application callbacks.

## Program Encoding

```lua
local program = ui.program(root, { epoch = app.ui_epoch })
```

Returns a Lua table with row-shaped MLUI program sections:

```text
program.header
program.auth.nodes
program.auth.children
program.auth.styles.tokens
program.auth.styles.tracks
program.paint.programs
program.paint.points
program.resources.ids
program.resources.contents
```

`ui.encode` is an alias for `ui.program`.

The encoded program is the frontend contract for later native loading. It is
not the retained kernel itself.
