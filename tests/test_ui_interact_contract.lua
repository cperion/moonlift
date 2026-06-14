package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local Core = T.Core
local Style = T.Style
local I = T.Interact
local interact = ui.interact
local id = ui.id.id

local function report(opts)
    opts = opts or {}
    return I.Report(
        opts.hover_id or Core.NoId,
        opts.cursor_id or Core.NoId,
        opts.cursor or Style.CursorDefault,
        opts.scroll_id or Core.NoId,
        opts.hits or {},
        opts.focusables or {},
        opts.scrollables or {},
        opts.drag_sources or {},
        opts.drop_targets or {},
        opts.drop_slots or {},
        opts.hit_stack or opts.hits or {},
        opts.layers or {},
        opts.overlays or {},
        opts.modal_barriers or {},
        opts.focus_scopes or {}
    )
end

local function hit(name, x, y, w, h) return I.HitBox(id(name), x, y, w, h) end
local function focus(name, slot, x, y, w, h) return I.FocusBox(id(name), slot, x, y, w, h) end
local function scroll(name, axis, x, y, w, h, cw, ch) return I.ScrollBox(id(name), axis, x, y, w, h, cw, ch, math.max(0, cw - w), math.max(0, ch - h)) end
local function drag_source(name, x, y, w, h) return I.DragSourceBox(id(name), x, y, w, h) end
local function drop_target(name, x, y, w, h) return I.DropTargetBox(id(name), x, y, w, h) end
local function drop_slot(name, x, y, w, h) return I.DropSlotBox(id(name), x, y, w, h) end

local function classes(events)
    local out = {}
    for i = 1, #events do out[i] = pvm.classof(events[i]) or events[i] end
    return out
end

local function assert_class(event, cls, msg)
    assert((pvm.classof(event) or event) == cls, msg or ("expected " .. tostring(cls) .. ", got " .. tostring(pvm.classof(event) or event)))
end

local function assert_event_order(events, expected, label)
    local got = classes(events)
    assert(#got == #expected, (label or "event order") .. ": expected " .. #expected .. " events, got " .. #got)
    for i = 1, #expected do
        local want = pvm.classof(expected[i]) or expected[i]
        assert(got[i] == want, (label or "event order") .. ": event " .. i .. " expected " .. tostring(want) .. ", got " .. tostring(got[i]))
    end
end

-- Typed focus traversal skips disabled/unfocusable controls by relying on the
-- runtime report's focusable list.  The omitted middle control represents a
-- disabled surface that must not be reached by Tab or Shift+Tab.
do
    local r = report {
        focusables = {
            focus("first", 1, 0, 0, 10, 10),
            focus("third", 2, 20, 0, 10, 10),
        },
    }
    local m = interact.model()
    local next_model, events = interact.step(m, r, interact.key_pressed(I.KeyTab))
    assert_event_order(events, { I.SetFocus }, "tab focus")
    assert(next_model.focus_id == id("first"), "Tab focuses the first focusable")

    next_model, events = interact.step(next_model, r, interact.key_pressed(I.KeyTab))
    assert(next_model.focus_id == id("third"), "Tab advances to next reported focusable")

    next_model, events = interact.step(next_model, r, interact.key_pressed(I.KeyTab, I.Modifiers(true, false, false, false)))
    assert(next_model.focus_id == id("first"), "Shift+Tab moves backward")

    next_model, events = interact.step(next_model, r, interact.focus_move(I.FocusBackward))
    assert(next_model.focus_id == id("third"), "typed FocusMove honors backward direction")
end

-- Keyboard activation and text input are routed to the focused target.
do
    local r = report { focusables = { focus("edit", 1, 0, 0, 100, 20) } }
    local m = interact.model { focus_id = id("edit") }

    local _, events = interact.step(m, r, interact.key_pressed(I.KeyReturn))
    assert_event_order(events, { I.Activate }, "return activation")
    assert(events[1].id == id("edit"), "Return activates focus")

    _, events = interact.step(m, r, interact.key_pressed(I.KeySpace))
    assert_event_order(events, { I.Activate }, "space activation")

    _, events = interact.step(m, r, interact.text_input("x"))
    assert_event_order(events, { I.InputText }, "text input")
    assert(events[1].id == id("edit") and events[1].text == "x", "TextInput routes to focus")

    _, events = interact.step(m, r, interact.text_editing("pre", 1, 2))
    assert_event_order(events, { I.EditText }, "text editing")
    assert(events[1].id == id("edit") and events[1].start == 1 and events[1].length == 2, "TextEditing routes to focus")
end

-- Pointer press event order is deterministic and establishes capture.  Release
-- can still activate the captured/pressed target even when the current report no
-- longer contains that target (for example after a reorder or disappearance).
do
    local target = id("button")
    local r_down = report {
        hover_id = target,
        hits = { hit("button", 0, 0, 50, 30) },
        focusables = { focus("button", 1, 0, 0, 50, 30) },
    }
    local m, events = interact.step(interact.model(), r_down, interact.pointer_pressed(I.BtnLeft, 10, 10))
    assert_event_order(events, { I.SetPointer, I.SetHover, I.SetPressed, I.SetCapture, I.SetFocus, I.ClearDrag }, "pointer press")
    assert(m.pressed_id == target, "press stores pressed id")
    assert(pvm.classof(m.capture) == I.Captured and m.capture.id == target, "press captures target")
    assert(m.focus_id == target, "press focuses target")

    local r_gone = report { hover_id = Core.NoId }
    m, events = interact.step(m, r_gone, interact.pointer_released(I.BtnLeft, 400, 400))
    assert_event_order(events, { I.SetPointer, I.ClearHover, I.Activate, I.ClearPressed, I.ClearCapture }, "captured release")
    assert(events[3].id == target, "captured release activates original pressed id")
    assert(m.pressed_id == Core.NoId and m.capture == I.NoCapture, "release clears pressed/capture")
end

-- Wheel input honors reported scroll target, axis, and clamped content limits.
do
    local sid = id("scroll")
    local r = report {
        hover_id = id("scroll-hit"),
        scroll_id = sid,
        scrollables = { scroll("scroll", Style.ScrollY, 0, 0, 100, 50, 100, 75) },
    }
    local m, events = interact.step(interact.model(), r, interact.wheel_moved(10, 40, 5, 5))
    assert_event_order(events, { I.SetPointer, I.SetHover, I.ScrollBy }, "wheel scroll")
    assert(events[3].id == sid and events[3].dx == 0 and events[3].dy == 25, "vertical scroll clamps and drops dx")
    local sx, sy = interact.scroll_offset(m, sid)
    assert(sx == 0 and sy == 25, "model scroll updated to clamped offset")

    m, events = interact.step(m, r, interact.wheel_moved(0, 10, 5, 5))
    assert(#events == 2, "wheel beyond max emits no zero ScrollBy")
end

-- Drag starts only after the threshold, tracks drop target/slot from the current
-- report, drops on release, and cancellation clears pending drag/capture.
do
    local src = id("source")
    local target = id("target")
    local slot = id("slot")
    local r = report {
        hover_id = src,
        hits = { hit("source", 0, 0, 20, 20) },
        drag_sources = { drag_source("source", 0, 0, 20, 20) },
        drop_targets = { drop_target("target", 40, 40, 40, 40) },
        drop_slots = { drop_slot("slot", 45, 45, 20, 20) },
    }

    local m, events = interact.step(interact.model(), r, interact.pointer_pressed(I.BtnLeft, 5, 5))
    assert_class(events[#events], I.SetDragPending, "press over drag source starts pending drag")
    assert(pvm.classof(m.drag) == I.DragPending and m.drag.source_id == src, "model stores pending drag")

    m, events = interact.step(m, r, interact.pointer_moved(46, 46))
    assert_event_order(events, { I.SetPointer, I.SetHover, I.SetDragging, I.DragStarted, I.DragMoved }, "drag threshold move")
    assert(events[3].source_id == src and events[3].over_target_id == target and events[3].over_slot_id == slot, "drag move reports target and slot")
    assert(pvm.classof(m.drag) == I.Dragging, "model stores dragging state")

    m, events = interact.step(m, r, interact.pointer_released(I.BtnLeft, 46, 46))
    assert_event_order(events, { I.SetPointer, I.SetHover, I.DragDropped, I.ClearDrag, I.ClearPressed, I.ClearCapture }, "drag drop")
    assert(events[3].source_id == src and events[3].over_target_id == target and events[3].over_slot_id == slot, "drop reports target and slot")
    assert(m.drag == I.NoDrag and m.capture == I.NoCapture, "drop clears drag/capture")

    m = interact.model { pressed_id = src, capture = I.Captured(src, 0, 0), drag = I.DragPending(src, 0, 0) }
    m, events = interact.step(m, r, interact.cancel_pointer())
    assert_event_order(events, { I.DragCancelled, I.ClearDrag, I.ClearPressed, I.CancelCapture, I.ClearCapture }, "cancel pending drag")
    assert(events[1].source_id == src, "cancel identifies drag source")
    assert(m.drag == I.NoDrag and m.pressed_id == Core.NoId and m.capture == I.NoCapture, "cancel clears interaction state")
end

-- Modal/layer reports are consumed through their already-filtered topmost facts:
-- lower hits may remain in hit_stack for diagnostics, but hover/focus/activation
-- follow the modal top layer supplied by runtime.
do
    local lower = id("lower-button")
    local modal = id("modal-button")
    local r = report {
        hover_id = modal,
        hits = { hit("lower-button", 0, 0, 200, 200), hit("modal-button", 50, 50, 100, 40) },
        hit_stack = { hit("lower-button", 0, 0, 200, 200), hit("modal-button", 50, 50, 100, 40) },
        focusables = { focus("modal-button", 1, 50, 50, 100, 40) },
        layers = {
            I.LayerBox(id("base-layer"), I.LayerBase, 0, 0, 0, 200, 200),
            I.LayerBox(id("modal-layer"), I.LayerModal, 100, 40, 40, 120, 80),
        },
        modal_barriers = { I.ModalBarrierBox(id("modal-barrier"), 0, 0, 200, 200) },
        focus_scopes = { I.FocusScopeBox(id("modal-scope"), I.FocusTrap, 1, 1) },
    }
    assert(#r.hit_stack == 2 and r.hit_stack[1].id == lower and r.hit_stack[2].id == modal, "report preserves hit stack for modal diagnostics")
    local m, events = interact.step(interact.model(), r, interact.pointer_pressed(I.BtnLeft, 60, 60))
    assert(events[3].id == modal and events[5].id == modal, "modal hover controls press/focus despite lower hit in stack")
    m, events = interact.step(m, r, interact.pointer_released(I.BtnLeft, 60, 60))
    assert(events[3].id == modal, "modal release activates top modal target")

    m, events = interact.step(interact.model { focus_id = modal }, r, interact.key_pressed(I.KeyEscape))
    assert(#events == 0, "Escape maps to cancel; with no press/drag/capture there are no reducer state events")
end

-- FocusLost clears focus/press/capture and cancels active drags.
do
    local src = id("draggy")
    local m = interact.model {
        focus_id = id("field"),
        pressed_id = src,
        capture = I.Captured(src, 0, 0),
        drag = I.Dragging(src, 0, 0, 10, 10, Core.NoId, Core.NoId),
    }
    m, events = interact.step(m, report(), interact.focus_lost())
    assert_event_order(events, { I.ClearFocus, I.ClearPressed, I.ClearCapture, I.DragCancelled, I.ClearDrag }, "focus lost")
    assert(m.focus_id == Core.NoId and m.pressed_id == Core.NoId and m.capture == I.NoCapture and m.drag == I.NoDrag, "focus lost clears transient interaction state")
end

print("ok test_ui_interact_contract")
