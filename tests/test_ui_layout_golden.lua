package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local L = T.Layout
local V = T.View
local b = ui.build
local tw = ui.tw

local theme = ui.theme.default()
local env = ui.theme.env_for_width(800)

local function id(value)
    return b.id(value)
end

local function id_value(v)
    if v == nil or v == T.Core.NoId then return "NoId" end
    return v.value
end

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "assert_eq", tostring(expected), tostring(actual)), 2)
    end
end

local function assert_close(actual, expected, label)
    if math.abs(actual - expected) > 1e-9 then
        error(string.format("%s: expected %.12g, got %.12g", label or "assert_close", expected, actual), 2)
    end
end

local function lower_one(auth)
    local nodes = ui.lower.root(auth, theme, env)
    assert_eq(#nodes, 1, "lower_one node count")
    return nodes[1]
end

local function measure(node, max_w, max_h, content_store)
    return pvm.one(ui.measure.root(node, max_w, max_h, false, content_store))
end

local function render_ops(node, w, h, content_store)
    return pvm.drain(ui.render.root(node, T.Solve.Env(w, h, {}), false, content_store))
end

local function push_translates(ops)
    local out = {}
    for i = 1, #ops do
        local op = ops[i]
        if op.kind == V.KPushTx then
            out[#out + 1] = { id = id_value(op.id), dx = op.dx, dy = op.dy }
        end
    end
    return out
end

local function assert_pushes(actual, expected, label)
    assert_eq(#actual, #expected, label .. " count")
    for i = 1, #expected do
        assert_eq(actual[i].id, expected[i][1], label .. " id[" .. i .. "]")
        assert_close(actual[i].dx, expected[i][2], label .. " dx[" .. i .. "]")
        assert_close(actual[i].dy, expected[i][3], label .. " dy[" .. i .. "]")
    end
end

local function leaf(name, w, h, extra)
    return b.box { id(name), tw.w_px(w), tw.h_px(h), extra }
end

-- Flow is vertical stream layout.  This golden locks padding, cross-axis
-- alignment, child fixed sizing, and gap handling against the shared
-- measure/render planner.
do
    local node = lower_one(b.box {
        id("flow"), tw.flow, tw.w_px(120), tw.px(2), tw.py(1), tw.gap_y(2), tw.items_center,
        leaf("f-a", 30, 10),
        leaf("f-b", 50, 20),
        leaf("f-c", 20, 5),
    })

    local size = measure(node, 120, 100)
    assert_eq(size.w, 120, "flow measured width")
    assert_eq(size.h, 59, "flow measured height")
    assert_eq(size.baseline, 0, "flow baseline")

    assert_pushes(push_translates(render_ops(node, 120, 100)), {
        { "flow", 8, 4 },
        { "f-a", 37, 0 },
        { "f-b", 27, 18 },
        { "f-c", 42, 46 },
    }, "flow placements")
end

-- Flow margins include ordinary margins in measured height and support auto
-- horizontal margins for centering within the available cross axis.
do
    local node = lower_one(b.box {
        id("margin-flow"), tw.flow, tw.w_px(100), tw.items_start,
        b.box { id("m-a"), tw.w_px(20), tw.h_px(10), tw.ml(2), tw.mt(1), tw.mb(2) },
        b.box { id("m-b"), tw.w_px(30), tw.h_px(5), tw.mx_auto },
    })

    local size = measure(node, 100, 100)
    assert_eq(size.w, 100, "margin flow measured width")
    assert_eq(size.h, 27, "margin flow measured height")

    assert_pushes(push_translates(render_ops(node, 100, 100)), {
        { "m-a", 8, 4 },
        { "m-b", 35, 22 },
    }, "margin flow placements")
end

-- Flex row layout supports fixed items, basis/grow distribution, gaps, and
-- cross-axis centering from the same plan used by measurement and render.
do
    local node = lower_one(b.box {
        id("flex"), tw.flex, tw.row, tw.w_px(120), tw.h_px(40), tw.gap_x(2), tw.items_center,
        leaf("fx-a", 20, 10),
        b.box { id("fx-b"), tw.basis_px(20), tw.grow_1, tw.h_px(20) },
        b.box { id("fx-c"), tw.basis_px(20), tw.grow_1, tw.h_px(30) },
    })

    local size = measure(node, 120, 40)
    assert_eq(size.w, 120, "flex measured width")
    assert_eq(size.h, 40, "flex measured height")
    assert_eq(size.baseline, 10, "flex baseline")

    assert_pushes(push_translates(render_ops(node, 120, 40)), {
        { "fx-a", 0, 15 },
        { "fx-b", 28, 10 },
        { "fx-c", 78, 5 },
    }, "flex placements")
end

-- Flex wrapping is explicit.  With a 20px gap, two 30px items fit in an 80px
-- first line and the third wraps to the second line with row gap preserved.
do
    local node = lower_one(b.box {
        id("wrap"), tw.flex, tw.row, tw.wrap, tw.w_px(80), tw.gap_x(5), tw.gap_y(3),
        leaf("w-a", 30, 10),
        leaf("w-b", 30, 20),
        leaf("w-c", 30, 15),
    })

    local size = measure(node, 80, 100)
    assert_eq(size.w, 80, "wrap measured width")
    assert_eq(size.h, 47, "wrap measured height")

    assert_pushes(push_translates(render_ops(node, 80, 100)), {
        { "w-a", 0, 0 },
        { "w-b", 50, 0 },
        { "w-c", 0, 32 },
    }, "wrap placements")
end

-- Sizing min/max/fraction constraints are deterministic at measure time.
do
    local min_node = lower_one(b.box { id("min"), tw.w_px(20), tw.min_w_px(40), tw.h_px(10) })
    local max_node = lower_one(b.box { id("max"), tw.w_px(80), tw.max_w_px(50), tw.h_px(10) })
    local frac_node = lower_one(b.box { id("frac"), tw.w_1_2, tw.h_px(10) })

    assert_eq(measure(min_node, 200, 100).w, 40, "min width clamps up")
    assert_eq(measure(max_node, 200, 100).w, 50, "max width clamps down")
    assert_eq(measure(frac_node, 200, 100).w, 100, "fraction width uses parent constraint")
end

-- Grid supports authored tracks, fr distribution, spans, gaps, and fixed item
-- placement.  Item-specific authored alignment is intentionally outside the
-- current guaranteed subset, so lowered grid items remain stretch-aligned.
do
    local node = lower_one(b.box {
        id("grid"), tw.grid, tw.w_px(120), tw.h_px(80),
        tw.cols(tw.track.px(20), tw.track.fr(1), tw.track.px(30)),
        tw.rows(tw.track.px(10), tw.track.fr(1)),
        tw.gap_x(5), tw.gap_y(4),
        b.box { id("g-a"), tw.col_start(1), tw.row_start(1), tw.w_px(10), tw.h_px(8) },
        b.box { id("g-b"), tw.col_start(2), tw.col_span(2), tw.row_start(2), tw.self_end, tw.w_px(20), tw.h_px(12) },
    })

    local size = measure(node, 120, 80)
    assert_eq(size.w, 120, "grid measured width")
    assert_eq(size.h, 80, "grid measured height")
    assert_eq(#node.items, 2, "grid item count")
    assert_eq(node.items[2].col_align, L.CStretch, "grid documented item col alignment subset")
    assert_eq(node.items[2].row_align, L.CStretch, "grid documented item row alignment subset")

    assert_pushes(push_translates(render_ops(node, 120, 80)), {
        { "g-a", 0, 0 },
        { "g-b", 40, 26 },
    }, "grid placements")
end

-- Referenced out-of-range grid placements create implicit auto tracks.
do
    local node = lower_one(b.box {
        id("implicit-grid"), tw.grid,
        tw.cols(tw.track.px(20)), tw.rows(tw.track.px(10)), tw.gap_x(1), tw.gap_y(1),
        b.box { id("gi"), tw.col_start(3), tw.row_start(2), tw.w_px(12), tw.h_px(6) },
    })

    local size = measure(node, 200, 100)
    assert_eq(size.w, 40, "implicit grid measured width")
    assert_eq(size.h, 20, "implicit grid measured height")
    assert_pushes(push_translates(render_ops(node, 200, 100)), {
        { "gi", 28, 14 },
    }, "implicit grid placements")
end

-- Scroll is structural: the viewport keeps its authored size while the scroll
-- op reports the content extent measured under the axis-specific constraint.
do
    local node = lower_one(b.scroll_y(id("scroll"), {
        tw.w_px(50), tw.h_px(30), tw.p(1),
        b.box { id("s-child"), tw.w_px(40), tw.h_px(80) },
    }))

    local size = measure(node, 50, 30)
    assert_eq(size.w, 50, "scroll measured width")
    assert_eq(size.h, 30, "scroll measured height")

    local ops = render_ops(node, 50, 30)
    local push_scroll
    for i = 1, #ops do
        if ops[i].kind == V.KPushScroll then
            push_scroll = ops[i]
            break
        end
    end
    assert(push_scroll, "scroll emits KPushScroll")
    assert_eq(id_value(push_scroll.id), "scroll", "scroll op id")
    assert_eq(push_scroll.w, 42, "scroll viewport width excludes padding")
    assert_eq(push_scroll.h, 22, "scroll viewport height excludes padding")
    assert_eq(push_scroll.dx, 40, "scroll content width")
    assert_eq(push_scroll.dy, 80, "scroll content height")
end

-- Content-store text references measure and render through explicit content
-- bindings.  This uses explicit approximate text layout so the golden remains
-- backend-independent.
do
    local content_id = id("content-title")
    local store = T.Content.Store({ T.Content.Text(content_id, "Hello") })
    local node = lower_one(b.text_ref(content_id, { id("text-node"), tw.text_base }))

    local size = measure(node, 200, 100, store)
    assert_eq(size.w, 48, "text ref measured width")
    assert_eq(size.h, 24, "text ref measured height")
    assert_eq(size.baseline, 13, "text ref baseline")

    local ops = render_ops(node, 200, 100, store)
    assert_eq(#ops, 1, "text ref render op count")
    assert_eq(ops[1].kind, V.KText, "text ref render op kind")
    assert_eq(id_value(ops[1].id), "text-node", "text ref op id")
    assert_eq(ops[1].text.measured_w, 48, "text ref layout width")
    assert_eq(ops[1].text.measured_h, 24, "text ref layout height")
    assert_eq(ops[1].text.style.content, "Hello", "text ref resolved content")
end

print("ok test_ui_layout_golden")
