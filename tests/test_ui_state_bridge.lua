package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local Core = T.Core
local Style = T.Style
local Auth = T.Auth
local Interact = T.Interact
local b = ui.build
local tw = ui.tw
local state = ui.state
local ids = ui.id
local W = ui.widgets

local theme = ui.theme.default()
local env = ui.theme.env_for_width(400)

local function empty_report(opts)
    opts = opts or {}
    return Interact.Report(
        opts.hover_id or Core.NoId,
        Core.NoId,
        Style.CursorDefault,
        Core.NoId,
        opts.hits or {},
        opts.focusables or {},
        opts.scrollables or {},
        opts.drag_sources or {},
        opts.drop_targets or {},
        opts.drop_slots or {},
        opts.hit_stack or {},
        opts.layers or {},
        opts.overlays or {},
        opts.modal_barriers or {},
        opts.focus_scopes or {}
    )
end

local function one_layout(node, opts)
    local out = ui.lower.root(node, theme, env, opts)
    assert(#out == 1, "expected one lowered node, got " .. #out)
    return out[1]
end

local function box_visual(layout)
    if layout.box ~= nil then return layout.box.box_visual end
    if layout.child ~= nil then return box_visual(layout.child) end
    error("layout has no box visual: " .. tostring(pvm.classof(layout)))
end

local function box_cursor(layout)
    if layout.box ~= nil then return layout.box.cursor end
    if layout.child ~= nil then return box_cursor(layout.child) end
    error("layout has no box cursor: " .. tostring(pvm.classof(layout)))
end

local function root_box(id_value)
    return b.box {
        b.id(id_value),
        tw.w_px(20), tw.h_px(20),
        tw.bg.slate[800],
        tw.border_1,
        tw.border_color.slate[900],
        tw.hover { tw.bg.slate[700] },
        tw.focus { tw.border_color.sky[400] },
        tw.active { tw.bg.slate[950] },
        tw.selected { tw.bg.sky[700] },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    }
end

-- Low-level state derivation combines report hover, model focus/press/capture,
-- drag state, and app-provided selected/disabled/active maps.
do
    local target = ids.id("target")
    local model = ui.interact.model {
        focus_id = target,
        capture = Interact.Captured(target, 0, 0),
        pressed_id = Core.NoId,
        drag = Interact.DragPending(target, 0, 0),
    }
    local report = empty_report { hover_id = target }
    local s = state.for_id(target, model, report, {
        selected = { target = true },
        disabled = function(_, key) return key == "target" end,
    })
    assert(s.hovered and s.focused and s.active and s.selected and s.disabled, "state.for_id derives all flags for target")

    local other = state.for_id(ids.id("other"), model, report, {
        selected_ids = { target = true },
        disabled_ids = { target = true },
        active_ids = { target = true },
    })
    assert(not other.hovered and not other.focused and not other.active and not other.selected and not other.disabled,
        "state.for_id does not contaminate other IDs")
end

-- Derived hover/focus/active/selected/disabled state changes style resolution
-- during lower.root.
do
    local node = root_box("target")
    local base = box_visual(one_layout(node))
    local hover = box_visual(one_layout(node, { report = empty_report { hover_id = ids.id("target") } }))
    assert(hover.bg ~= base.bg, "hover state changes resolved background")

    local focused = box_visual(one_layout(node, { model = ui.interact.model { focus_id = ids.id("target") } }))
    assert(focused.border_color ~= base.border_color, "focus state changes resolved border color")

    local active = box_visual(one_layout(node, { model = ui.interact.model { pressed_id = ids.id("target") } }))
    assert(active.bg ~= base.bg and active.bg ~= hover.bg, "active state resolves active background")

    local selected = box_visual(one_layout(node, { selected = { target = true } }))
    assert(selected.bg ~= base.bg and selected.bg ~= hover.bg and selected.bg ~= active.bg, "selected state resolves selected background")

    local disabled = box_visual(one_layout(node, { disabled = true }))
    assert(disabled.opacity == 50, "boolean disabled option applies disabled state to target")
    assert(box_cursor(one_layout(node, { disabled = true })) == Style.CursorNotAllowed, "disabled cursor style resolves")
end

-- Explicit Auth.WithState is merged with derived state rather than replacing it:
-- this node should get hover background from the report and focus border from
-- the explicit authored wrapper.
do
    local node = Auth.WithState(Style.State(false, true, false, false, false), root_box("merge"))
    local base = box_visual(one_layout(root_box("merge")))
    local merged = box_visual(one_layout(node, { report = empty_report { hover_id = ids.id("merge") } }))
    assert(merged.bg ~= base.bg, "derived hover survives explicit WithState")
    assert(merged.border_color ~= base.border_color, "explicit focus survives derived hover")
end

-- apply_to_auth wraps only non-empty derived states by default, can wrap empty
-- states when requested, and safely passes through Auth.Empty singletons.
do
    local provider = state.provider(ui.interact.model { focus_id = ids.id("a") }, empty_report(), nil)
    local node = b.fragment { b.box { b.id("a") }, b.box { b.id("b") }, b.empty }
    local applied = state.apply_to_auth(node, provider)
    assert(pvm.classof(applied) == Auth.Fragment, "apply_to_auth preserves fragment")
    assert(pvm.classof(applied.children[1]) == Auth.WithState, "matching ID is wrapped with state")
    assert(pvm.classof(applied.children[2]) == Auth.Box, "nonmatching ID is not wrapped by empty state")
    assert(applied.children[3] == Auth.Empty, "Auth.Empty passes through state bridge")

    local wrap_empty = state.apply_to_auth(b.box { b.id("c") }, provider, { wrap_empty = true })
    assert(pvm.classof(wrap_empty) == Auth.WithState, "wrap_empty forces an explicit no-state wrapper")
end

-- Per-ID maps do not leak across siblings during lowering.  Only the selected
-- row receives selected styling.
do
    local node = b.box {
        b.id("root"),
        tw.flex, tw.row,
        b.box { b.id("a"), tw.bg.slate[800], tw.selected { tw.bg.sky[600] } },
        b.box { b.id("b"), tw.bg.slate[800], tw.selected { tw.bg.sky[600] } },
    }
    local layout = one_layout(node, { selected_ids = { a = true } })
    local a_bg = layout.children[1].box.box_visual.bg
    local b_bg = layout.children[2].box.box_visual.bg
    assert(a_bg ~= b_bg, "selected state applies only to selected ID")
end

-- Widget-level opts feed the same state bridge.  Disabled buttons resolve their
-- disabled style and suppress routed events; selected toggles advertise selected
-- bundle state and route activation to a boolean change.
do
    local button = W.button.bundle { id = "disabled-button", label = "Disabled", disabled = true }
    assert(button.disabled == true, "disabled button bundle records disabled flag")
    local visual = box_visual(one_layout(button.node))
    assert(visual.opacity == 50, "disabled button node resolves disabled opacity")
    local ev = button:route_ui_event(Interact.Activate(ids.id("disabled-button")))
    assert(ev == nil, "disabled widget bundle suppresses routed events by default")

    local toggle = W.toggle.bundle { id = "power", label = "Power", selected = true }
    assert(toggle.selected == true, "selected toggle bundle exposes selected state")
    local routed = toggle:route_ui_event(Interact.Activate(ids.id("power")))
    assert(routed ~= nil and routed.kind == "change" and routed.value == false, "selected toggle activation routes to inverted boolean value")
end

print("ok test_ui_state_bridge")
