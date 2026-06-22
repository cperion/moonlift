# MLUI Usage Guide

Status: superseded by
[`experiments/mlui-llpvm/mlui_llpvm_stack_blueprint.md`](../mlui-llpvm/mlui_llpvm_stack_blueprint.md).
This file is retained as a historical guide for the pre-LLPVM Lua API. It is
not the current usage contract.

## Mental Model

```text
Lua API       builds authored MLUI ASDL
ui.program    compiles authored ASDL into an MLUI program object
bytecode      immutable borrowed MLUI image for VM import
UiKernel      retains validated/imported products and runs frame phases
backend       draws view ops and sends raw input
application   owns domain state
```

The Lua API is immediate-mode authoring. That does not mean the native VM
should be torn down every frame.

## The Rule

```text
Rebuild Lua authoring values freely.
Do not recreate the kernel every frame.
Do not validate/load a full program every frame unless the authored tree changed.
Do not recreate durable resources every frame.
```

MLUI is designed so a frame can be cheap:

```text
same loaded program + same retained kernel + new input/model/env
    -> solve/render/report/interact
```

Full program load is a compiler/import operation. Frame execution is the hot
runtime path.

The native-facing program artifact is the bytecode image:

```lua
local program = ui.program(root, { epoch = app.ui_epoch })
local bytes = program:bytecode()
local image, len = program:bytebuffer()
```

The buffer is caller-owned immutable memory. A borrowed native load API may keep
views into that buffer, so the caller must keep it alive while loaded roots or
program handles derived from it are live.

## Three Levels Of Reuse

### 1. Rebuild The Lua Tree

This is fine:

```lua
local function view(app)
    return ui.box "main" {
        tw.flex, tw.col,
        ui.text(app.title) { tw.text.lg },
        app.can_save and W.button "save" { label = "Save" }.node,
    }
end
```

Lua tree rebuilding is authoring work. The ASDL values are immutable and
interned by the Lua ASDL context.

### 2. Reuse The Encoded Program

If the authored shape and resources did not change, keep the encoded program:

```lua
local root = view(app)
local program = ui.program(root, { epoch = app.ui_epoch })
local image, len = program:bytebuffer()
```

Only rebuild `program` when one of these changes:

```text
authored tree shape
stable ids
style token lists
text literals embedded directly in Auth.Text
paint command rows
resource bindings
program epoch
```

If only pointer input, focus, hover, window size, scroll, or interaction model
changed, reuse the program.

### 3. Reuse The Native Kernel Load

The intended native pattern is:

```lua
local kernel = ui.kernel.open { ... }
local loaded = nil
local loaded_epoch = nil

local function ensure_loaded(app)
    if loaded == nil or loaded_epoch ~= app.ui_epoch then
        local root = view(app)
        local program = ui.program(root, { epoch = app.ui_epoch })
        local image, len = program:bytebuffer()
        loaded = kernel:load_program { image = image, len = len }
        loaded_epoch = app.ui_epoch
    end
    return loaded
end

local function frame(app, raw_input)
    local root_ref = ensure_loaded(app)
    return kernel:frame {
        root = root_ref,
        env = app.env,
        input = raw_input,
        model = app.ui_model,
    }
end
```

The exact native `kernel` methods are still the bridge/API layer, but this is
the ownership discipline the implementation must preserve.

## Avoid The Slow Path

Do not do this as a normal frame loop:

```lua
while running do
    local root = view(app)
    local program = ui.program(root)
    local image, len = program:bytebuffer()
    local kernel = ui.kernel.open {}
    local loaded = kernel:load_program { image = image, len = len }
    local frame = kernel:frame { root = loaded, input = raw_input }
    kernel:close()
end
```

That performs allocator setup, program encode, validation, import, store
creation, frame execution, and teardown every frame.

Do this instead:

```lua
local kernel = ui.kernel.open {}
local loaded = nil

while running do
    if app.ui_dirty then
        local root = view(app)
        local program = ui.program(root, { epoch = app.ui_epoch })
        local image, len = program:bytebuffer()
        loaded = kernel:load_program { image = image, len = len }
        app.ui_dirty = false
    end

    local frame = kernel:frame {
        root = loaded,
        env = app.env,
        input = raw_input,
        model = app.ui_model,
    }

    draw(frame.ops)
    app.ui_model = frame.model
    apply_events(app, frame.events)
end
```

## What Marks UI Dirty

Use explicit epochs. Do not guess from Lua object identity.

Recommended app state:

```lua
local app = {
    ui_epoch = 1,
    text_epoch = 1,
    paint_epoch = 1,
    theme_epoch = 1,
    ui_dirty = true,
}
```

Increment `ui_epoch` when:

```text
node count changes
child order changes
node kind changes
ids change
style token lists change
literal Auth.Text content changes
paint command structure changes
compose structure changes
```

Do not increment `ui_epoch` for:

```text
pointer move
hover/focus/active state
scroll offsets
window size
raw keyboard input
interaction model changes
domain values not reflected in authored tree
```

Use separate resource epochs for retained content:

```lua
ui.text_ref "patch_name" {
    content_id = "patch_name",
}
```

The content store can update `"patch_name"` with `text_epoch` without making
the whole authored tree structurally dirty.

## Text Strategy

Use `ui.text` for small literal labels that are genuinely part of the authored
tree:

```lua
ui.text "Save"
```

Use `ui.text_ref` for dynamic, large, or frequently changing text:

```lua
ui.text_ref "patch_name" { tw.font.semibold }
```

Then update the retained content store separately:

```text
retain/copy text bytes
publish content ref
increment content epoch
text layout cache sees stale text product
auth program stays loaded
```

This avoids full program reload for text edits, meters, logs, and labels that
change often.

## Paint Strategy

Use authored paint commands for stable paint structure:

```lua
ui.paint "scope" {
    tw.w.fill, tw.h[120],
    ui.paint.polyline {
        points = static_points,
        stroke = ui.paint.stroke { color = 0xff66ccff, width = 1.25 },
    },
}
```

For high-frequency data such as oscilloscope samples, prefer retained paint
resources:

```text
Auth.Paint references a stable paint/content id
sample buffer updates through resource protocol
paint epoch changes
program stays loaded
render product invalidates only where needed
```

Do not encode thousands of changing points into a new full auth program every
frame unless the benchmark is intentionally measuring rebuild cost.

## Stable IDs

Stable ids are the cache key boundary:

```lua
ui.box "transport" { ... }
W.button "save" { label = "Save" }
ui.scroll.y "preset_list" { child = presets }
```

Bad:

```lua
ui.box(tostring(os.clock())) { ... }
```

Good dynamic ids:

```lua
ui.box { id = "row:" .. row.id, child }
```

The same semantic object should get the same id across frames.

## Retained Kernel Products

The native kernel should retain these products behind explicit protocols:

```text
imported authored nodes
style resolution products
text content and text layout
paint programs/resources
measurements
solve placements
view op buffers
runtime reports
interaction model
event buffers
```

The Lua API does not own those resources. It only names them through ASDL facts
and program rows.

## Frame Shape

The hot frame should look like:

```text
borrow loaded root
read env/input/model
resolve stale style/text/paint products only
measure/solve/render/report/interact
return borrowed output buffers valid until next frame
```

It should not look like:

```text
parse/build all Lua
encode all rows
validate all rows
import all rows
allocate all stores
then frame
then free everything
```

## Bench Discipline

Use two benchmark modes and name them honestly:

| Mode | Measures |
| --- | --- |
| retained frame | real hot path: loaded program + persistent kernel |
| rebuild/load | frontend rebuild + validation/import + frame |

Compare retained-frame numbers to retained/immediate UI runtimes. Compare
rebuild/load numbers only when the competing system also rebuilds and validates
equivalent semantic data.

For MLUI, the retained frame is the target path. Rebuild/load is still useful
for editor tools, generated assets, hot reload, and stress testing, but it is
not the normal frame cost.

## Practical Pattern

```lua
local ui = require "mlui"
local tw = ui.tw
local W = ui.widgets

local app = {
    ui_epoch = 1,
    ui_dirty = true,
    ui_model = nil,
}

local function view(app)
    local save = W.button "save" {
        label = "Save",
        model = app.ui_model,
    }

    return ui.box "main" {
        tw.flex, tw.col, tw.gap.y[4], tw.p[6],
        ui.text "Patch",
        save.node,
    }
end

local loaded_epoch = nil
local loaded_root = nil

local function ensure_program(kernel, app)
    if loaded_root == nil or loaded_epoch ~= app.ui_epoch then
        local root = view(app)
        local program = ui.program(root, { epoch = app.ui_epoch })
        local image, len = program:bytebuffer()
        loaded_root = kernel:load_program { image = image, len = len }
        loaded_epoch = app.ui_epoch
    end
    return loaded_root
end

local function step(kernel, app, raw_input)
    local root = ensure_program(kernel, app)
    local frame = kernel:frame {
        root = root,
        env = app.env,
        input = raw_input,
        model = app.ui_model,
    }
    app.ui_model = frame.model
    return frame
end
```

The current Lua package already supplies the authoring and program encoding
side. The native kernel bridge must implement this retained/load discipline
instead of hiding full rebuilds inside `frame`.
