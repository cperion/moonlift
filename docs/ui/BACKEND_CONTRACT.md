# Lalin UI Backend Contract

This document defines the contract between the typed UI kernel and concrete
platform backends. Backends draw typed `View.Op` streams, normalize host input,
provide text systems, and expose platform lifecycle services. They do not define
application semantics: focus, activation, pointer capture, drag/drop, modal
routing, widget events, and style state are kernel contracts described in
`CONTRACT.md`.

The current supported backend families are:

- SDL3: `ui.backends.sdl3`, `ui.host_sdl3`, `ui.runtime_sdl3`, `ui.text_sdl3`.
- Love: `ui.runtime_love` and `ui.text_love` where Love remains product-supported.

A backend may be partial only when its capability metadata and documentation say
so explicitly. Declared primitives must not silently no-op.

## 1. Backend package shape

A product backend module exposes a table with stable fields:

```lua
{
  name = "sdl3",
  ffi = optional_ffi_module,
  host = host_module,
  runtime = runtime_driver_module,
  text = text_system_module,
  new_host = function(opts) -> host,
  new_text_system = function(opts) -> text_system,
  poll_events = function() -> host_event[],
  filter_events = function(host_or_window_id, events) -> host_event[],
  partition_events = function(events) -> { global = ..., [window_id] = ... },
  capabilities = capabilities_table,
}
```

Compatibility modules may re-export older paths, but app-facing code should prefer
`ui.backends.<name>`, `ui.session`, `ui.input`, `ui.runtime`, and `ui.text`.

## 2. Runtime driver interface

`ui.runtime.run(driver, opts, g, p, c)` is the generic op-stream consumer. The
runtime owns transform, clip, scroll, hit testing, focus collection, cursor
selection, drag/drop facts, layer/modal facts, and report construction. The driver
owns drawing and platform cursor state.

A runtime driver is an object returned by `backend.runtime.new(opts)` and supports
these methods:

### Required drawing methods

```lua
driver:draw_box(x, y, w, h, box_visual)
-- or compatibility alias:
driver:draw_rect(x, y, w, h, box_visual)

driver:draw_text(x, y, w, h, text_layout)

driver:draw_paint(x, y, w, h, paint_program_list)
```

`draw_box`/`draw_rect` draws `Resolved.BoxVisual` including background, border,
shape, radius, and opacity. `draw_text` draws a measured `Layout.TextLayout`.
`draw_paint` draws a typed `Paint.ProgramList`. Coordinates are absolute after
generic runtime transform/scroll application. The driver must not apply semantic
hit/focus logic.

### Required clipping methods

```lua
driver:push_clip_rect(x, y, w, h)
driver:pop_clip_rect()
```

Compatibility aliases `push_clip`/`pop_clip` may remain supported. Clip calls are
balanced and nested. The generic runtime computes clip intersections before
calling the driver; the driver applies the platform clip region exactly as given.

### Optional cursor/layer methods

```lua
driver:set_cursor_kind(style_cursor)
driver:push_layer(layer_info)       -- optional
driver:pop_layer(layer_info)        -- optional
```

Cursor changes are advisory platform side effects; the kernel-selected cursor is
also returned in `Interact.Report`. Layer hooks are optional when the generic
runtime can express layers by op order and clipping alone. If a backend requires a
separate render target or compositor for layers, it must expose that behavior as a
capability and still preserve the typed layer contract.

### Error behavior

Backend failures that prevent a declared operation from being drawn must raise a
clear error or return a documented diagnostic. Missing images/fonts/resources may
skip only when the contract for that resource says unresolved resources are
optional; otherwise they fail loud.

## 3. Render-op semantics

Drivers receive operations only through `ui.runtime`; they do not inspect authored
or layout trees directly.

### Coordinate system

- `View.Op` coordinates are local to the current transform.
- Runtime converts them to absolute driver coordinates.
- Scroll offsets are applied by runtime when entering `KPushScroll`.
- Drivers must not apply additional layout transforms unless an explicit backend
  option documents a device transform such as density scaling.

### Clipping and scrolling

- `KPushClipRect` pushes an intersected clip rectangle.
- `KPushScroll` pushes a clip rectangle and subtracts the current scroll offset
  from subsequent child coordinates.
- Visual drawing and semantic report facts are both clipped by the active stack.
- Pop operations restore the previous driver clip.

### Layers, overlays, and modals

When the ASDL/view vocabulary includes layer and modal ops:

- layer push/pop preserves deterministic z-order;
- modal barriers block lower-layer interaction facts in runtime reports;
- lower-layer drawing remains visible unless explicitly obscured by authored UI;
- backends may use native/composited layers only as an implementation detail.

No backend may implement popups, tooltips, menus, or modals as untyped host-only
windows unless that host window is still represented by typed UI/session state.

## 4. Box drawing contract

`draw_box` receives `Resolved.BoxVisual`:

- `bg`: RGBA8 background color, transparent/zero means no fill;
- `border_color`: RGBA8 border color, transparent/zero means no border;
- `border_w`: border width in logical pixels;
- `shape`: rect, round-rect, or capsule;
- `radius`: resolved round-rect radius in logical pixels;
- `opacity`: resolved opacity percentage or normalized equivalent.

Backends must support rectangular boxes. Rounded rectangles and capsules are
required for product SDL3 support and required for Love if Love remains supported.
If a backend cannot draw a shape exactly, it must document the approximation in
capabilities and conformance tests.

Borders are drawn inside the box bounds. Negative or zero width/height draws
nothing.

## 5. Text drawing and text system contract

Text drawing and text measurement are separate but must agree on layout facts.

A text system implements the `ui.text` measuring/hit-testing contract:

- layout text into `Layout.TextLayout` with lines, runs, clusters, and boundaries;
- support wrapping under finite width constraints;
- expose hit testing and range queries required by text fields;
- honor resolved font id/size/weight, alignment, leading/tracking as far as the
  backend declares support;
- expose IME/script/direction options where the platform supports them.

`driver:draw_text` draws the exact `Layout.TextLayout` produced by the selected
text system. It must not re-wrap or re-measure with different constraints.

Session lifecycle:

- a session that creates a text system registers it with `ui.text` under a
  collision-free key;
- windows created by that session know the active text key/system;
- missing text registration does not silently select approximate layout unless the
  caller explicitly requested approximate fallback;
- close/unregister releases owned text systems and removes registry entries.

SDL3 text uses SDL_ttf and must support text measurement, line/range/hit queries,
clipboard-compatible editing flows, and IME composition rectangles. Love text may
be less capable only if marked optional with clear capability metadata.

## 6. Paint contract

`Paint.ProgramList` is typed drawing data, not a callback. Coordinates are local
to the paint node; runtime has already positioned the paint node when it calls the
driver.

Declared product paint primitives:

- line;
- polyline;
- polygon with fill and stroke;
- circle with fill and stroke;
- arc;
- bezier;
- mesh with triangle/strip/fan modes;
- image.

Stroke width, opacity, tint, and texture/image resolution are part of the drawing
contract. If a primitive is unsupported by a backend, the backend capability table
must mark it unsupported and conformance tests must assert the diagnostic path.
Product SDL3 support declares these primitives supported.

## 7. Image and mesh resource contract

Backends resolve image IDs through explicit options, not global hidden state:

```lua
runtime.new {
  images = { [id_string] = backend_image_or_spec },
  resolve_image = function(core_id) -> backend_image_or_spec end,
}
```

A backend image spec may be a loaded platform texture/image, a table wrapping that
resource, or a documented loadable path. SDL3 may load BMP paths where supported;
other formats require a documented image loader/resolver.

Unresolved images:

- for decorative optional paint images may skip drawing only if the primitive or
  caller explicitly allows missing resources;
- for required widget/content images must raise or report a diagnostic.

Meshes using an image ID follow the same resolution path. Untextured meshes must
render with vertex tint.

## 8. Host event normalization contract

Host modules convert native platform events into compatibility host tables and
canonical typed raw UI input.

A normalized host event keeps stable fields such as:

```lua
{ type = "mouse_pressed", window_id = id, x = x, y = y, button = "left" }
{ type = "key_down", window_id = id, key = "tab", shift = true, ctrl = false }
{ type = "text_input", window_id = id, text = text }
```

The canonical route also exposes `raw` or `raws` values produced by `ui.input`,
which are `Interact.Raw` ASDL values. Compatibility host tables may remain for
existing demos and widgets, but reducers and new widgets consume typed raw input.

Native constants stay inside the backend host layer. `ui.input` uses backend-
independent key/button/modifier names and typed constructors.

Window focus loss, pointer cancellation, text input, text editing/IME, resize,
close, and quit events must be normalized explicitly.

## 9. Host/window lifecycle contract

A host object created by `backend.new_host(opts)` owns one platform window and its
renderer/input services. Session code drives hosts through a stable lifecycle:

```lua
host:begin_frame(clear_color?)
host:present()
host:close()
host:now_ms() -> number
host:new_runtime_driver(opts) -> driver
```

Additional required or optional services:

```lua
host:set_title(title)
host:size() -> w, h
host:pixel_size() -> w, h
host:set_clipboard_text(text)
host:get_clipboard_text() -> text
host:set_text_input(active)
host:set_text_input_rect(x, y, w, h)
```

If a backend lacks a service, it must declare the missing capability. Text widgets
must be able to discover whether clipboard and IME/text-input rectangle services
are available.

The session loop owns dirty/timed redraw scheduling and event dispatch. Backends
must provide enough timing and event polling support for `redraw_mode = "dirty"`
and timed redraws to work deterministically.

## 10. HiDPI and density contract

The kernel environment includes `Env.Density`. A backend must document whether it
uses logical coordinates, physical pixels, or a scale transform.

Product rules:

- layout sizes are in logical pixels;
- host/window APIs expose both logical size and pixel size when the platform
  distinguishes them;
- text/font sizes and clip rectangles follow the same coordinate scale used by
  runtime drawing;
- any automatic density scaling is explicit in backend/session options and visible
  to tests.

A backend that ignores density must mark density as unsupported or no-op. It must
not partially scale text or images while leaving hit testing in another space.

## 11. Capability metadata

Each backend/runtime/text host advertises capabilities so tests and docs can make
truthful claims. Recommended shape:

```lua
capabilities = {
  runtime = {
    boxes = true,
    rounded_boxes = true,
    capsules = true,
    clipping = true,
    transforms = true,
    scrolling = true,
    layers = "generic" or true or false,
    cursors = true,
  },
  paint = {
    line = true,
    polyline = true,
    polygon_fill = true,
    circle_fill = true,
    arc = true,
    bezier = true,
    mesh = true,
    image = true,
    stroke_width = true,
  },
  text = {
    measure = true,
    draw = true,
    hit_test = true,
    ranges = true,
    ime = true,
    clipboard = true,
    shaping = "sdl_ttf" or "basic" or false,
  },
  host = {
    windows = true,
    multi_window = true,
    events = true,
    text_input_rect = true,
    clipboard = true,
    timers = true,
    hidpi = true or false,
  },
}
```

Capability values may be booleans or documented strings. Unsupported required
features fail conformance for product-supported backends.

## 12. SDL3 product contract

SDL3 is the primary product backend for synth UI readiness. It must provide:

- host window creation, event polling/partitioning/filtering, frame begin/present,
  close, timing, clipboard, text input, and IME rectangle support;
- normalized typed input for mouse, wheel, keyboard, text input/editing, focus,
  resize, close, and quit;
- runtime drawing for boxes, rounded boxes, capsules, text, all declared paint
  primitives, clipping, scrolling, cursors, image/mesh texture resolution;
- SDL_ttf-backed text measurement/drawing/hit testing/range queries;
- dummy-video compatible smoke tests where possible.

SDL3-specific constants, FFI types, and resource handles must stay behind SDL3
modules or explicit resolver options.

## 13. Love support contract

Love may remain supported as a secondary backend if it satisfies the same typed
runtime contract and advertises truthful capabilities. Love-specific behavior must
not become the public UI contract.

If Love cannot support a product feature such as SDL_ttf-quality text layout,
IME, clipboard, image resolver semantics, or overlays, the gap must be documented
in capability metadata and tests. If Love is not product-supported, public docs
must say it is legacy/experimental and conformance tests may skip it explicitly.

## 14. Backend conformance tests

Backend conformance tests verify the contract, not pixel-perfect aesthetics.
Required coverage:

- driver method presence and capability metadata;
- clip push/pop balancing and scroll clipping behavior;
- box shape/border/opacity smoke paths;
- each declared paint primitive and unresolved resource diagnostics;
- text registration, layout, draw smoke, hit/range APIs, and fallback policy;
- host event normalization to typed raw input;
- cursor setting path;
- window/session lifecycle, dirty/timed redraw, close/unregister cleanup;
- density coordinate consistency when density is enabled;
- dummy/headless SDL3 example runs.

Visual parity tests may use snapshots or probes, but pure runtime/report tests are
preferred for interaction facts. A backend is product-ready only when its declared
capabilities are covered by conformance tests.
