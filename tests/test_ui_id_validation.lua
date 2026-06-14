package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")

local T = ui.T
local Auth = T.Auth
local Interact = T.Interact
local Style = T.Style
local b = ui.build
local ids = ui.id
local W = ui.widgets

local function has_error(errors, pattern)
    for i = 1, #errors do
        if errors[i]:find(pattern, 1, true) then return true, errors[i] end
    end
    return false, table.concat(errors, "\n")
end

local function assert_invalid(node, pattern, label, opts)
    local ok, errors = ids.validate_auth(node, opts)
    assert(not ok, (label or pattern) .. " should be invalid")
    local found, detail = has_error(errors, pattern)
    assert(found, (label or pattern) .. " missing error pattern " .. pattern .. " in:\n" .. detail)
    return errors
end

local function assert_valid(node, label, opts)
    local ok, errors = ids.validate_auth(node, opts)
    assert(ok, (label or "node") .. " should be valid, got:\n" .. table.concat(errors, "\n"))
end

-- NoId leaves and local, non-interactive anonymous nodes are allowed.
do
    local node = b.fragment {
        b.text { "anonymous text" },
        b.box { b.text { "anonymous child" } },
        b.empty,
    }
    assert_valid(node, "NoId leaves")
    assert(#ids.collect_auth(node) == 0, "NoId leaves are not collected as identity entries")
end

-- Duplicate authored IDs are detected across the whole tree, including nested
-- fragments, with paths precise enough to identify both locations.
do
    local node = b.fragment {
        b.fragment {
            b.text { b.id("dup"), "first" },
        },
        b.box { b.id("container"), b.text { b.id("dup"), "second" } },
    }
    local errors = assert_invalid(node, "Auth.Text(id=\"dup\") duplicates Auth.Text(id=\"dup\")", "nested duplicate")
    local message = table.concat(errors, "\n")
    assert(message:find("root.children%[2%].children%[1%]"), "duplicate error includes later nested path: " .. message)
    assert(message:find("root.children%[1%].children%[1%]"), "duplicate error includes original nested path: " .. message)
end

-- Wrapper IDs share the same namespace as child IDs.  An input surface cannot
-- reuse the visual box ID it wraps.
do
    local node = b.with_input(b.id("action"), Interact.ActivateTarget,
        b.box { b.id("action"), b.text { "Run" } })
    local errors = assert_invalid(node, "Auth.Box(id=\"action\") duplicates Auth.WithInput(id=\"action\")", "input/box duplicate")
    assert(table.concat(errors, "\n"):find("root.child"), "input duplicate points at wrapped child path")
end

-- Scroll, drag, drop target, and drop slot surface IDs are all part of the same
-- validation set.
do
    local node = b.fragment {
        b.scroll_y(b.id("surface"), { b.text { "scroll" } }),
        b.drag_source(b.id("surface"), b.box { b.text { "drag" } }),
        b.drop_target(b.id("surface"), b.box { b.text { "drop target" } }),
        b.drop_slot(b.id("surface"), b.box { b.text { "drop slot" } }),
    }
    local ok, errors = ids.validate_auth(node)
    assert(not ok, "scroll/drag/drop duplicate IDs should be invalid")
    local joined = table.concat(errors, "\n")
    assert(joined:find("Auth.WithDragSource%(id=\"surface\"%) duplicates Auth.Scroll%(id=\"surface\"%)"), joined)
    assert(joined:find("Auth.WithDropTarget%(id=\"surface\"%) duplicates Auth.Scroll%(id=\"surface\"%)"), joined)
    assert(joined:find("Auth.WithDropSlot%(id=\"surface\"%) duplicates Auth.Scroll%(id=\"surface\"%)"), joined)
end

-- TextRef content IDs are tracked by default so content-store keys cannot
-- collide silently with node IDs or other content refs.
do
    local node = b.fragment {
        b.text { b.id("content:greeting"), "visible" },
        b.text_ref(b.id("content:greeting"), { b.id("greeting-ref") }),
    }
    assert_invalid(node, "Auth.TextRef.content_id(id=\"content:greeting\") duplicates Auth.Text(id=\"content:greeting\")", "content id duplicate")

    local ok = ids.validate_auth(node, { content_refs = false })
    assert(ok, "content_refs=false intentionally ignores content ID collisions")
end

-- Layer/overlay/focus-scope/modal IDs participate in validation just like older
-- input wrappers.
do
    local child = b.box { b.text { "overlay" } }
    local node = b.fragment {
        Auth.Layer(b.id("layerish"), Interact.LayerPopup, 10, child),
        Auth.Overlay(b.id("layerish"), b.id("anchor"), Interact.PlaceBelow, false, b.empty),
        Auth.FocusScope(b.id("layerish"), Interact.FocusTrap, b.empty),
        Auth.Modal(b.id("layerish"), b.empty),
    }
    local ok, errors = ids.validate_auth(node)
    assert(not ok, "layer/overlay/focus scope/modal duplicates should be invalid")
    local joined = table.concat(errors, "\n")
    assert(joined:find("Auth.Overlay%(id=\"layerish\"%) duplicates Auth.Layer%(id=\"layerish\"%)"), joined)
    assert(joined:find("Auth.FocusScope%(id=\"layerish\"%) duplicates Auth.Layer%(id=\"layerish\"%)"), joined)
    assert(joined:find("Auth.Modal%(id=\"layerish\"%) duplicates Auth.Layer%(id=\"layerish\"%)"), joined)
end

-- Generated widget child IDs are deterministic and validated at the full-tree
-- boundary.  A caller-authored node that reuses a widget-generated child ID is a
-- duplicate even if the widget itself validates in isolation.
do
    local button = W.button.bundle { id = "save", label = "Save" }
    assert_valid(button.node, "button node in isolation")
    local entries = ids.collect_auth(button.node)
    local saw_label = false
    for i = 1, #entries do
        if entries[i].key == "save:label" then saw_label = true end
    end
    assert(saw_label, "button generated label child ID is collected")

    local tree = b.fragment {
        button.node,
        b.text { b.id("save:label"), "duplicate generated label" },
    }
    assert_invalid(tree, "Auth.Text(id=\"save:label\") duplicates Auth.Text(id=\"save:label\")", "generated child duplicate")
end

-- Surface map validation catches duplicate IDs independently of authored trees.
do
    local surfaces = {
        primary = b.id("same"),
        secondary = b.id("same"),
        other = b.id("other"),
    }
    local ok, errors = ids.validate_surfaces(surfaces)
    assert(not ok, "surface duplicate should be invalid")
    local joined = table.concat(errors, "\n")
    assert(joined:find("surface.secondary%(id=\"same\"%) duplicates surface.primary%(id=\"same\"%)")
        or joined:find("surface.primary%(id=\"same\"%) duplicates surface.secondary%(id=\"same\"%)"), joined)
end

-- assert_auth includes the same precise diagnostics in its thrown error.
do
    local bad = b.fragment { b.text { b.id("boom"), "a" }, b.text { b.id("boom"), "b" } }
    local ok, err = pcall(function() ids.assert_auth(bad) end)
    assert(not ok, "assert_auth throws on duplicates")
    assert(tostring(err):find("ui.id validation failed", 1, true), err)
    assert(tostring(err):find("root.children[2]", 1, true), err)
    assert(tostring(err):find("root.children[1]", 1, true), err)
end

-- lower.root keeps validation enabled by default, making duplicate authored IDs a
-- boundary error before layout/render/runtime phases consume the tree.
do
    local bad = b.fragment { b.box { b.id("lower-dup") }, b.box { b.id("lower-dup") } }
    local theme = ui.theme.default()
    local env = ui.theme.env_for_width(320)
    local ok, err = pcall(function() ui.lower.root(bad, theme, env) end)
    assert(not ok, "lower.root validates IDs by default")
    assert(tostring(err):find("lower%-dup"), err)
end

print("ok test_ui_id_validation")
