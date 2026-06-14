package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local Core = T.Core
local Auth = T.Auth
local Interact = T.Interact
local Layout = T.Layout
local View = T.View
local contract = ui.backend_contract
local b = ui.build
local tw = ui.tw
local paint = ui.paint

local function id(value)
    return b.id(value)
end

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "assert_eq", tostring(expected), tostring(actual)), 2)
    end
end

local function assert_truthy(value, label)
    if not value then error(label or "expected truthy", 2) end
end

local function lower_one(auth)
    local nodes = ui.lower.root(auth, ui.theme.default(), ui.theme.env_for_width(320))
    assert_eq(#nodes, 1, "lower_one count")
    return nodes[1]
end

local function render(node, w, h, text_system, content_store)
    return ui.render.root(node, T.Solve.Env(w, h, {}), text_system or false, content_store)
end

local function call_count(calls, name)
    local n = 0
    for i = 1, #calls do
        if calls[i].name == name then n = n + 1 end
    end
    return n
end

-- Capability helpers should fail loud for missing required capabilities and
-- accept the explicit trace-driver template when no product backend is present.
do
    local ok, errors, warnings = contract.validate_capabilities(nil, {})
    assert_truthy(ok, "nil capabilities are warnings by default")
    assert_eq(#errors, 0, "nil capabilities error count")
    assert_truthy(#warnings >= 1, "nil capabilities warning")

    ok, errors = contract.validate_capabilities({}, { require_capabilities = true, required_capabilities = { "runtime.boxes" } })
    assert_eq(ok, false, "missing required capability fails")
    assert_truthy(string.find(contract.describe_errors(errors), "runtime.boxes", 1, true), "required capability named in error")

    local trace = contract.new_trace_driver()
    contract.assert_runtime_driver(trace, { require_cursor = true })
    contract.assert_trace_balance(trace.calls)
end

-- Host event validation is backend-independent: input events must expose typed
-- Interact.Raw values, while non-input lifecycle events may remain plain tables.
do
    contract.assert_host_event({ type = "window_resized", w = 100, h = 80 })
    contract.assert_host_event({ type = "key_down", raw = ui.input.raw_key_down(ui.input.KeyTab, ui.input.modifiers(), false) })
    contract.assert_host_event({ type = "text_input", raws = ui.input.raw_many_from_host_event({ type = "text_input", text = "a" }) })

    local ok, errors = contract.validate_host_event({ type = "mouse_pressed", x = 1, y = 2, button = ui.input.ButtonLeft })
    assert_eq(ok, false, "input event without raw fails")
    assert_truthy(string.find(contract.describe_errors(errors), "typed raw", 1, true), "raw error text")
end

-- Generic runtime execution must remain useful with no backend driver at all:
-- layer, overlay, modal, hit, focus, and cursor facts are reported from View.Op
-- without requiring SDL/Love callbacks.
do
    local auth = Auth.Layer(
        id("layer"),
        Interact.LayerPopup,
        7,
        Auth.Overlay(
            id("overlay"),
            Core.NoId,
            Interact.PlaceCenter,
            true,
            b.with_input(
                id("target"),
                Interact.ActivateTarget,
                b.box { id("panel"), tw.w_px(40), tw.h_px(30), tw.cursor_pointer, tw.bg.slate[900] }
            )
        )
    )
    local node = lower_one(auth)
    local g, p, c = render(node, 80, 60)
    local report = ui.runtime.run(nil, { pointer_x = 10, pointer_y = 10 }, g, p, c)

    assert_eq(#report.layers, 1, "generic report layer count")
    assert_eq(report.layers[1].id.value, "layer", "generic report layer id")
    assert_eq(report.layers[1].kind, Interact.LayerPopup, "generic report layer kind")
    assert_eq(#report.overlays, 1, "generic report overlay count")
    assert_eq(report.overlays[1].modal, true, "generic report overlay modal")
    assert_eq(#report.modal_barriers, 1, "generic report modal barrier count")
    assert_eq(report.hover_id.value, "target", "generic report hover target")
    assert_eq(report.cursor, T.Style.CursorPointer, "generic report cursor")
end

-- Trace drivers validate the runtime driver surface, stack balance, clipping,
-- boxes, paint, and the fact that layers are generic View.Op/report semantics
-- rather than mandatory native driver calls.
do
    local auth = b.box {
        id("trace-root"), tw.flow, tw.w_px(96), tw.h_px(64), tw.p(1),
        tw.overflow_x_hidden, tw.overflow_y_hidden, tw.bg.slate[950],
        b.paint {
            id("trace-paint"), tw.w_px(80), tw.h_px(48),
            paint.line(0, 0, 20, 20, paint.stroke(0x38bdf8ff, 2)),
            paint.polygon({ 24, 4, 48, 4, 44, 24, 28, 20 }, paint.fill(0x14b8a688), paint.stroke(0x2dd4bfff, 1)),
            paint.circle(64, 24, 10, paint.fill(0xf59e0b88), paint.stroke(0xfbbf24ff, 2)),
            paint.arc(20, 36, 8, 0, 3.14, 8, paint.stroke(0xef4444ff, 2)),
            paint.bezier({ 50, 36, 60, 30, 70, 42, 78, 34 }, 8, paint.stroke(0x22c55eff, 2)),
            paint.mesh(paint.mesh_fan, {
                paint.vertex(8, 30), paint.vertex(20, 34), paint.vertex(18, 44), paint.vertex(6, 42),
            }, nil, 0x60a5faff, 75),
        },
    }
    local node = lower_one(auth)
    local trace = contract.new_trace_driver()
    local g, p, c = render(node, 96, 64)
    local report = ui.runtime.run(trace, { pointer_x = 4, pointer_y = 4 }, g, p, c)

    contract.assert_trace_balance(trace.calls)
    assert_truthy(call_count(trace.calls, "draw_box") >= 1 or call_count(trace.calls, "draw_rect") >= 1, "trace drew box")
    assert_eq(call_count(trace.calls, "push_clip_rect"), 1, "trace clip push count")
    assert_eq(call_count(trace.calls, "pop_clip_rect"), 1, "trace clip pop count")
    assert_eq(call_count(trace.calls, "draw_paint"), 1, "trace paint draw count")
    assert_eq(call_count(trace.calls, "push_layer"), 0, "generic layers do not require native push_layer")
    assert_truthy(report ~= nil, "runtime report returned with trace driver")
end

-- SDL3 package/module capability metadata should satisfy the product backend
-- contract.  Object-level checks exercise dummy-video host creation, driver
-- capabilities, paint/image policies, text system methods, clipboard hooks, text
-- input rect lifecycle, and density reporting.
do
    local sdl3 = require("ui.backends.sdl3")
    contract.assert_backend_package(sdl3, { product = "sdl3", require_capabilities = true })
    contract.assert_host_module(sdl3.host)
    contract.assert_runtime_module(sdl3.runtime, {
        require_capabilities = true,
        required_capabilities = {
            "runtime.boxes", "runtime.rounded_boxes", "runtime.clipping", "runtime.scrolling",
            "paint.line", "paint.polygon_fill", "paint.circle_fill", "paint.mesh", "paint.image",
        },
    })
    contract.assert_text_module(sdl3.text, { require_capabilities = true })

    local host = sdl3.new_host {
        title = "ui backend contract",
        width = 96,
        height = 64,
        vsync = false,
        driver = { missing_image = "skip" },
    }

    local ok, err = pcall(function()
        contract.assert_host_object(host, {
            require_clipboard = true,
            require_text_input_rect = true,
            require_density = true,
        })
        contract.assert_runtime_driver(host.driver, {
            require_cursor = true,
            require_capabilities = true,
            required_capabilities = {
                "runtime.boxes", "runtime.rounded_boxes", "runtime.capsules", "runtime.clipping",
                "runtime.transforms", "runtime.scrolling", "runtime.cursors",
                "paint.line", "paint.polyline", "paint.polygon_fill", "paint.circle_fill",
                "paint.arc", "paint.bezier", "paint.mesh", "paint.image", "paint.stroke_width",
            },
        })
        contract.assert_text_system(host.text_system, { require_close = true })

        local logical_w, logical_h = host:size()
        assert_truthy(logical_w > 0 and logical_h > 0, "SDL host logical size")
        local density = contract.density_report(host)
        assert_eq(density.supported, true, "SDL density report supported")
        assert_truthy(density.scale_x > 0 and density.scale_y > 0, "SDL density scale")

        host:begin_frame(0x020617ff)
        host.driver:draw_rect(2, 2, 30, 18, Layout.BoxVisual(0x0f172aff, 0x38bdf8ff, 2, Layout.ShapeRoundRect, 6, 100))
        host.driver:draw_rect(36, 2, 30, 18, Layout.BoxVisual(0x1e293bff, 0xf59e0bff, 2, Layout.ShapeCapsule, 999, 100))
        host.driver:push_clip_rect(0, 0, 96, 64)
        host.driver:draw_paint(0, 0, 96, 64, paint.list {
            paint.line(4, 28, 40, 32, paint.stroke(0x38bdf8ff, 2)),
            paint.polyline({ 44, 28, 54, 36, 64, 30 }, paint.stroke(0xa78bfaff, 2)),
            paint.polygon({ 8, 44, 20, 40, 28, 56 }, paint.fill(0x14b8a688), paint.stroke(0x2dd4bfff, 1)),
            paint.circle(46, 48, 8, paint.fill(0xf59e0b88), paint.stroke(0xfbbf24ff, 1)),
            paint.arc(70, 48, 8, -1, 2, 8, paint.stroke(0xef4444ff, 2)),
            paint.bezier({ 72, 26, 82, 20, 86, 38, 92, 30 }, 8, paint.stroke(0x22c55eff, 2)),
            paint.mesh(paint.mesh_fan, { paint.vertex(70, 8), paint.vertex(88, 10), paint.vertex(82, 22) }, nil, 0x60a5faff, 80),
            paint.image(id("missing-image"), 0, 0, 8, 8, 0xffffffff, 100),
        })
        host.driver:pop_clip_rect()

        local style = Layout.TextStyle(1, 16, 400, 0xffffffff, 0, 20, 0, "SDL")
        local constraint = Layout.Constraint(160, 80)
        local measured = host.text_system.measure(style, constraint)
        assert_truthy((measured.measured_w or measured.width or 0) > 0, "SDL text measured width")
        assert_truthy((measured.measured_h or measured.height or 0) > 0, "SDL text measured height")
        local probe = host.text_system.hit_test(style, constraint, 0, 0)
        assert_truthy(type(probe) == "table", "SDL text hit test")
        local ranges = host.text_system.range_query(style, constraint, 0, -1)
        assert_truthy(type(ranges) == "table", "SDL text ranges")

        host:set_text_input(true)
        host:set_text_input_rect(1, 2, 12, 16, 0)
        host:set_text_input(false)
        host:set_clipboard_text("ui backend contract")
        assert_eq(type(host:get_clipboard_text()), "string", "SDL clipboard returns string")
        host:present()
    end)

    host:close()
    if not ok then error(err, 0) end
end

-- Love remains secondary/optional.  When the module is available, its declared
-- capabilities must be structurally valid and its unsupported advanced text/host
-- gaps must remain explicit rather than silently claimed.
do
    local ok, love_runtime = pcall(require, "ui.runtime_love")
    if ok then
        contract.assert_runtime_module(love_runtime, { require_capabilities = true })
        assert_eq(contract.capability(love_runtime.capabilities, "text.hit_test"), false, "Love text hit_test explicit gap")
        assert_eq(contract.capability(love_runtime.capabilities, "host.clipboard"), false, "Love clipboard explicit gap")
    end
end

print("ok test_ui_backend_contract")
