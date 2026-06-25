package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local ui = require("ui")

local T = ui.T
local Core = T.Core
local Interact = T.Interact
local Solve = T.Solve
local Style = T.Style
local b = ui.build
local tw = ui.tw
local paint = ui.paint
local W = ui.widgets
local ids = ui.id
local input = ui.input
local text_field = ui.text_field
local session_sdl3 = require("ui.session_sdl3")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local DEFAULT_THEME = ui.theme.default()
local VALIDATE_IDS_EACH_FRAME = os.getenv("UI_VALIDATE_IDS") == "1"

local function id_key(id)
    return ids.key(id)
end

local function same_id(a, b_)
    return id_key(a) == id_key(b_)
end

local function empty_report()
    return Interact.Report(
        Core.NoId,
        Core.NoId,
        Style.CursorDefault,
        Core.NoId,
        {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
    )
end

local function text_style(text, rgba8, size)
    size = size or 14
    return T.Layout.TextMeasure(T.Resolved.TextMetrics(1, size, 400, 0, math.floor(size * 1.35), 0), text or "")
end

local function text_opts(window, id, placeholder, min_h)
    return {
        id = id,
        text_key = window.text_key,
        placeholder = placeholder,
        padding = 8,
        min_h = min_h or 56,
        text_style = function(field)
            return text_style(text_field.text(field), 0xe5e7ebff, 15)
        end,
        composition_style = function(field)
            return text_style(field.composition_text, 0x93c5fdff, 15)
        end,
        text_rgba8 = 0xe5e7ebff,
        composition_rgba8 = 0x93c5fdff,
        bg_rgba8 = 0x020617ff,
        border_rgba8 = 0x1e293bff,
        focus_border_rgba8 = 0x38bdf8ff,
        selection_rgba8 = 0x1d4ed8ff,
        caret_rgba8 = 0xf8fafcff,
        composition_underline_rgba8 = 0x93c5fdff,
    }
end

local function new_model()
    return {
        interact = ui.interact.model(),
        report = empty_report(),
        bundles = {},
        text_results = {},
        event_log = { "SDL3 gallery initialized" },
        click_count = 0,
        bypass = false,
        agree = true,
        voice = "poly",
        gain = 0.42,
        cutoff = 0.58,
        fader = 0.68,
        fine = 0,
        resonance = 0.36,
        meter = 0.2,
        progress = 0.45,
        wave = "saw",
        list_choice = "alpha",
        page = "controls",
        menu_open = false,
        select_open = false,
        theme_choice = "dark",
        popup_open = true,
        popover_open = false,
        modal_open = false,
        split_ratio = 0.46,
        canvas_last = "none",
        name_field = text_field.state("Lalin synth", 0, 0, {}),
        form_field = text_field.state("Form value", 0, 0, {}),
        notes_field = text_field.state("Tab moves focus. Try the sliders, text fields, popup, select, menu, modal, and the scroll panel.\nTyped input uses the session text system by default.", 0, 0, {}),
    }
end

local function log_event(model, msg)
    model.event_log[#model.event_log + 1] = msg
    while #model.event_log > 8 do
        table.remove(model.event_log, 1)
    end
end

local function node_list(items)
    local out = {}
    for i = 1, #items do
        local v = items[i]
        if v ~= nil and v ~= false then out[#out + 1] = v end
    end
    return out
end

local function section(id, title, children)
    return W.panel.bundle {
        id = id,
        title = title,
        children = children,
        styles = tw.list { tw.p_4, tw.rounded_xl, tw.border_1, tw.border_color.slate[800], tw.bg.slate[950], tw.gap_y_3 },
    }.node
end

local function small_label(id, text)
    return b.text { b.id(id), tw.text_xs, tw.fg.slate[400], text }
end

local function make_canvas_program(phase)
    local pts = {}
    for i = 0, 72 do
        local x = 12 + i * 3.8
        local y = 70 + math.sin(i * 0.22 + phase) * 24 + math.sin(i * 0.07 + phase * 0.4) * 10
        pts[#pts + 1] = x
        pts[#pts + 1] = y
    end
    return paint.list {
        paint.polygon({ 0, 0, 300, 0, 300, 140, 0, 140 }, paint.fill(0x020617ff), paint.stroke(0x334155ff, 1)),
        paint.line(12, 70, 288, 70, paint.stroke(0x1e293bff, 1)),
        paint.polyline(pts, paint.stroke(0x38bdf8ff, 3)),
        paint.circle(238, 44, 20, paint.fill(0xf59e0b55), paint.stroke(0xfbbf24ff, 2)),
        paint.arc(238, 44, 32, phase * 0.35, phase * 0.35 + 4.8, 32, paint.stroke(0xef4444ff, 4)),
        paint.mesh(paint.mesh_fan, {
            paint.vertex(70, 102), paint.vertex(112, 82), paint.vertex(148, 108),
            paint.vertex(132, 132), paint.vertex(82, 128),
        }, nil, 0x8b5cf688, 100),
    }
end

local function add_bundle(list, bundle)
    list[#list + 1] = bundle
    return bundle.node, bundle
end

local function build_gallery(window, model, phase)
    local report = model.report or empty_report()
    local imodel = model.interact
    local bundles = {}

    local function common(opts)
        opts.model = imodel
        opts.interact_model = imodel
        opts.report = report
        return opts
    end

    local run_button = add_bundle(bundles, W.button.bundle(common { id = "run-button", label = "Run", description = "Activates from pointer, Return, or Space" }))
    local modal_button = add_bundle(bundles, W.button.bundle(common { id = "open-modal", label = "Open modal" }))
    local popover_button = add_bundle(bundles, W.button.bundle(common { id = "open-popover", label = "Popover" }))
    local disabled_button = add_bundle(bundles, W.button.bundle(common { id = "disabled-button", label = "Disabled", disabled = true }))

    local toolbar = add_bundle(bundles, W.toolbar.bundle {
        id = "main-toolbar",
        title = false,
        children = node_list {
            b.text { b.id("toolbar-title"), tw.text_lg, tw.font_semibold, tw.fg.white, "Lalin SDL3 widget gallery" },
            run_button,
            modal_button,
            popover_button,
            disabled_button,
        },
    })

    local tabs = add_bundle(bundles, W.tabs.bundle(common {
        id = "main-tabs",
        items = {
            { key = "controls", label = "Controls" },
            { key = "text", label = "Text" },
            { key = "layers", label = "Layers" },
        },
        selected_key = model.page,
    }))

    local toggle = add_bundle(bundles, W.toggle.bundle(common { id = "bypass", label = "Bypass", selected = model.bypass }))
    local checkbox = add_bundle(bundles, W.checkbox.bundle(common { id = "agree", label = "Enable typed input", selected = model.agree }))
    local radio_poly = add_bundle(bundles, W.radio.bundle(common { id = "voice-poly", label = "Poly", value = "poly", selected = model.voice == "poly" }))
    local radio_mono = add_bundle(bundles, W.radio.bundle(common { id = "voice-mono", label = "Mono", value = "mono", selected = model.voice == "mono" }))

    local slider = add_bundle(bundles, W.slider.bundle(common { id = "gain", label = "Gain", value = model.gain, min = 0, max = 1, step = 0.01, show_value = true, precision = 2, focused = same_id(imodel.focus_id, ids.id("gain")) }))
    local fader = add_bundle(bundles, W.fader.bundle(common { id = "fader", label = "Fader", value = model.fader, min = 0, max = 1, step = 0.01, show_value = true, precision = 2, focused = same_id(imodel.focus_id, ids.id("fader")) }))
    local value_drag = add_bundle(bundles, W.value_drag.bundle(common { id = "fine", label = "Fine tune", value = model.fine, min = -100, max = 100, step = 1, show_value = true, precision = 0, focused = same_id(imodel.focus_id, ids.id("fine")) }))
    local knob = add_bundle(bundles, W.knob.bundle(common { id = "resonance", label = "Resonance", value = model.resonance, min = 0, max = 1, step = 0.01, show_value = true, precision = 2, focused = same_id(imodel.focus_id, ids.id("resonance")) }))

    local meter_value = (math.sin(phase * 0.08) + 1) * 0.5
    model.meter = meter_value
    local meter = add_bundle(bundles, W.meter.bundle { id = "level-meter", label = "Level meter", value = meter_value, peak = math.min(1, meter_value + 0.12), hold = 0.72, width = 220, show_value = true })
    local progress = add_bundle(bundles, W.progress.bundle { id = "load-progress", label = "Load progress", value = model.progress, width = 220, show_value = true })

    local list_plain = add_bundle(bundles, W.list.bundle(common {
        id = "plain-list",
        label = "Plain list",
        items = { "alpha", "beta", "gamma", "delta" },
        selected_key = model.list_choice,
        activatable = true,
        focusable = true,
    }))
    local listbox = add_bundle(bundles, W.listbox.bundle(common {
        id = "wave-listbox",
        label = "Wave listbox",
        items = {
            { key = "sine", label = "Sine" },
            { key = "saw", label = "Saw" },
            { key = "square", label = "Square" },
            { key = "noise", label = "Noise", disabled = true },
        },
        selected_key = model.wave,
    }))

    local menu = add_bundle(bundles, W.menu.bundle(common {
        id = "file-menu",
        label = "Menu",
        open = model.menu_open,
        items = { "New patch", "Duplicate", "Export", { key = "disabled", label = "Disabled", disabled = true } },
        selected_key = nil,
    }))
    local select_box = add_bundle(bundles, W.select.bundle(common {
        id = "theme-select",
        label = "Theme",
        value = model.theme_choice,
        open = model.select_open,
        items = { "dark", "blue", "amber" },
    }))

    local text_name = add_bundle(bundles, W.text_input.bundle(common(text_opts(window, "patch-name", "Patch name", 58))))
    local text_notes = add_bundle(bundles, W.text_area.bundle(common(text_opts(window, "patch-notes", "Notes", 132))))
    local cutoff_control = add_bundle(bundles, W.slider.bundle(common { id = "cutoff", label = false, value = model.cutoff, min = 0, max = 1, step = 0.01, show_value = false }))
    local form_input = add_bundle(bundles, W.text_input.bundle(common(text_opts(window, "form-name-input", "Form value", 52))))

    local property = add_bundle(bundles, W.property_row.bundle {
        id = "cutoff-row",
        label = "Cutoff row",
        description = "Property row wrapping a slider",
        control = cutoff_control,
    })
    local form_field = add_bundle(bundles, W.form_field.bundle {
        id = "form-name",
        label = "Form field",
        description = "A form-field alias around a text input shell",
        control = form_input,
    })
    local split = add_bundle(bundles, W.split_pane.bundle(common {
        id = "split-demo",
        ratio = model.split_ratio,
        first = b.text { b.id("split-left-text"), tw.text_sm, tw.fg.slate[300], "Split pane first child" },
        second = b.text { b.id("split-right-text"), tw.text_sm, tw.fg.slate[300], "Drag the separator" },
    }))
    local canvas = add_bundle(bundles, W.canvas.bundle(common {
        id = "scope-canvas",
        width = 300,
        height = 140,
        paint = make_canvas_program(phase),
        label = "Paint canvas",
    }))

    local log_rows = {}
    for i = #model.event_log, 1, -1 do
        log_rows[#log_rows + 1] = b.text { b.id("log-row-" .. tostring(#log_rows + 1)), tw.text_xs, tw.fg.slate[400], model.event_log[i] }
    end

    local controls_section = section("section-controls", "Catalog controls", node_list {
        b.box { b.id("toggle-row"), tw.flex, tw.row, tw.wrap, tw.gap_x_2, tw.gap_y_2, toggle, checkbox, radio_poly, radio_mono },
        b.box { b.id("numeric-row"), tw.grid, tw.cols_2, tw.gap_4, slider, value_drag, knob, fader },
        b.box { b.id("meter-row"), tw.flex, tw.row, tw.wrap, tw.gap_x_4, tw.gap_y_2, meter, progress },
        property,
    })

    local lists_section = section("section-lists", "Lists, tabs, menus, select", node_list {
        tabs,
        b.box { b.id("list-row"), tw.grid, tw.cols_2, tw.gap_4, list_plain, listbox },
        b.box { b.id("menu-row"), tw.flex, tw.row, tw.wrap, tw.gap_x_3, tw.gap_y_2, menu, select_box },
    })

    local text_section = section("section-text", "Session text lifecycle", node_list {
        small_label("text-help", "Text overlays use window.text_key from ui.session_sdl3; typing is routed through typed Interact.Raw values."),
        text_name,
        text_notes,
        form_field,
    })

    local layout_section = section("section-layout", "Composition, scrolling, split panes, canvas", node_list {
        split,
        canvas,
        b.text { b.id("canvas-status"), tw.text_xs, tw.fg.slate[400], "Canvas: " .. tostring(model.canvas_last) },
    })

    local log_section = section("section-log", "Routed widget events", log_rows)

    local scroll_panel = add_bundle(bundles, W.scroll_panel.bundle(common {
        id = "gallery-scroll",
        label = "Gallery scroll panel",
        children = node_list {
            controls_section,
            lists_section,
            text_section,
            layout_section,
            log_section,
        },
        styles = tw.list { tw.h_px(620), tw.p_3, tw.rounded_xl, tw.border_1, tw.border_color.slate[900], tw.bg.slate[950], tw.overflow_y_auto },
        content_styles = tw.list { tw.flex, tw.col, tw.gap_y_4 },
    }))

    local tooltip = add_bundle(bundles, W.tooltip.bundle {
        id = "gallery-tooltip",
        open = true,
        anchor_id = ids.id("run-button"),
        content = "Tooltip layer: Tab, Shift+Tab, Return/Space, Escape, wheel, text input.",
    })
    local overlay = add_bundle(bundles, W.overlay.bundle {
        id = "gallery-overlay",
        open = true,
        placement = Interact.PlaceRight,
        content = "Overlay layer",
    })
    local popup = add_bundle(bundles, W.popup.bundle {
        id = "gallery-popup",
        open = model.popup_open,
        child = b.text { b.id("gallery-popup-text"), tw.p_2, tw.rounded_lg, tw.bg.slate[900], tw.border_1, tw.border_color.sky[800], tw.text_xs, tw.fg.sky[100], "Popup layer (Esc/cancel closes)." },
    })
    local popover = add_bundle(bundles, W.popover.bundle {
        id = "gallery-popover",
        open = model.popover_open,
        content = b.box {
            b.id("popover-body"), tw.flex, tw.col, tw.gap_y_2, tw.p_3, tw.rounded_xl, tw.border_1, tw.border_color.slate[700], tw.bg.slate[950],
            b.text { b.id("popover-title"), tw.text_sm, tw.font_semibold, tw.fg.white, "Popover" },
            b.text { b.id("popover-copy"), tw.text_xs, tw.fg.slate[300], "This exercises popup layers, focus scopes, and close routing." },
        },
    })
    local modal = add_bundle(bundles, W.modal.bundle {
        id = "gallery-modal",
        open = model.modal_open,
        title = "Modal dialog",
        body = "The modal emits a barrier and traps focus. Press Escape or Close.",
        close_label = "Close",
    })

    local root = b.box {
        b.id("gallery-root"),
        tw.w_px(window.host:size()),
        tw.h_px(({ window.host:size() })[2]),
        tw.flex,
        tw.col,
        tw.gap_y_3,
        tw.p_4,
        tw.bg.slate[950],
        tw.fg.slate[100],
        toolbar,
        scroll_panel,
        tooltip,
        overlay,
        popup,
        popover,
        modal,
    }

    model.bundles = bundles
    return root, bundles
end

local function route_widget_events(model, ui_events)
    local out = {}
    for i = 1, #(model.bundles or {}) do
        local bundle = model.bundles[i]
        local routed = bundle:route_ui_events(ui_events)
        for j = 1, #routed do out[#out + 1] = routed[j] end
    end
    return out
end

local function apply_widget_event(model, ev)
    local key = id_key(ev.widget_id or ev.id)
    if ev.kind == "activate" then
        if key == "run-button" then
            model.click_count = model.click_count + 1
            model.progress = math.min(1, model.progress + 0.08)
            log_event(model, "Run activated #" .. tostring(model.click_count))
        elseif key == "open-modal" then
            model.modal_open = true
            log_event(model, "Modal opened")
        elseif key == "open-popover" then
            model.popover_open = not model.popover_open
            log_event(model, "Popover " .. (model.popover_open and "opened" or "closed"))
        end
    elseif ev.kind == "change" then
        if key == "bypass" then model.bypass = ev.value == true
        elseif key == "agree" then model.agree = ev.value == true
        elseif key == "voice-poly" or key == "voice-mono" then model.voice = ev.value
        elseif key == "gain" then model.gain = ev.value
        elseif key == "fader" then model.fader = ev.value
        elseif key == "fine" then model.fine = ev.value
        elseif key == "resonance" then model.resonance = ev.value
        elseif key == "cutoff" then model.cutoff = ev.value
        elseif key == "split-demo" then model.split_ratio = ev.ratio or ev.value
        end
        log_event(model, "change " .. tostring(key) .. " = " .. tostring(ev.value))
    elseif ev.kind == "select" then
        if key == "main-tabs" then model.page = ev.value
        elseif key == "plain-list" then model.list_choice = ev.value
        elseif key == "wave-listbox" then model.wave = ev.value
        elseif key == "file-menu" then model.menu_open = false; log_event(model, "menu select " .. tostring(ev.value))
        end
    elseif ev.kind == "open" then
        if key == "file-menu" then model.menu_open = true
        elseif key == "theme-select" then model.select_open = true
        end
    elseif ev.kind == "close" then
        if key == "file-menu" then model.menu_open = false
        elseif key == "theme-select" then model.select_open = false
        elseif key == "gallery-popup" then model.popup_open = false
        elseif key == "gallery-popover" then model.popover_open = false
        elseif key == "gallery-modal" then model.modal_open = false
        end
    elseif ev.kind == "input" then
        if key == "patch-name" then model.name_field = text_field.text_input(model.name_field, ev.text)
        elseif key == "form-name-input" then model.form_field = text_field.text_input(model.form_field, ev.text)
        elseif key == "patch-notes" then model.notes_field = text_field.text_input(model.notes_field, ev.text)
        end
    elseif ev.kind == "edit" then
        if key == "patch-name" then model.name_field = text_field.text_editing(model.name_field, ev.text, ev.start, ev.length)
        elseif key == "form-name-input" then model.form_field = text_field.text_editing(model.form_field, ev.text, ev.start, ev.length)
        elseif key == "patch-notes" then model.notes_field = text_field.text_editing(model.notes_field, ev.text, ev.start, ev.length)
        end
    elseif ev.kind == "canvas_drag" or ev.kind == "canvas_drop" or ev.kind == "pointer_down" then
        model.canvas_last = string.format("%s @ %.1f, %.1f", ev.kind, ev.local_x or 0, ev.local_y or 0)
    end
end

local function focused_text_id(model)
    local fid = model.interact and model.interact.focus_id or Core.NoId
    if same_id(fid, ids.id("patch-name")) then return "patch-name" end
    if same_id(fid, ids.id("form-name-input")) then return "form-name-input" end
    if same_id(fid, ids.id("patch-notes")) then return "patch-notes" end
    return nil
end

local function sync_text_focus(model)
    local focused = focused_text_id(model)
    model.name_field = pvm.with(model.name_field, { focused = focused == "patch-name" })
    model.form_field = pvm.with(model.form_field, { focused = focused == "form-name-input" })
    model.notes_field = pvm.with(model.notes_field, { focused = focused == "patch-notes" })
end

local function apply_text_pointer(model, raw)
    local cls = pvm.classof(raw)
    if cls == Interact.PointerPressed and raw.button == Interact.BtnLeft then
        for id, field_name in pairs({ ["patch-name"] = "name_field", ["form-name-input"] = "form_field", ["patch-notes"] = "notes_field" }) do
            local result = model.text_results and model.text_results[id]
            if result ~= nil and W.text_input.contains(result, raw.x, raw.y) then
                local lx, ly = W.text_input.local_point(result, raw.x, raw.y)
                model[field_name] = text_field.pointer_pressed(result.resolved.layout, model[field_name], lx, ly, false)
            end
        end
    elseif cls == Interact.PointerReleased and raw.button == Interact.BtnLeft then
        model.name_field = text_field.pointer_released(model.name_field)
        model.form_field = text_field.pointer_released(model.form_field)
        model.notes_field = text_field.pointer_released(model.notes_field)
    elseif cls == Interact.PointerMoved then
        for id, field_name in pairs({ ["patch-name"] = "name_field", ["form-name-input"] = "form_field", ["patch-notes"] = "notes_field" }) do
            local result = model.text_results and model.text_results[id]
            if result ~= nil then
                local lx, ly = W.text_input.local_point(result, raw.x, raw.y)
                model[field_name] = text_field.pointer_moved(result.resolved.layout, model[field_name], lx, ly)
            end
        end
    end
end

local function apply_text_key(window, model, raw, host_ev)
    if pvm.classof(raw) ~= Interact.KeyPressed or host_ev == nil or host_ev.type ~= "key_down" then return end
    local id = focused_text_id(model)
    if id == nil then return end
    local result = model.text_results and model.text_results[id]
    if result == nil then return end
    local field_name = id == "patch-name" and "name_field" or (id == "form-name-input" and "form_field" or "notes_field")
    model[field_name] = text_field.key(result.resolved.layout, model[field_name], host_ev.key, host_ev.shift, host_ev.ctrl, {
        repeat_ = host_ev.repeat_,
        get_clipboard_text = function()
            if window.host:has_clipboard_text() then return window.host:get_clipboard_text() end
            return nil
        end,
        set_clipboard_text = function(text)
            window.host:set_clipboard_text(text)
        end,
    })
end

local function handle_raw(session, window, raw, host_ev)
    local model = window.state
    local report = model.report or empty_report()
    local raw_ui_events
    model.interact, raw_ui_events = ui.interact.step(model.interact, report, raw)
    sync_text_focus(model)
    apply_text_key(window, model, raw, host_ev)
    apply_text_pointer(model, raw)

    local widget_events = route_widget_events(model, raw_ui_events)
    for i = 1, #widget_events do
        apply_widget_event(model, widget_events[i])
    end

    if host_ev ~= nil and host_ev.type == "key_down" and host_ev.ctrl and host_ev.key == input.KeyQ then
        session:stop()
    end

    window:request_redraw()
end

local function draw_window(session, window)
    local host = window.host
    local model = window.state
    local vw, vh = host:size()
    local phase = host:now_ms() / 16

    local root = build_gallery(window, model, phase)
    if VALIDATE_IDS_EACH_FRAME then
        ui.id.assert_auth(root)
    end
    if model._env == nil or model._env_w ~= vw then
        model._env = ui.theme.env_for_width(vw, { density = T.Env.D1x })
        model._env_w = vw
    end
    local lowered = ui.lower.root(root, DEFAULT_THEME, model._env, {
        model = model.interact,
        report = model.report,
        validate_ids = false,
    })
    assert(#lowered == 1, "gallery lowers to one root")

    local solve_env = Solve.Env(vw, vh)
    local solved = pvm.one(ui.solve.root(lowered[1].layout, solve_env, window.text_key))
    local rg, rp, rc = ui.render.root(solved, lowered[1].decor)

    host:begin_frame(0x020617ff)
    local report = ui.runtime.run(host.driver, {
        pointer_x = model.interact.pointer_x,
        pointer_y = model.interact.pointer_y,
        scrolls = model.interact.scrolls,
    }, rg, rp, rc)
    model.report = report
    model.interact = ui.interact.clamp_model(model.interact, report)
    sync_text_focus(model)

    model.text_results = {
        ["patch-name"] = W.text_input.draw(window, report, model.name_field, text_opts(window, "patch-name", "Patch name", 58)),
        ["patch-notes"] = W.text_area.draw(window, report, model.notes_field, text_opts(window, "patch-notes", "Notes", 132)),
        ["form-name-input"] = W.text_input.draw(window, report, model.form_field, text_opts(window, "form-name-input", "Form value", 52)),
    }

    host:present()
    session:request_redraw_after(window, 16)
end

local function main()
    local session = session_sdl3.new {
        title = "Lalin SDL3 widget gallery",
        width = 1120,
        height = 780,
        vsync = true,
        default_font = FONT,
        redraw_mode = "dirty",
        frame_delay_ms = 8,
    }

    local window = session:create_window {
        title = "Lalin SDL3 widget gallery",
        width = 1120,
        height = 780,
        state = new_model(),
        on_raw_ui = handle_raw,
        on_draw = draw_window,
        on_event = function(session_, window_, ev)
            if ev.type == "quit" or ev.type == "window_close_requested" then
                session_:stop()
            end
        end,
    }

    window:set_text_input(true)
    session:run { close_on_exit = true }
end

main()
