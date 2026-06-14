local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Auth = T.Auth
local Interact = T.Interact

local M = {}

local function classof(v)
    if v == nil then return nil end
    return pvm.classof(v)
end

local function id_key(id)
    if id == nil or id == Core.NoId then return nil end
    if type(id) == "string" then return id end
    return id.value
end

local function same_id(a, b)
    local ak, bk = id_key(a), id_key(b)
    return ak ~= nil and bk ~= nil and ak == bk
end

local function no_state()
    return Style.State(false, false, false, false, false)
end

M.no_state = no_state

function M.is_empty(state)
    return state == nil
        or (not state.hovered
            and not state.focused
            and not state.active
            and not state.selected
            and not state.disabled)
end

function M.merge(a, b)
    if a == nil then a = no_state() end
    if b == nil then b = no_state() end
    return Style.State(
        a.hovered or b.hovered,
        a.focused or b.focused,
        a.active or b.active,
        a.selected or b.selected,
        a.disabled or b.disabled
    )
end

local function flag_from(spec, id)
    if spec == nil then return false end
    local key = id_key(id)
    if key == nil then return false end

    if type(spec) == "boolean" then
        return spec == true
    end
    if type(spec) == "function" then
        return spec(id, key) == true
    end
    if type(spec) == "table" then
        if spec[key] ~= nil then return spec[key] == true end
        if spec[id] ~= nil then return spec[id] == true end
        return false
    end
    return same_id(spec, id)
end

local function drag_active_for_id(drag, id)
    local cls = classof(drag)
    if cls == Interact.DragPending or cls == Interact.Dragging then
        return same_id(drag.source_id, id)
    end
    return false
end

local function capture_active_for_id(model, id)
    if model == nil then return false end
    local cap = model.capture
    local cls = classof(cap)
    if cls == Interact.Captured then
        return same_id(cap.id, id)
    end
    return false
end

function M.for_id(id, model, report, opts)
    opts = opts or {}
    local hovered = false
    local focused = false
    local active = false

    if model ~= nil then
        hovered = hovered or same_id(model.hover_id, id)
        focused = focused or same_id(model.focus_id, id)
        active = active or same_id(model.pressed_id, id)
        active = active or capture_active_for_id(model, id)
        active = active or drag_active_for_id(model.drag, id)
    end

    if report ~= nil then
        hovered = hovered or same_id(report.hover_id, id)
    end

    active = active or flag_from(opts.active_ids or opts.active, id)

    return Style.State(
        hovered,
        focused,
        active,
        flag_from(opts.selected_ids or opts.selected, id),
        flag_from(opts.disabled_ids or opts.disabled, id)
    )
end

function M.provider(model, report, opts)
    return function(id, explicit)
        local derived = M.for_id(id, model, report, opts)
        if explicit ~= nil then
            return M.merge(derived, explicit)
        end
        return derived
    end
end

local function should_wrap(state, opts)
    if opts ~= nil and opts.wrap_empty == true then return true end
    return not M.is_empty(state)
end

local function wrap_with_state(id, node, provider, opts)
    if provider == nil then return node end
    local state = provider(id)
    if should_wrap(state, opts) then
        return Auth.WithState(state, node)
    end
    return node
end

local function apply_node(node, provider, opts)
    local cls = classof(node)
    if cls == nil then return node end

    if cls == Auth.Box then
        local children = {}
        for i = 1, #node.children do
            children[i] = apply_node(node.children[i], provider, opts)
        end
        return wrap_with_state(node.id, Auth.Box(node.id, node.styles, children), provider, opts)
    elseif cls == Auth.Text then
        return wrap_with_state(node.id, Auth.Text(node.id, node.styles, node.content), provider, opts)
    elseif cls == Auth.TextRef then
        return wrap_with_state(node.id, Auth.TextRef(node.id, node.styles, node.content_id), provider, opts)
    elseif cls == Auth.Paint then
        return wrap_with_state(node.id, Auth.Paint(node.id, node.styles, node.paint), provider, opts)
    elseif cls == Auth.Scroll then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.Scroll(node.id, node.styles, node.axis, child), provider, opts)
    elseif cls == Auth.WithState then
        local child = apply_node(node.child, provider, opts)
        return Auth.WithState(node.state, child)
    elseif cls == Auth.WithInput then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.WithInput(node.id, node.role, child), provider, opts)
    elseif cls == Auth.WithDragSource then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.WithDragSource(node.id, child), provider, opts)
    elseif cls == Auth.WithDropTarget then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.WithDropTarget(node.id, child), provider, opts)
    elseif cls == Auth.WithDropSlot then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.WithDropSlot(node.id, child), provider, opts)
    elseif cls == Auth.FocusScope then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.FocusScope(node.id, node.policy, child), provider, opts)
    elseif cls == Auth.Layer then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.Layer(node.id, node.kind, node.order, child), provider, opts)
    elseif cls == Auth.Overlay then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.Overlay(node.id, node.anchor_id, node.placement, node.modal, child), provider, opts)
    elseif cls == Auth.Modal then
        local child = apply_node(node.child, provider, opts)
        return wrap_with_state(node.id, Auth.Modal(node.id, child), provider, opts)
    elseif cls == Auth.Fragment then
        local children = {}
        for i = 1, #node.children do
            children[i] = apply_node(node.children[i], provider, opts)
        end
        return Auth.Fragment(children)
    elseif cls == Auth.Empty or node == Auth.Empty or cls == classof(Auth.Empty) then
        return node
    end

    error("ui.state.apply_to_auth: unknown Auth node", 2)
end

function M.apply_to_auth(node, provider, opts)
    return apply_node(node, provider, opts)
end

function M.apply_model_to_auth(node, model, report, opts)
    return M.apply_to_auth(node, M.provider(model, report, opts), opts)
end

return M
