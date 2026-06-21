local pvm = require("pvm")
local A = require("mlui.asdl")
local tw = require("mlui.tw")

local T = A.T
local B = A.B
local Core = T.Core
local Style = T.Style
local Paint = T.Paint
local Auth = T.Auth
local Compose = T.Compose
local Interact = T.Interact

local M = {}

local EMPTY_STYLES = B.Style.TokenList { items = {} }
local EMPTY_PAINT = B.Paint.ProgramList { items = {} }

local function classof(v)
    return pvm.classof(v)
end

local function id(value)
    if value == nil or value == false then return Core.NoId end
    local cls = classof(value)
    if cls and Core.Id.members[cls] then return value end
    return B.Core.IdValue { value = tostring(value) }
end

local function is_node(v)
    local cls = classof(v)
    return cls and Auth.Node.members[cls] or false
end

local function is_compose(v)
    local cls = classof(v)
    return cls and Compose.Node.members[cls] or false
end

local function is_token(v)
    return classof(v) == Style.Token
end

local function is_group(v)
    local cls = classof(v)
    return cls == Style.Group or cls == Style.TokenList
end

local function is_paint(v)
    local cls = classof(v)
    return cls and Paint.Program.members[cls] or false
end

local function plain_array_last(items)
    local max = 0
    for k in pairs(items) do
        if type(k) == "number" and k >= 1 and k == math.floor(k) and k > max then max = k end
    end
    return max
end

local function finish_value(v)
    if type(v) == "table" and v._mlui_finish then return v:_mlui_finish() end
    return v
end

local function collect_styles(opts, out)
    if opts.style ~= nil then out[#out + 1] = opts.style end
    if opts.styles ~= nil then out[#out + 1] = opts.styles end
    local n = plain_array_last(opts)
    for i = 1, n do
        local v = finish_value(opts[i])
        if v ~= nil and v ~= false and (is_token(v) or is_group(v)) then out[#out + 1] = v end
    end
end

local function style_list(opts)
    local values = {}
    collect_styles(opts or {}, values)
    if #values == 0 then return EMPTY_STYLES end
    return tw.list(values)
end

local function collect_children(opts)
    local out = {}
    local n = plain_array_last(opts)
    for i = 1, n do
        local v = finish_value(opts[i])
        if v ~= nil and v ~= false and not is_token(v) and not is_group(v) then
            if is_node(v) then out[#out + 1] = v
            elseif type(v) == "string" or type(v) == "number" then
                out[#out + 1] = B.Auth.Text { id = Core.NoId, styles = EMPTY_STYLES, content = tostring(v) }
            else error("expected authored child node", 3) end
        end
    end
    return out
end

local function child_from_opts(opts)
    local child = finish_value(opts.child or opts.node or opts.body or opts.content)
    if child == nil or child == false then return Auth.Empty end
    if is_node(child) then return child end
    if type(child) == "string" or type(child) == "number" then
        return B.Auth.Text { id = Core.NoId, styles = EMPTY_STYLES, content = tostring(child) }
    end
    error("expected authored child node", 3)
end

local function make_auth_builder(kind, staged)
    return setmetatable({ _kind = kind, _staged = staged }, {
        __call = function(builder, arg)
            if type(arg) == "string" then return make_auth_builder(kind, arg) end
            if type(arg) ~= "table" or classof(arg) then error("builder expects string stage or plain table", 2) end
            if kind == "box" then
                return B.Auth.Box {
                    id = id(arg.id or builder._staged),
                    styles = style_list(arg),
                    children = collect_children(arg),
                }
            elseif kind == "text" then
                local content = arg.content or builder._staged or ""
                local n = plain_array_last(arg)
                for i = 1, n do
                    local v = arg[i]
                    if type(v) == "string" or type(v) == "number" then content = tostring(v) end
                end
                return B.Auth.Text { id = id(arg.id), styles = style_list(arg), content = tostring(content) }
            elseif kind == "text_ref" then
                return B.Auth.TextRef {
                    id = id(arg.id),
                    styles = style_list(arg),
                    content_id = id(arg.content or arg.content_id or builder._staged),
                }
            elseif kind == "paint" then
                local paint = {}
                local n = plain_array_last(arg)
                for i = 1, n do
                    local v = finish_value(arg[i])
                    if v ~= nil and v ~= false and not is_token(v) and not is_group(v) then paint[#paint + 1] = v end
                end
                return B.Auth.Paint {
                    id = id(arg.id or builder._staged),
                    styles = style_list(arg),
                    paint = B.Paint.ProgramList { items = paint },
                }
            elseif kind == "fragment" then
                return B.Auth.Fragment { children = collect_children(arg) }
            end
            error("unknown auth builder kind", 2)
        end,
        __index = function(builder, key)
            if key == "_mlui_finish" then
                return function(v)
                    if v._kind == "text" then
                        return B.Auth.Text { id = Core.NoId, styles = EMPTY_STYLES, content = tostring(v._staged or "") }
                    end
                    if v._kind == "text_ref" then
                        return B.Auth.TextRef { id = Core.NoId, styles = EMPTY_STYLES, content_id = id(v._staged) }
                    end
                    if v._kind == "box" then
                        return B.Auth.Box { id = id(v._staged), styles = EMPTY_STYLES, children = {} }
                    end
                    if v._kind == "paint" then
                        return B.Auth.Paint { id = id(v._staged), styles = EMPTY_STYLES, paint = EMPTY_PAINT }
                    end
                    if v._kind == "fragment" then return B.Auth.Fragment { children = {} } end
                    return Auth.Empty
                end
            end
            return rawget(builder, key)
        end,
    })
end

local function wrapper(fn)
    return setmetatable({}, {
        __call = function(_, arg)
            if type(arg) == "string" then
                return setmetatable({ _staged = arg }, {
                    __call = function(staged, opts) return fn(staged._staged, opts or {}) end,
                })
            end
            if type(arg) == "table" and not classof(arg) then return fn(nil, arg) end
            error("wrapper expects string stage or plain table", 2)
        end,
        __index = function(_, key)
            return wrapper(function(staged, opts)
                opts.variant = opts.variant or key
                return fn(staged, opts)
            end)
        end,
    })
end

local function scroll_axis(v)
    if v == "x" then return Style.ScrollX end
    if v == "both" or v == "xy" then return Style.ScrollBoth end
    return Style.ScrollY
end

local function role(v)
    if v == "hit" then return Interact.HitTarget end
    if v == "focus" then return Interact.FocusTarget end
    if v == "edit" then return Interact.EditTarget end
    if v == "passive" then return Interact.Passive end
    return Interact.ActivateTarget
end

local function focus_policy(opts)
    if opts.policy then return opts.policy end
    if opts.trap then return Interact.FocusTrap end
    if opts.wrap == false then return Interact.FocusClamp end
    if opts.passthrough then return Interact.FocusPassthrough end
    return Interact.FocusWrap
end

local function layer_kind(v)
    if v == "popup" then return Interact.LayerPopup end
    if v == "tooltip" then return Interact.LayerTooltip end
    if v == "modal" then return Interact.LayerModal end
    if v == "drag_preview" then return Interact.LayerDragPreview end
    if v == "base" then return Interact.LayerBase end
    return Interact.LayerOverlay
end

local function placement(v)
    if v == "above" then return Interact.PlaceAbove end
    if v == "below" then return Interact.PlaceBelow end
    if v == "left" then return Interact.PlaceLeft end
    if v == "right" then return Interact.PlaceRight end
    if v == "center" then return Interact.PlaceCenter end
    return Interact.PlaceAuto
end

local function compose_node(v)
    v = finish_value(v)
    if v == nil or v == false then return nil end
    if is_compose(v) then return v end
    if is_node(v) then return B.Compose.Raw { child = v } end
    error("expected compose or authored node", 3)
end

local function compose_children(opts)
    local out = {}
    local n = plain_array_last(opts)
    for i = 1, n do
        local child = compose_node(opts[i])
        if child then out[#out + 1] = child end
    end
    return out
end

local function maybe_styles(v)
    if v == nil or v == false then return nil end
    if is_token(v) then return B.Style.TokenList { items = { v } } end
    if is_group(v) then return B.Style.TokenList { items = v.items } end
    return tw.list(v)
end

local function make_compose(kind, staged)
    return setmetatable({ _kind = kind, _staged = staged }, {
        __call = function(builder, arg)
            if type(arg) == "string" then return make_compose(kind, arg) end
            if type(arg) ~= "table" or classof(arg) then error("compose builder expects string stage or plain table", 2) end
            local node_id = id(arg.id or builder._staged)
            if kind == "fragment" then return B.Compose.Fragment { children = compose_children(arg) } end
            if kind == "raw" then return B.Compose.Raw { child = child_from_opts(arg) } end
            if kind == "panel" then
                return B.Compose.Panel {
                    id = node_id, styles = maybe_styles(arg.styles or arg.style),
                    header_styles = maybe_styles(arg.header_styles), header = compose_node(arg.header or arg.title),
                    body_styles = maybe_styles(arg.body_styles), body = compose_node(arg.body or arg.child),
                    footer_styles = maybe_styles(arg.footer_styles), footer = compose_node(arg.footer),
                }
            end
            if kind == "scroll_panel" then
                return B.Compose.ScrollPanel {
                    id = node_id, styles = maybe_styles(arg.styles or arg.style),
                    header_styles = maybe_styles(arg.header_styles), header = compose_node(arg.header or arg.title),
                    scroll_id = id(arg.scroll_id or tostring(arg.id or builder._staged or "scroll") .. ":scroll"),
                    axis = scroll_axis(arg.axis or arg.variant),
                    scroll_styles = maybe_styles(arg.scroll_styles),
                    body_styles = maybe_styles(arg.body_styles), body = compose_node(arg.body or arg.child),
                    footer_styles = maybe_styles(arg.footer_styles), footer = compose_node(arg.footer),
                }
            end
            if kind == "hsplit" then return B.Compose.HSplit { id = node_id, styles = maybe_styles(arg.styles or arg.style), children = compose_children(arg) } end
            if kind == "vsplit" then return B.Compose.VSplit { id = node_id, styles = maybe_styles(arg.styles or arg.style), children = compose_children(arg) } end
            if kind == "workbench" then
                return B.Compose.Workbench {
                    id = node_id, styles = maybe_styles(arg.styles or arg.style),
                    top_styles = maybe_styles(arg.top_styles), top = compose_node(arg.top or arg.toolbar),
                    middle_styles = maybe_styles(arg.middle_styles),
                    left_styles = maybe_styles(arg.left_styles), left = compose_node(arg.left or arg.sidebar),
                    center_styles = maybe_styles(arg.center_styles), center = compose_node(arg.center or arg.main or Auth.Empty),
                    right_styles = maybe_styles(arg.right_styles), right = compose_node(arg.right),
                    bottom_styles = maybe_styles(arg.bottom_styles), bottom = compose_node(arg.bottom),
                }
            end
            error("unknown compose kind", 2)
        end,
    })
end

M.id = id
M.box = make_auth_builder("box")
M.text = make_auth_builder("text")
M.text_ref = make_auth_builder("text_ref")
M.paint = make_auth_builder("paint")
M.fragment = make_auth_builder("fragment")
M.empty = Auth.Empty

M.scroll = wrapper(function(staged, opts)
    return B.Auth.Scroll { id = id(opts.id or staged), styles = style_list(opts), axis = scroll_axis(opts.axis or opts.variant), child = child_from_opts(opts) }
end)
M.input = wrapper(function(staged, opts)
    return B.Auth.WithInput { id = id(opts.id or staged), role = role(opts.role or opts.variant), child = child_from_opts(opts) }
end)
M.drag = { source = wrapper(function(staged, opts) return B.Auth.WithDragSource { id = id(opts.id or staged), child = child_from_opts(opts) } end) }
M.drop = {
    target = wrapper(function(staged, opts) return B.Auth.WithDropTarget { id = id(opts.id or staged), child = child_from_opts(opts) } end),
    slot = wrapper(function(staged, opts) return B.Auth.WithDropSlot { id = id(opts.id or staged), child = child_from_opts(opts) } end),
}
M.focus = { scope = wrapper(function(staged, opts) return B.Auth.FocusScope { id = id(opts.id or staged), policy = focus_policy(opts), child = child_from_opts(opts) } end) }
M.state = wrapper(function(_, opts) return B.Auth.WithState { state = tw.state(opts), child = child_from_opts(opts) } end)
M.layer = wrapper(function(staged, opts) return B.Auth.Layer { id = id(opts.id or staged), kind = layer_kind(opts.kind or opts.variant), order = opts.order or 0, child = child_from_opts(opts) } end)
M.overlay = wrapper(function(staged, opts) return B.Auth.Overlay { id = id(opts.id or staged), anchor_id = id(opts.anchor or opts.anchor_id), placement = opts.placement or placement(opts.variant), modal = not not opts.modal, child = child_from_opts(opts) } end)
M.modal = wrapper(function(staged, opts) return B.Auth.Modal { id = id(opts.id or staged), child = child_from_opts(opts) } end)

M.compose = {
    raw = make_compose("raw"),
    fragment = make_compose("fragment"),
    panel = make_compose("panel"),
    scroll_panel = make_compose("scroll_panel"),
    hsplit = make_compose("hsplit"),
    vsplit = make_compose("vsplit"),
    workbench = make_compose("workbench"),
}

M.place = {
    auto = Interact.PlaceAuto,
    above = Interact.PlaceAbove,
    below = Interact.PlaceBelow,
    left = Interact.PlaceLeft,
    right = Interact.PlaceRight,
    center = Interact.PlaceCenter,
}

M.T = T
M.B = B

return M
