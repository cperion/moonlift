package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local Core = T.Core
local Style = T.Style
local Layout = T.Layout
local View = T.View
local Interact = T.Interact
local Auth = T.Auth
local b = ui.build
local tw = ui.tw
local ids = ui.id
local W = ui.widgets

local theme = ui.theme.default()
local env = ui.theme.env { width = 300, height = 200 }
local solve_env = T.Solve.Env(300, 200, {})

local function op(kind, id, x, y, w, h, dx, dy, layer_kind, focus_policy, placement, modal, anchor_id, order)
    return View.Op(kind, id or Core.NoId, x or 0, y or 0, w or 0, h or 0, dx or 0, dy or 0, nil, nil, nil, nil, nil, layer_kind, focus_policy, placement, modal, anchor_id, order)
end

local function run_ops(ops, pointer_x, pointer_y)
    local g, p, c = pvm.seq(ops)
    return ui.runtime.run(nil, { pointer_x = pointer_x, pointer_y = pointer_y }, g, p, c)
end

local function render_report(auth, pointer_x, pointer_y)
    local lowered = ui.lower.root(auth, theme, env)
    assert(#lowered == 1, "expected one lowered root")
    local rg, rp, rc = ui.render.root(lowered[1], solve_env)
    return ui.runtime.run(nil, { pointer_x = pointer_x, pointer_y = pointer_y }, rg, rp, rc)
end

local function key(id) return ids.key(id) end
local function has_id(list, wanted)
    local wk = key(wanted)
    for i = 1, #list do
        if key(list[i].id) == wk then return list[i], i end
    end
    return nil
end

-- Layer metadata survives render/runtime, including explicit kind and order.
-- Drag-preview layers can carry ordinary drag facts inside the same op stream.
do
    local base_layer = ids.id("base-layer")
    local preview_layer = ids.id("preview-layer")
    local drag_id = ids.id("preview-drag")
    local auth = b.box {
        b.id("root"),
        tw.w_px(160), tw.h_px(120), tw.flex, tw.col,
        Auth.Layer(base_layer, Interact.LayerBase, 0,
            b.with_input(b.id("base-button"), Interact.ActivateTarget,
                b.box { b.id("base-box"), tw.w_px(80), tw.h_px(30) })),
        Auth.Layer(preview_layer, Interact.LayerDragPreview, 100,
            b.drag_source(drag_id,
                b.box { b.id("preview-box"), tw.w_px(80), tw.h_px(30) })),
    }
    local report = render_report(auth, 5, 35)
    local base = has_id(report.layers, base_layer)
    local preview = has_id(report.layers, preview_layer)
    assert(base and base.kind == Interact.LayerBase and base.order == 0, "base layer kind/order reported")
    assert(preview and preview.kind == Interact.LayerDragPreview and preview.order == 100, "drag preview layer kind/order reported")
    assert(has_id(report.drag_sources, drag_id), "drag preview layer contains drag source facts")
end

-- Runtime modal barriers clear lower-layer hit/focus/scroll facts when the
-- pointer is within the barrier.  Later modal child hits/focus are then the only
-- interactive facts visible to the reducer.
do
    local lower = ids.id("lower")
    local modal = ids.id("modal")
    local barrier = ids.id("barrier")
    local scope = ids.id("modal-scope")
    local scroll_id = ids.id("lower-scroll")
    local ops = {
        op(View.KHit, lower, 0, 0, 200, 200),
        op(View.KFocus, lower, 0, 0, 200, 30),
        op(View.KPushScroll, scroll_id, 0, 0, 200, 100, 200, 400, nil, nil, nil, nil),
        op(View.KPopScroll, scroll_id, 0, 0, 0, 0),
        op(View.KPushLayer, ids.id("modal-layer"), 0, 0, 200, 200, 0, 0, Interact.LayerModal, nil, nil, nil, nil, 100),
        op(View.KModalBarrier, barrier, 0, 0, 200, 200),
        op(View.KFocusScope, scope, 0, 0, 200, 200, 0, 0, nil, Interact.FocusTrap),
        op(View.KHit, modal, 50, 50, 80, 40),
        op(View.KFocus, modal, 50, 50, 80, 40),
        op(View.KEndFocusScope, scope, 0, 0, 200, 200),
        op(View.KPopLayer, ids.id("modal-layer"), 0, 0, 200, 200),
    }

    local outside_child = run_ops(ops, 10, 10)
    assert(outside_child.hover_id == Core.NoId, "modal barrier clears lower hover outside modal child")
    assert(not has_id(outside_child.hits, lower) and has_id(outside_child.hits, modal), "modal barrier clears lower hits while preserving modal child facts")
    assert(not has_id(outside_child.focusables, lower) and has_id(outside_child.focusables, modal), "modal barrier clears lower focus while preserving modal focus facts")
    assert(outside_child.scroll_id == Core.NoId and #outside_child.scrollables == 0, "modal barrier clears lower scroll facts")
    assert(#outside_child.modal_barriers == 1 and outside_child.modal_barriers[1].id == barrier, "modal barrier fact is reported")

    local inside_child = run_ops(ops, 60, 60)
    assert(inside_child.hover_id == modal, "modal child receives hover after barrier")
    assert(#inside_child.hits == 1 and inside_child.hits[1].id == modal, "only modal hit remains after barrier")
    assert(#inside_child.focusables == 1 and inside_child.focusables[1].id == modal, "only modal focus remains after barrier")
    assert(#inside_child.focus_scopes == 1 and inside_child.focus_scopes[1].id == scope, "focus scope fact is reported")
    assert(inside_child.focus_scopes[1].policy == Interact.FocusTrap, "focus trap policy survives render/runtime")

    local model, events = ui.interact.step(ui.interact.model(), inside_child, ui.interact.focus_next())
    assert(model.focus_id == modal and #events == 1 and events[1].id == modal, "focus traversal is trapped by filtered modal focusables")
end

-- Explicit sibling layers can be emitted after a clipped subtree without
-- weakening clipping globally: the clipped hit is discarded, while the later
-- layer hit outside that clip is visible.
do
    local clipped = ids.id("clipped-hit")
    local overlay = ids.id("overlay-hit")
    local ops = {
        op(View.KPushClipRect, ids.id("clip"), 0, 0, 20, 20),
        op(View.KHit, clipped, 30, 30, 20, 20),
        op(View.KPopClip, ids.id("clip"), 0, 0, 0, 0),
        op(View.KPushLayer, ids.id("overlay-layer"), 0, 0, 100, 100, 0, 0, Interact.LayerOverlay, nil, nil, nil, nil, 50),
        op(View.KHit, overlay, 30, 30, 20, 20),
        op(View.KPopLayer, ids.id("overlay-layer"), 0, 0, 100, 100),
    }
    local report = run_ops(ops, 35, 35)
    assert(not has_id(report.hits, clipped), "clipped hit outside clip is not reported")
    assert(has_id(report.hits, overlay), "explicit sibling overlay layer hit is reported outside prior clip")
    assert(report.hover_id == overlay, "overlay hit controls hover")
end

-- Popup/popover/modal close routing: outside-click policy is represented as a
-- cancel raw/event at the widget boundary; Escape follows the same close path.
do
    local pop = W.popover.bundle { id = "filters-popover", open = true, content = "Filters" }
    local cancel_ev = pop:route_ui_event(Interact.CancelPointer)
    assert(cancel_ev ~= nil and cancel_ev.kind == "close" and cancel_ev.reason == "cancel", "popover routes outside cancel to close")
    local escape_ev = pop:route_ui_event(Interact.KeyPressed(Interact.KeyEscape, Interact.Modifiers(false, false, false, false), false))
    assert(escape_ev ~= nil and escape_ev.kind == "close" and escape_ev.reason == "escape", "popover routes Escape to close")

    local modal = W.modal.bundle { id = "confirm", open = true, title = "Confirm", body = "Continue?", close_label = "Close" }
    local close_id = ui.widget.child_id(modal.id, "close")
    local close_ev = modal:route_ui_event(Interact.Activate(close_id))
    assert(close_ev ~= nil and close_ev.kind == "close" and close_ev.reason == "button", "modal close button routes close event")
end

-- Tooltip overlays are passive: they produce layer/overlay facts with tooltip
-- kind, but no hit/focus targets when their content contains no input wrapper.
do
    local tooltip = W.tooltip.bundle { id = "gain-tip", open = true, content = "Gain in dB" }
    local report = render_report(tooltip.node, 5, 5)
    local layer = has_id(report.layers, ui.widget.child_id(tooltip.id, "layer"))
    local overlay = has_id(report.overlays, ui.widget.child_id(tooltip.id, "overlay"))
    assert(layer and layer.kind == Interact.LayerTooltip, "tooltip reports tooltip layer kind")
    assert(overlay and overlay.modal == false and overlay.placement == Interact.PlaceAbove, "tooltip overlay is passive/non-modal with placement")
    assert(#report.hits == 0 and #report.focusables == 0, "tooltip content has no passive hit/focus targets")
end

print("ok test_ui_overlay_layers")
