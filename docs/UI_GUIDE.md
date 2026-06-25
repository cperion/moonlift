# Lalin UI Guide

The UI package under `lua/ui` is a Lalin-family application layer. It is kept in
the main tree because it exercises the same principles as the compiler:
explicit products, typed phases, stable IDs, process-shaped inspection, and
backend contracts.

## Pipeline

```text
authored tree
  -> normalized UI tree
  -> measured layout
  -> solved layout
  -> render ops
  -> backend runtime
  -> interaction report
  -> next authored tree
```

The authored tree is user-facing. The solved layout and render ops are compiler
products. Backend reports and input events feed the next frame.

## Contracts

Stable IDs are required for stateful widgets. A widget that owns focus, text
editing state, scroll position, drag capture, popup state, or animation state
must have a stable ID.

Input is normalized before widget logic sees it. Backends should report a small
host-independent input product:

- pointer position and buttons
- keyboard text and key events
- focus changes
- wheel/scroll motion
- window size and scale

Rendering is expressed as ops, not backend calls hidden in widgets. Backends own
the translation from ops to SDL3, Love2D, or another host.

## Widgets

Widget bundles should expose:

- a pure authored value
- an event product
- a reducer or state update contract
- render/layout behavior through the shared UI pipeline

Do not hide state in widget-local globals. State belongs in the app model or in
explicit UI runtime state keyed by stable IDs.

## Backends

Backend modules live under `lua/ui/backends`. A backend should provide:

- runtime creation and teardown
- host event polling
- normalized input conversion
- render op execution
- text measurement and shaping support where available
- capability metadata

Backend-specific behavior must be explicit in capability records. App-facing
code should not branch on backend module names.

## Performance

The UI system should preserve three separate products:

```text
structure       what widgets exist
layout          where boxes and text runs are
dynamic display what changes every frame
```

Rebuilding a small authored tree is acceptable. Recomputing text shaping,
layout, and backend resources without a structural reason is not.

Cache keys should be typed products. Do not smuggle layout or paint decisions
through string keys.

## Tests

Useful UI checks:

```sh
luajit tests/run.lua ui
luajit tests/ui/test_ui_smoke.lua
luajit tests/ui/test_ui_text_session.lua
luajit tests/ui/test_ui_backend_contract.lua
```

UI tests should cover:

- ID validation
- state bridge behavior
- layout golden cases
- overlay/layer ordering
- text session behavior
- backend contract conformance
