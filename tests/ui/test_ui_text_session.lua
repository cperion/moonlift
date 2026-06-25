package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local Layout = T.Layout
local Interact = T.Interact
local text = ui.text
local session = ui.session

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "assert_eq", tostring(expected), tostring(actual)), 2)
    end
end

local function assert_truthy(value, label)
    if not value then error(label or "expected truthy", 2) end
end

local function style_for(content)
    return Layout.TextMeasure(T.Resolved.TextMetrics(1, 16, 400, 0, 20, 0), content or "")
end

local function text_content(style)
    return style.content or ""
end

local function text_font_size(style)
    return (style.metrics and style.metrics.font_size) or style.font_size or 16
end

local function fixed_measure(multiplier)
    return function(style, constraint)
        local content = text_content(style)
        return {
            measured_w = #content * multiplier,
            measured_h = 10 + multiplier,
            baseline = multiplier,
            lines = {
                {
                    text = content,
                    w = #content * multiplier,
                    h = 10 + multiplier,
                    baseline = multiplier,
                    byte_start = 0,
                    byte_end = #content,
                },
            },
        }
    end
end

local function fake_backend(opts)
    opts = opts or {}
    local state = {
        next_window_id = 1000,
        created_hosts = {},
        text_systems = {},
        text_closed = 0,
        host_closed = 0,
        text_input_calls = {},
        rect_calls = {},
        clipboard = "",
    }

    local backend = {}

    function backend.new_text_system(spec)
        local sys = {
            spec = spec,
            measure = fixed_measure(opts.multiplier or 7),
        }
        function sys.hit_test(style, constraint, x, y)
            return { byte_start = 0, byte_end = 0, x = x or 0, y = y or 0, w = 0, h = text_font_size(style) }
        end
        function sys.range_query(style, constraint, offset, length)
            return { { byte_start = offset or 0, byte_end = length or #text_content(style) } }
        end
        function sys:close()
            state.text_closed = state.text_closed + 1
        end
        state.text_systems[#state.text_systems + 1] = sys
        return sys
    end

    function backend.new_host(spec)
        state.next_window_id = state.next_window_id + 1
        local host = {
            window_id = state.next_window_id,
            text_system = spec.text_system,
            driver = {},
        }
        function host:begin_frame() end
        function host:present() end
        function host:now_ms() return 25 end
        function host:delay() end
        function host:size() return spec.width or 64, spec.height or 48 end
        function host:close() state.host_closed = state.host_closed + 1 end
        function host:set_text_input(active) state.text_input_calls[#state.text_input_calls + 1] = active == true end
        function host:set_text_input_rect(x, y, w, h, cursor)
            state.rect_calls[#state.rect_calls + 1] = { x = x, y = y, w = w, h = h, cursor = cursor }
        end
        function host:set_clipboard_text(value) state.clipboard = value or "" end
        function host:get_clipboard_text() return state.clipboard end
        state.created_hosts[#state.created_hosts + 1] = host
        return host
    end

    function backend.poll_events()
        return {}
    end

    backend._state = state
    return backend
end

-- Explicit approximate fallback remains available and observable.  Missing real
-- text systems fail loud when fallback is disabled, instead of silently using the
-- approximate backend.
do
    local old_default = text.default_key()
    local old_fallback = text.fallback_allowed()
    text.set_default(nil)
    text.set_fallback_allowed(false)

    local approx = text.layout(style_for("abcd"), Layout.Constraint(200, 100), false)
    assert_truthy(approx.measured_w > 0, "explicit approx layout measured width")
    assert_truthy(string.find(text.fallback_reason() or "", "explicit approximate", 1, true), "explicit approx fallback reason")

    local ok, err = pcall(function()
        text.layout(style_for("abcd"), Layout.Constraint(200, 100), "missing-ui-text-system")
    end)
    assert_eq(ok, false, "missing registered text system errors with fallback disabled")
    assert_truthy(string.find(tostring(err), "unregistered text system key", 1, true), "missing text system error text")

    text.set_fallback_allowed(old_fallback)
    if old_default ~= nil and text.lookup(old_default) ~= nil then
        text.set_default(old_default)
    else
        text.set_default(nil)
    end
end

-- Text registry defaults and explicit text_key compatibility are owned by the
-- session lifecycle and are unregistered on close.
do
    local backend = fake_backend({ multiplier = 9 })
    local s = session.new {
        backend = backend,
        session_id = "fake-default",
        text_key = "explicit-text-key",
        width = 80,
        height = 60,
    }
    assert_eq(s.text_key, "explicit-text-key", "session explicit text_key")
    assert_eq(text.lookup("explicit-text-key"), s.text_system, "session text registered")
    assert_eq(text.default_key(), "explicit-text-key", "session text default key")

    local win = s:create_window { title = "fake", width = 80, height = 60 }
    assert_eq(win.text_key, "explicit-text-key", "window inherits text key")
    assert_eq(win.text_system, s.text_system, "window inherits text system")

    local layout = text.layout(style_for("abc"), Layout.Constraint(200, 100))
    assert_eq(layout.measured_w, 27, "default registered system used")
    assert_eq(layout.measured_h, 19, "default registered system height")

    s:close()
    assert_eq(text.lookup("explicit-text-key"), nil, "session unregisters explicit text key")
    assert_eq(text.default_key(), nil, "session clears default text key")
    assert_eq(backend._state.text_closed, 1, "owned session text system closed")
    assert_eq(backend._state.host_closed, 1, "session closes host")
end

-- Sessions without an explicit key choose a deterministic session-scoped key and
-- dispatch typed raw input to windows while preserving on_event compatibility.
do
    local backend = fake_backend({ multiplier = 5 })
    local raw_classes = {}
    local events_seen = 0
    local s = session.new {
        backend = backend,
        session_id = "auto-key",
        width = 64,
        height = 48,
        window_event = function()
            events_seen = events_seen + 1
        end,
        window_raw_ui = function(_, _, raw)
            raw_classes[#raw_classes + 1] = pvm.classof(raw)
        end,
    }
    assert_eq(s.text_key, "session:auto-key", "auto session text key")
    assert_eq(text.lookup("session:auto-key"), s.text_system, "auto key registered")

    local win = s:create_window {}
    local key_raw = ui.input.raw_key_down(ui.input.KeyTab, ui.input.modifiers(), false)
    s:dispatch_event({ type = "key_down", window_id = win.window_id, raw = key_raw })
    s:dispatch_event({ type = "text_input", window_id = win.window_id, raws = ui.input.raw_many_from_host_event({ type = "text_input", text = "x" }) })

    assert_eq(events_seen, 2, "session preserves on_event dispatch")
    assert_eq(raw_classes[1], Interact.KeyPressed, "session dispatches raw key")
    assert_eq(raw_classes[2], Interact.TextInput, "session dispatches raw text input")
    assert_eq(win.needs_redraw, true, "event dispatch requests redraw")

    win:set_text_input(true)
    win:set_text_input_rect(1, 2, 3, 4)
    win:set_text_input(false)
    assert_eq(#backend._state.text_input_calls, 2, "window text input lifecycle calls")
    assert_eq(backend._state.text_input_calls[1], true, "window starts text input")
    assert_eq(backend._state.text_input_calls[2], false, "window stops text input")
    assert_eq(#backend._state.rect_calls, 1, "window text input rect call")
    assert_eq(backend._state.rect_calls[1].x, 1, "window text input rect x")

    s:close()
    assert_eq(text.lookup("session:auto-key"), nil, "auto key unregistered on close")
end

-- Measurement/render text layout cache keys must include both text system key and
-- content-store object/content, so changing either produces deterministic new
-- sizes instead of stale cached layout.
do
    local content_id = ui.build.id("cache-content")
    local auth = ui.build.text_ref(content_id, { ui.build.id("cache-node"), ui.tw.text_base })
    local node = ui.lower.root(auth, ui.theme.default(), ui.theme.env_for_width(320))[1]
    local store_a = T.Content.Store({ T.Content.Text(content_id, "aa") })
    local store_b = T.Content.Store({ T.Content.Text(content_id, "aaaa") })

    text.register("cache-a", { measure = fixed_measure(3) })
    text.register("cache-b", { measure = fixed_measure(11) })

    local size_a = pvm.one(ui.measure.root(node.layout, 200, 100, "cache-a", store_a))
    local size_b = pvm.one(ui.measure.root(node.layout, 200, 100, "cache-b", store_a))
    local size_c = pvm.one(ui.measure.root(node.layout, 200, 100, "cache-a", store_b))
    assert_eq(size_a.w, 6, "cache text system A width")
    assert_eq(size_b.w, 22, "cache text system B width")
    assert_eq(size_c.w, 12, "cache content store B width")

    local solved_a = pvm.one(ui.solve.root(node.layout, T.Solve.Env(200, 100), "cache-a", store_a))
    local solved_b = pvm.one(ui.solve.root(node.layout, T.Solve.Env(200, 100), "cache-b", store_a))
    local ops_a = pvm.drain(ui.render.root(solved_a, node.decor))
    local ops_b = pvm.drain(ui.render.root(solved_b, node.decor))
    assert_eq(ops_a[1].text.measured_w, 6, "render cache system A width")
    assert_eq(ops_b[1].text.measured_w, 22, "render cache system B width")

    text.unregister("cache-a")
    text.unregister("cache-b")
end

-- SDL3 session wrapper uses the same default text lifecycle under dummy video,
-- and its window helpers expose text input rect and clipboard hooks safely.
do
    local sdl_session = require("ui.session_sdl3")
    local s = sdl_session.new {
        session_id = "sdl-text-session-test",
        title = "ui text session test",
        width = 96,
        height = 64,
        vsync = false,
    }
    assert_eq(s.text_key, "session:sdl-text-session-test", "SDL session default text key")
    assert_eq(text.lookup(s.text_key), s.text_system, "SDL session registered text system")
    assert_eq(text.default_key(), s.text_key, "SDL session default text key registered")

    local win = s:create_window { title = "ui text session window", width = 96, height = 64, vsync = false }
    assert_eq(win.text_key, s.text_key, "SDL window inherits session text key")
    win:set_text_input(true)
    win:set_text_input_rect(2, 3, 20, 16)
    win:set_text_input(false)
    win.host:set_clipboard_text("lalin-ui")
    assert_eq(type(win.host:get_clipboard_text()), "string", "SDL clipboard hook returns string")

    local layout = text.layout(style_for("SDL"), Layout.Constraint(200, 100))
    assert_truthy(layout.measured_w > 0, "SDL session default text layout width")
    assert_truthy(layout.measured_h > 0, "SDL session default text layout height")

    s:close()
    assert_eq(text.lookup("session:sdl-text-session-test"), nil, "SDL session unregisters text key")
    assert_eq(text.default_key(), nil, "SDL session clears default text key")
end

print("ok test_ui_text_session")
