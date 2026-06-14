local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact
local Paint = T.Paint

local M = {}

local DEFAULTS = {
    kind = "canvas",
    role = "canvas",
    width = 320,
    height = 180,
    draggable = true,
    activatable = true,
    redraw = "on_change",
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.rounded_lg,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
        tw.cursor_pointer,
        tw.hover { tw.border_color.slate[600] },
        tw.active { tw.border_color.sky[500] },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
    paint_styles = nil,
}

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end
local function add_style(items, value) if value ~= nil and value ~= false then items[#items + 1] = value end end

local function is_paint_program(v)
    local cls = pvm.classof(v)
    return cls and Paint.Program.members[cls]
end

local function is_paint_list(v)
    return pvm.classof(v) == Paint.ProgramList
end

local function append_paint(items, value)
    if value == nil or value == false then return end
    if is_paint_program(value) or is_paint_list(value) then
        items[#items + 1] = value
    elseif type(value) == "table" then
        for i = 1, #value do append_paint(items, value[i]) end
    else
        error("canvas paint expects Paint.Program, Paint.ProgramList, or array", 3)
    end
end

local function programs_from_opts(opts)
    if opts.program ~= nil then return opts.program end
    if opts.programs ~= nil then return opts.programs end
    if opts.paint ~= nil then return opts.paint end
    return nil
end

function M.find_hit(report, id)
    if report == nil then return nil end
    local key = id_key(id)
    local lists = { report.hits, report.hit_stack }
    for li = 1, #lists do
        local hits = lists[li]
        if hits ~= nil then
            for i = #hits, 1, -1 do
                if id_key(hits[i].id) == key then return hits[i] end
            end
        end
    end
    return nil
end

function M.local_point(report_or_box, id, x, y, opts)
    opts = opts or {}
    local box = report_or_box
    if report_or_box ~= nil and (report_or_box.hits ~= nil or report_or_box.hit_stack ~= nil) then
        box = M.find_hit(report_or_box, id)
    end
    if box == nil then return nil end
    local lx = (x or 0) - (box.x or 0)
    local ly = (y or 0) - (box.y or 0)
    local sx = opts.scale_x or ((opts.width and box.w and box.w ~= 0) and (opts.width / box.w) or 1)
    local sy = opts.scale_y or ((opts.height and box.h and box.h ~= 0) and (opts.height / box.h) or 1)
    return lx * sx, ly * sy, box
end

function M.contains(report_or_box, id, x, y)
    local box = report_or_box
    if report_or_box ~= nil and (report_or_box.hits ~= nil or report_or_box.hit_stack ~= nil) then box = M.find_hit(report_or_box, id) end
    if box == nil then return false end
    return x >= box.x and y >= box.y and x < box.x + box.w and y < box.y + box.h
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "canvas id")
    local w = opts.width or DEFAULTS.width
    local h = opts.height or DEFAULTS.height

    local paint_items = { b.id(id_key(child_id(id, "paint"))), tw.w_px(w), tw.h_px(h) }
    add_style(paint_items, DEFAULTS.paint_styles)
    add_style(paint_items, opts.paint_styles)
    append_paint(paint_items, programs_from_opts(opts))
    local paint_node = b.paint(paint_items)
    if opts.draggable ~= false then
        paint_node = b.drag_source(child_id(id, "drag"), paint_node)
    end

    local box_items = { b.id(id_key(child_id(id, "box"))), tw.w_px(w), tw.h_px(h) }
    add_style(box_items, DEFAULTS.styles)
    add_style(box_items, opts.styles)
    box_items[#box_items + 1] = paint_node

    local role
    if opts.disabled then role = Interact.Passive
    elseif opts.activatable == false then role = Interact.HitTarget
    else role = Interact.ActivateTarget end
    local node = b.with_input(id, role, b.box(box_items))
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "canvas id")
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        width = opts.width or DEFAULTS.width,
        height = opts.height or DEFAULTS.height,
        images = opts.images,
        backend_expect = opts.backend_expect or { paint = true, images = opts.images ~= nil },
    }
    widget.add_surface(surfaces, "input", id, common)
    widget.add_surface(surfaces, "canvas", id, common)
    widget.add_surface(surfaces, "paint", child_id(id, "paint"), common)
    if opts.draggable ~= false then widget.add_surface(surfaces, "drag", child_id(id, "drag"), common) end
    return surfaces
end

local function point_event(kind, bundle, source, x, y, fields)
    fields = fields or {}
    local lx, ly, box = M.local_point(bundle and bundle.report, bundle and bundle.id, x, y, bundle or {})
    fields.x = x
    fields.y = y
    fields.local_x = lx
    fields.local_y = ly
    fields.box = box
    fields.source = source
    return widget.event(kind, bundle.id, fields)
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if bundle == nil then return widget.route_interact_event(surfaces, ui_event, bundle) end

    if cls == Interact.PointerPressed then
        if M.contains(bundle.report, bundle.id, ui_event.x, ui_event.y) then
            return point_event("pointer_down", bundle, ui_event, ui_event.x, ui_event.y, { button = ui_event.button })
        end
    elseif cls == Interact.PointerMoved then
        if M.contains(bundle.report, bundle.id, ui_event.x, ui_event.y) then
            return point_event("pointer_move", bundle, ui_event, ui_event.x, ui_event.y)
        end
    elseif cls == Interact.PointerReleased then
        if M.contains(bundle.report, bundle.id, ui_event.x, ui_event.y) then
            return point_event("pointer_up", bundle, ui_event, ui_event.x, ui_event.y, { button = ui_event.button })
        end
    elseif cls == Interact.DragMoved then
        local info = widget.lookup_surface(surfaces, "drag", ui_event.source_id)
        if info ~= nil then return point_event("canvas_drag", bundle, ui_event, ui_event.x, ui_event.y, { id = info.id }) end
    elseif cls == Interact.DragDropped then
        local info = widget.lookup_surface(surfaces, "drag", ui_event.source_id)
        if info ~= nil then return point_event("canvas_drop", bundle, ui_event, ui_event.x, ui_event.y, { id = info.id }) end
    elseif cls == Interact.Activate then
        local info = widget.lookup_surface(surfaces, "canvas", ui_event.id) or widget.lookup_surface(surfaces, "input", ui_event.id)
        if info ~= nil then return widget.activate_event(bundle.id, { id = info.id, source = ui_event }) end
    end

    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "canvas id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        width = opts.width or DEFAULTS.width,
        height = opts.height or DEFAULTS.height,
        scale_x = opts.scale_x,
        scale_y = opts.scale_y,
        report = opts.report,
        images = opts.images,
        backend_expect = opts.backend_expect or { paint = true, images = opts.images ~= nil },
        redraw = opts.redraw or DEFAULTS.redraw,
        style_slots = { root = opts.styles or DEFAULTS.styles, paint = opts.paint_styles or DEFAULTS.paint_styles },
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

M.DEFAULTS = DEFAULTS
M.T = T
return M
