local pvm = require("pvm")
local ui_asdl = require("mlui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Paint = T.Paint
local Auth = T.Auth
local Compose = T.Compose
local Interact = T.Interact

local M = {}

M.K = {
    AUTH_EMPTY = 1,
    AUTH_FRAGMENT = 2,
    AUTH_BOX = 3,
    AUTH_TEXT = 4,
    AUTH_TEXT_REF = 5,
    AUTH_PAINT = 6,
    AUTH_SCROLL = 7,
    AUTH_WITH_INPUT = 8,
    AUTH_WITH_DRAG_SOURCE = 9,
    AUTH_WITH_DROP_TARGET = 10,
    AUTH_WITH_DROP_SLOT = 11,
    AUTH_WITH_STATE = 12,
    AUTH_FOCUS_SCOPE = 13,
    AUTH_LAYER = 14,
    AUTH_OVERLAY = 15,
    AUTH_MODAL = 16,

    COMPOSE_PANEL = 1,
    COMPOSE_SCROLL_PANEL = 2,
    COMPOSE_HSPLIT = 3,
    COMPOSE_VSPLIT = 4,
    COMPOSE_WORKBENCH = 5,
    COMPOSE_RAW_AUTH = 6,

    PAINT_LINE = 1,
    PAINT_POLYLINE = 2,
    PAINT_POLYGON = 3,
    PAINT_CIRCLE = 4,
    PAINT_ARC = 5,
    PAINT_BEZIER = 6,
    PAINT_MESH = 7,
    PAINT_IMAGE = 8,
}

local K = M.K

local ATOM = {
    DISPLAY = 1, AXIS = 2, WRAP = 3, JUSTIFY = 4, ITEMS = 5, SELF = 6,
    GAP = 10, GAP_X = 11, GAP_Y = 12,
    PAD = 20, PAD_X = 21, PAD_Y = 22, PAD_TOP = 23, PAD_RIGHT = 24, PAD_BOTTOM = 25, PAD_LEFT = 26,
    MARGIN = 30, MARGIN_X = 31, MARGIN_Y = 32, MARGIN_TOP = 33, MARGIN_RIGHT = 34, MARGIN_BOTTOM = 35, MARGIN_LEFT = 36,
    WIDTH = 40, HEIGHT = 41, MIN_WIDTH = 42, MAX_WIDTH = 43, MIN_HEIGHT = 44, MAX_HEIGHT = 45,
    GROW = 50, SHRINK = 51, BASIS = 52,
    FG = 60, BG = 61, BORDER_COLOR = 62, BORDER_WIDTH = 63, ROUNDED = 64, OPACITY = 65,
    TEXT_SIZE = 70, TEXT_WEIGHT = 71, TEXT_ALIGN = 72, LEADING = 73, TRACKING = 74,
    OVERFLOW_X = 80, OVERFLOW_Y = 81, CURSOR = 90,
    COLS = 100, ROWS = 101, COL_GAP = 102, ROW_GAP = 103,
    COL_START = 110, COL_SPAN = 111, ROW_START = 112, ROW_SPAN = 113,
}

local function classof(v)
    return pvm.classof(v)
end

local function id_value(v, state)
    local cls = classof(v)
    if v == nil or v == false or v == Core.NoId then return 0 end
    if cls == Core.IdValue then
        local n = state.ids[v.value]
        if not n then
            n = #state.id_values + 1
            state.ids[v.value] = n
            state.id_values[n] = v.value
        end
        return n
    end
    error("expected Core.Id", 3)
end

local function role_value(v)
    if v == Interact.HitTarget then return 1 end
    if v == Interact.FocusTarget then return 2 end
    if v == Interact.ActivateTarget then return 3 end
    if v == Interact.EditTarget then return 4 end
    return 0
end

local function scroll_axis_value(v)
    if v == Style.ScrollX then return 1 end
    if v == Style.ScrollBoth then return 3 end
    return 2
end

local function focus_policy_value(v)
    if v == Interact.FocusClamp then return 1 end
    if v == Interact.FocusTrap then return 2 end
    if v == Interact.FocusPassthrough then return 3 end
    return 0
end

local function layer_kind_value(v)
    if v == Interact.LayerOverlay then return 1 end
    if v == Interact.LayerPopup then return 2 end
    if v == Interact.LayerTooltip then return 3 end
    if v == Interact.LayerModal then return 4 end
    if v == Interact.LayerDragPreview then return 5 end
    return 0
end

local function placement_value(v)
    if v == Interact.PlaceAbove then return 1 end
    if v == Interact.PlaceBelow then return 2 end
    if v == Interact.PlaceLeft then return 3 end
    if v == Interact.PlaceRight then return 4 end
    if v == Interact.PlaceCenter then return 5 end
    return 0
end

local space_values = {
    [Style.S0] = 0, [Style.S0_5] = 2, [Style.S1] = 4, [Style.S1_5] = 6,
    [Style.S2] = 8, [Style.S2_5] = 10, [Style.S3] = 12, [Style.S3_5] = 14,
    [Style.S4] = 16, [Style.S5] = 20, [Style.S6] = 24, [Style.S7] = 28,
    [Style.S8] = 32, [Style.S9] = 36, [Style.S10] = 40, [Style.S11] = 44,
    [Style.S12] = 48, [Style.S14] = 56, [Style.S16] = 64, [Style.S20] = 80,
    [Style.S24] = 96, [Style.S28] = 112, [Style.S32] = 128, [Style.S36] = 144,
    [Style.S40] = 160, [Style.S44] = 176, [Style.S48] = 192, [Style.S52] = 208,
    [Style.S56] = 224, [Style.S60] = 240, [Style.S64] = 256, [Style.S72] = 288,
    [Style.S80] = 320, [Style.S96] = 384, [Style.SPx] = 1,
}

local enum_values = {}
local function enum(n, ...)
    local values = { ... }
    for i = 1, #values do
        enum_values[values[i]] = i - 1
        enum_values[classof(values[i])] = i - 1
    end
end
enum("display", Style.DisplayFlow, Style.DisplayFlex, Style.DisplayGrid)
enum("axis", Style.AxisRow, Style.AxisCol)
enum("wrap", Style.WrapOff, Style.WrapOn)
enum("justify", Style.JustifyStart, Style.JustifyCenter, Style.JustifyEnd, Style.JustifyBetween, Style.JustifyAround, Style.JustifyEvenly)
enum("items", Style.ItemsStart, Style.ItemsCenter, Style.ItemsEnd, Style.ItemsStretch, Style.ItemsBaseline)
enum("self", Style.SelfAuto, Style.SelfStart, Style.SelfCenter, Style.SelfEnd, Style.SelfStretch, Style.SelfBaseline)
enum("text_align", Style.TLeft, Style.TCenter, Style.TRight, Style.TJustify)
enum("overflow", Style.OverflowVisible, Style.OverflowHidden, Style.OverflowScroll, Style.OverflowAuto)
enum("cursor", Style.CursorDefault, Style.CursorPointer, Style.CursorText, Style.CursorMove, Style.CursorGrab, Style.CursorGrabbing, Style.CursorNotAllowed)

local font_sizes = {
    [Style.TxtXs] = 12, [Style.TxtSm] = 14, [Style.TxtBase] = 16,
    [Style.TxtLg] = 18, [Style.TxtXl] = 20, [Style.Txt2xl] = 24,
    [Style.Txt3xl] = 30, [Style.Txt4xl] = 36, [Style.Txt5xl] = 48,
    [Style.Txt6xl] = 60,
}
local font_weights = {
    [Style.Thin] = 100, [Style.ExtraLight] = 200, [Style.Light] = 300,
    [Style.Normal] = 400, [Style.Medium] = 500, [Style.Semibold] = 600,
    [Style.Bold] = 700, [Style.ExtraBold] = 800, [Style.WeightBlack] = 900,
}
local leading_values = {
    [Style.LeadingNone] = 1.0, [Style.LeadingTight] = 1.25, [Style.LeadingSnug] = 1.375,
    [Style.LeadingNormal] = 1.5, [Style.LeadingRelaxed] = 1.625, [Style.LeadingLoose] = 2.0,
}
local tracking_values = {
    [Style.TrackingTighter] = -0.8, [Style.TrackingTight] = -0.4, [Style.TrackingNormal] = 0,
    [Style.TrackingWide] = 0.4, [Style.TrackingWider] = 0.8, [Style.TrackingWidest] = 1.6,
}
local radius_values = {
    [Style.R0] = 0, [Style.RSm] = 2, [Style.RBase] = 4, [Style.RMd] = 6,
    [Style.RLg] = 8, [Style.RXl] = 12, [Style.R2xl] = 16, [Style.R3xl] = 24,
    [Style.RFull] = 9999,
}
local border_values = { [Style.BW0] = 0, [Style.BW1] = 1, [Style.BW2] = 2, [Style.BW4] = 4, [Style.BW8] = 8 }
local opacity_values = {
    [Style.O0] = 0, [Style.O5] = 5, [Style.O10] = 10, [Style.O20] = 20,
    [Style.O25] = 25, [Style.O30] = 30, [Style.O40] = 40, [Style.O50] = 50,
    [Style.O60] = 60, [Style.O70] = 70, [Style.O75] = 75, [Style.O80] = 80,
    [Style.O90] = 90, [Style.O95] = 95, [Style.O100] = 100,
}

local palette = {
    WhiteRef = 0xffffffff, BlackRef = 0xff000000, TransparentRef = 0x00000000,
    Slate = 0xff64748b, Gray = 0xff6b7280, Zinc = 0xff71717a, Neutral = 0xff737373, Stone = 0xff78716c,
    Red = 0xffef4444, Orange = 0xfff97316, Amber = 0xfff59e0b, Yellow = 0xffeab308,
    Lime = 0xff84cc16, Green = 0xff22c55e, Emerald = 0xff10b981, Teal = 0xff14b8a6,
    Cyan = 0xff06b6d4, Sky = 0xff0ea5e9, Blue = 0xff3b82f6, Indigo = 0xff6366f1,
    Violet = 0xff8b5cf6, Purple = 0xffa855f7, Fuchsia = 0xffd946ef, Pink = 0xffec4899, Rose = 0xfff43f5e,
}

local shade_factor = {
    [Style.S50] = 1.55, [Style.S100] = 1.45, [Style.S200] = 1.30, [Style.S300] = 1.15,
    [Style.S400] = 1.0, [Style.S500] = 0.9, [Style.S600] = 0.78, [Style.S700] = 0.62,
    [Style.S800] = 0.48, [Style.S900] = 0.34, [Style.S950] = 0.24,
}

local function tint(rgba, factor)
    local r = math.min(255, math.floor(((rgba / 0x10000) % 0x100) * factor))
    local g = math.min(255, math.floor(((rgba / 0x100) % 0x100) * factor))
    local b = math.min(255, math.floor((rgba % 0x100) * factor))
    return 0xff000000 + r * 0x10000 + g * 0x100 + b
end

local function color_value(v)
    local cls = classof(v)
    if v == Style.WhiteRef then return palette.WhiteRef end
    if v == Style.BlackRef then return palette.BlackRef end
    if v == Style.TransparentRef then return palette.TransparentRef end
    if cls == Style.Palette then
        local scale = v.scale
        local shade = v.shade
        local name
        for k, val in pairs(Style.ColorScale.members) do
            if val == scale or val == classof(scale) then name = k end
        end
        return tint(palette[name] or palette.Slate, shade_factor[shade] or shade_factor[classof(shade)] or 1)
    end
    return 0
end

local function length_value(v)
    local cls = classof(v)
    if v == Style.LHug then return 1, 0 end
    if v == Style.LFill then return 2, 0 end
    if cls == Style.LFixed then return 3, v.px end
    if cls == Style.LFrac then return 4, enum_values[classof(v.value)] or 1 end
    return 0, 0
end

local function basis_value(v)
    local cls = classof(v)
    if v == Style.BHug then return 1, 0 end
    if cls == Style.BFixed then return 3, v.px end
    if cls == Style.BFrac then return 4, enum_values[classof(v.value)] or 1 end
    return 0, 0
end

local function cond_value(cond)
    return {
        bp = enum_values[classof(cond.bp)] or 0,
        scheme = enum_values[classof(cond.scheme)] or 0,
        motion = enum_values[classof(cond.motion)] or 0,
        hovered = enum_values[classof(cond.state.hovered)] or 0,
        focused = enum_values[classof(cond.state.focused)] or 0,
        active = enum_values[classof(cond.state.active)] or 0,
        selected = enum_values[classof(cond.state.selected)] or 0,
        disabled = enum_values[classof(cond.state.disabled)] or 0,
    }
end

enum("bp", Style.AnyBp, Style.SmUp, Style.MdUp, Style.LgUp, Style.XlUp, Style.X2lUp)
enum("scheme", Style.AnyScheme, Style.LightOnly, Style.DarkOnly)
enum("motion", Style.AnyMotion, Style.MotionSafeOnly, Style.MotionReduceOnly)
enum("flag", Style.ReqAny, Style.ReqOn, Style.ReqOff)

local function track_value(v)
    local cls = classof(v)
    if cls == Style.TFr then return { kind = 1, a = v.fr, b = 0 } end
    if cls == Style.TFixed then return { kind = 2, a = v.px, b = 0 } end
    if cls == Style.TMinMax then return { kind = 3, a = v.min_px, b = v.max_px } end
    return { kind = 0, a = 0, b = 0 }
end

local function atom_value(atom, state)
    local cls = classof(atom)
    local function mapv(map, v, default)
        local out = map[v]
        if out ~= nil then return out end
        out = map[classof(v)]
        if out ~= nil then return out end
        return default
    end
    local function one(kind, a, b, color)
        return { kind = kind, a = a or 0, b = b or 0, color = color or 0, track_first = 0, track_count = 0 }
    end
    local function len(kind, value)
        local a, b = length_value(value)
        return one(kind, a, b)
    end
    local function basis(kind, value)
        local a, b = basis_value(value)
        return one(kind, a, b)
    end
    local function tracks(kind, values)
        local first = #state.style_tracks + 1
        for i = 1, #values do state.style_tracks[#state.style_tracks + 1] = track_value(values[i]) end
        local row = one(kind)
        row.track_first = first
        row.track_count = #values
        return row
    end

    if cls == Style.ADisplay then return one(ATOM.DISPLAY, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AAxis then return one(ATOM.AXIS, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AWrap then return one(ATOM.WRAP, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AJustify then return one(ATOM.JUSTIFY, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AItems then return one(ATOM.ITEMS, enum_values[classof(atom.value)] or 0) end
    if cls == Style.ASelf then return one(ATOM.SELF, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AGap then return one(ATOM.GAP, mapv(space_values, atom.value, 0)) end
    if cls == Style.AGapX then return one(ATOM.GAP_X, mapv(space_values, atom.value, 0)) end
    if cls == Style.AGapY then return one(ATOM.GAP_Y, mapv(space_values, atom.value, 0)) end
    if cls == Style.APad then return one(ATOM.PAD, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadX then return one(ATOM.PAD_X, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadY then return one(ATOM.PAD_Y, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadTop then return one(ATOM.PAD_TOP, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadRight then return one(ATOM.PAD_RIGHT, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadBottom then return one(ATOM.PAD_BOTTOM, mapv(space_values, atom.value, 0)) end
    if cls == Style.APadLeft then return one(ATOM.PAD_LEFT, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMargin then return one(ATOM.MARGIN, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginX then return one(ATOM.MARGIN_X, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginY then return one(ATOM.MARGIN_Y, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginTop then return one(ATOM.MARGIN_TOP, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginRight then return one(ATOM.MARGIN_RIGHT, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginBottom then return one(ATOM.MARGIN_BOTTOM, mapv(space_values, atom.value, 0)) end
    if cls == Style.AMarginLeft then return one(ATOM.MARGIN_LEFT, mapv(space_values, atom.value, 0)) end
    if cls == Style.AWidth then return len(ATOM.WIDTH, atom.value) end
    if cls == Style.AHeight then return len(ATOM.HEIGHT, atom.value) end
    if cls == Style.AMinWidth then return len(ATOM.MIN_WIDTH, atom.value) end
    if cls == Style.AMaxWidth then return len(ATOM.MAX_WIDTH, atom.value) end
    if cls == Style.AMinHeight then return len(ATOM.MIN_HEIGHT, atom.value) end
    if cls == Style.AMaxHeight then return len(ATOM.MAX_HEIGHT, atom.value) end
    if cls == Style.AGrow then return one(ATOM.GROW, atom.value) end
    if cls == Style.AShrink then return one(ATOM.SHRINK, atom.value) end
    if cls == Style.ABasis then return basis(ATOM.BASIS, atom.value) end
    if cls == Style.AFg then return one(ATOM.FG, 0, 0, color_value(atom.value)) end
    if cls == Style.ABg then return one(ATOM.BG, 0, 0, color_value(atom.value)) end
    if cls == Style.ABorderColor then return one(ATOM.BORDER_COLOR, 0, 0, color_value(atom.value)) end
    if cls == Style.ABorderWidth then return one(ATOM.BORDER_WIDTH, mapv(border_values, atom.value, 0)) end
    if cls == Style.ARounded then return one(ATOM.ROUNDED, mapv(radius_values, atom.value, 0)) end
    if cls == Style.AOpacity then return one(ATOM.OPACITY, mapv(opacity_values, atom.value, 100)) end
    if cls == Style.ATextSize then return one(ATOM.TEXT_SIZE, mapv(font_sizes, atom.value, 16)) end
    if cls == Style.ATextWeight then return one(ATOM.TEXT_WEIGHT, mapv(font_weights, atom.value, 400)) end
    if cls == Style.ATextAlign then return one(ATOM.TEXT_ALIGN, enum_values[classof(atom.value)] or 0) end
    if cls == Style.ALeading then return one(ATOM.LEADING, mapv(leading_values, atom.value, 1.5)) end
    if cls == Style.ATracking then return one(ATOM.TRACKING, mapv(tracking_values, atom.value, 0)) end
    if cls == Style.AOverflowX then return one(ATOM.OVERFLOW_X, enum_values[classof(atom.value)] or 0) end
    if cls == Style.AOverflowY then return one(ATOM.OVERFLOW_Y, enum_values[classof(atom.value)] or 0) end
    if cls == Style.ACursor then return one(ATOM.CURSOR, enum_values[classof(atom.value)] or 0) end
    if cls == Style.ACols then return tracks(ATOM.COLS, atom.tracks) end
    if cls == Style.ARows then return tracks(ATOM.ROWS, atom.tracks) end
    if cls == Style.AColGap then return one(ATOM.COL_GAP, mapv(space_values, atom.value, 0)) end
    if cls == Style.ARowGap then return one(ATOM.ROW_GAP, mapv(space_values, atom.value, 0)) end
    if cls == Style.AColStart then return one(ATOM.COL_START, atom.value) end
    if cls == Style.AColSpan then return one(ATOM.COL_SPAN, atom.value) end
    if cls == Style.ARowStart then return one(ATOM.ROW_START, atom.value) end
    if cls == Style.ARowSpan then return one(ATOM.ROW_SPAN, atom.value) end
    error("unsupported style atom: " .. tostring(cls), 3)
end

local function append_styles(styles, state)
    local first = #state.styles + 1
    if styles then
        for i = 1, #styles.items do
            local tok = styles.items[i]
            state.styles[#state.styles + 1] = {
                cond = cond_value(tok.cond),
                atom = atom_value(tok.atom, state),
            }
        end
    end
    return first, #state.styles - first + 1
end

local function state_value(v)
    if not v then return { hovered = false, focused = false, active = false, selected = false, disabled = false } end
    return { hovered = v.hovered, focused = v.focused, active = v.active, selected = v.selected, disabled = v.disabled }
end

local function empty_row(kind)
    return {
        kind = kind,
        id = 0,
        role = 0,
        scroll_axis = 0,
        focus_policy = 0,
        layer_kind = 0,
        overlay_placement = 0,
        anchor_id = 0,
        order = 0,
        modal = false,
        first_child = 0,
        n_child = 0,
        token_first = 0,
        token_count = 0,
        content = 0,
        paint_first = 0,
        paint_count = 0,
        state = state_value(nil),
    }
end

local function content_ref(value, state)
    local key = tostring(value or "")
    local n = state.contents[key]
    if not n then
        n = #state.content_values + 1
        state.contents[key] = n
        state.content_values[n] = key
    end
    return n
end

local function point_range(points, state)
    local first = #state.paint_points + 1
    for i = 1, #points do state.paint_points[#state.paint_points + 1] = points[i] end
    return first, #points
end

local function append_paint(programs, state)
    local first = #state.paint + 1
    for i = 1, #programs.items do
        local p = programs.items[i]
        local cls = classof(p)
        local row = { kind = 0, a = 0, b = 0, c = 0, d = 0, stroke = nil, fill = nil, first = 0, count = 0, image = 0 }
        if cls == Paint.Line then
            row.kind = K.PAINT_LINE; row.a = p.x1; row.b = p.y1; row.c = p.x2; row.d = p.y2; row.stroke = p.stroke
        elseif cls == Paint.Polyline then
            row.kind = K.PAINT_POLYLINE; row.first, row.count = point_range(p.xy, state); row.stroke = p.stroke
        elseif cls == Paint.Polygon then
            row.kind = K.PAINT_POLYGON; row.first, row.count = point_range(p.xy, state); row.fill = p.fill; row.stroke = p.stroke
        elseif cls == Paint.Circle then
            row.kind = K.PAINT_CIRCLE; row.a = p.cx; row.b = p.cy; row.c = p.r; row.fill = p.fill; row.stroke = p.stroke
        elseif cls == Paint.Arc then
            row.kind = K.PAINT_ARC; row.a = p.cx; row.b = p.cy; row.c = p.r; row.d = p.a1; row.e = p.a2; row.segments = p.segments; row.stroke = p.stroke
        elseif cls == Paint.Bezier then
            row.kind = K.PAINT_BEZIER; row.first, row.count = point_range(p.xy, state); row.segments = p.segments; row.stroke = p.stroke
        elseif cls == Paint.Mesh then
            row.kind = K.PAINT_MESH; row.mode = classof(p.mode); row.vertices = p.vertices; row.image = id_value(p.image_id, state); row.tint = p.tint_rgba8; row.opacity = p.opacity
        elseif cls == Paint.Image then
            row.kind = K.PAINT_IMAGE; row.image = id_value(p.image_id, state); row.a = p.src_x; row.b = p.src_y; row.c = p.src_w; row.d = p.src_h; row.tint = p.tint_rgba8; row.opacity = p.opacity
        else
            error("unsupported paint program", 3)
        end
        state.paint[#state.paint + 1] = row
    end
    return first, #state.paint - first + 1
end

local encode_auth

local function child_range(children, state)
    local first = #state.children + 1
    for i = 1, #children do state.children[#state.children + 1] = encode_auth(children[i], state) end
    return first, #children
end

function encode_auth(node, state)
    local cls = classof(node)
    local row
    if cls == Auth.Empty then
        row = empty_row(K.AUTH_EMPTY)
    elseif cls == Auth.Fragment then
        row = empty_row(K.AUTH_FRAGMENT)
        row.first_child, row.n_child = child_range(node.children, state)
    elseif cls == Auth.Box then
        row = empty_row(K.AUTH_BOX)
        row.id = id_value(node.id, state)
        row.token_first, row.token_count = append_styles(node.styles, state)
        row.first_child, row.n_child = child_range(node.children, state)
    elseif cls == Auth.Text then
        row = empty_row(K.AUTH_TEXT)
        row.id = id_value(node.id, state)
        row.token_first, row.token_count = append_styles(node.styles, state)
        row.content = content_ref(node.content, state)
    elseif cls == Auth.TextRef then
        row = empty_row(K.AUTH_TEXT_REF)
        row.id = id_value(node.id, state)
        row.token_first, row.token_count = append_styles(node.styles, state)
        row.content = id_value(node.content_id, state)
    elseif cls == Auth.Paint then
        row = empty_row(K.AUTH_PAINT)
        row.id = id_value(node.id, state)
        row.token_first, row.token_count = append_styles(node.styles, state)
        row.paint_first, row.paint_count = append_paint(node.paint, state)
    elseif cls == Auth.Scroll then
        row = empty_row(K.AUTH_SCROLL)
        row.id = id_value(node.id, state)
        row.scroll_axis = scroll_axis_value(node.axis)
        row.token_first, row.token_count = append_styles(node.styles, state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.WithInput then
        row = empty_row(K.AUTH_WITH_INPUT)
        row.id = id_value(node.id, state)
        row.role = role_value(node.role)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.WithDragSource then
        row = empty_row(K.AUTH_WITH_DRAG_SOURCE)
        row.id = id_value(node.id, state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.WithDropTarget then
        row = empty_row(K.AUTH_WITH_DROP_TARGET)
        row.id = id_value(node.id, state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.WithDropSlot then
        row = empty_row(K.AUTH_WITH_DROP_SLOT)
        row.id = id_value(node.id, state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.WithState then
        row = empty_row(K.AUTH_WITH_STATE)
        row.state = state_value(node.state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.FocusScope then
        row = empty_row(K.AUTH_FOCUS_SCOPE)
        row.id = id_value(node.id, state)
        row.focus_policy = focus_policy_value(node.policy)
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.Layer then
        row = empty_row(K.AUTH_LAYER)
        row.id = id_value(node.id, state)
        row.layer_kind = layer_kind_value(node.kind)
        row.order = node.order
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.Overlay then
        row = empty_row(K.AUTH_OVERLAY)
        row.id = id_value(node.id, state)
        row.anchor_id = id_value(node.anchor_id, state)
        row.overlay_placement = placement_value(node.placement)
        row.modal = node.modal
        row.first_child, row.n_child = child_range({ node.child }, state)
    elseif cls == Auth.Modal then
        row = empty_row(K.AUTH_MODAL)
        row.id = id_value(node.id, state)
        row.first_child, row.n_child = child_range({ node.child }, state)
    else
        error("expected Auth.Node", 3)
    end
    state.auth[#state.auth + 1] = row
    return #state.auth
end

local function new_state(epoch)
    return {
        epoch = epoch or 0,
        ids = {},
        id_values = {},
        contents = {},
        content_values = {},
        auth = {},
        children = {},
        styles = {},
        style_tracks = {},
        paint = {},
        paint_points = {},
        compose = {},
        compose_children = {},
    }
end

function M.auth(root, opts)
    local state = new_state(opts and opts.epoch)
    local root_index = encode_auth(root, state)
    return {
        header = {
            magic = "MLUI",
            abi_version = 1,
            root_kind = "auth",
            root_index = root_index,
            epoch = state.epoch,
        },
        auth = {
            nodes = state.auth,
            children = state.children,
            styles = {
                tokens = state.styles,
                tracks = state.style_tracks,
            },
        },
        paint = {
            programs = state.paint,
            points = state.paint_points,
        },
        resources = {
            ids = state.id_values,
            contents = state.content_values,
        },
    }
end

M.encode = M.auth

return M
