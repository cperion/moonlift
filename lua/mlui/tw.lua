local A = require("mlui.asdl")
local T = A.T
local B = A.B
local S = T.Style
local BS = B.Style

local M = {}

local DEFAULT_STATE = BS.StateCond {
    hovered = S.ReqAny,
    focused = S.ReqAny,
    active = S.ReqAny,
    selected = S.ReqAny,
    disabled = S.ReqAny,
}
local DEFAULT_COND = BS.Cond {
    bp = S.AnyBp,
    scheme = S.AnyScheme,
    motion = S.AnyMotion,
    state = DEFAULT_STATE,
}

local function classof(v)
    return require("pvm").classof(v)
end

local function token(atom, cond)
    return BS.Token { cond = cond or DEFAULT_COND, atom = atom }
end

local function group(items)
    local out = {}
    for i = 1, #items do
        local v = items[i]
        if v ~= nil and v ~= false then
            local cls = classof(v)
            if cls == S.Token then
                out[#out + 1] = v
            elseif cls == S.Group or cls == S.TokenList then
                for j = 1, #v.items do out[#out + 1] = v.items[j] end
            elseif type(v) == "table" and not cls then
                local g = group(v)
                for j = 1, #g.items do out[#out + 1] = g.items[j] end
            else
                error("expected style token or group", 3)
            end
        end
    end
    return BS.Group { items = out }
end

local function list(items)
    return BS.TokenList { items = group(items).items }
end

local space = {
    [0] = S.S0, ["0"] = S.S0,
    [0.5] = S.S0_5, ["0.5"] = S.S0_5, ["0_5"] = S.S0_5,
    [1] = S.S1, ["1"] = S.S1, [1.5] = S.S1_5, ["1.5"] = S.S1_5, ["1_5"] = S.S1_5,
    [2] = S.S2, ["2"] = S.S2, [2.5] = S.S2_5, ["2.5"] = S.S2_5, ["2_5"] = S.S2_5,
    [3] = S.S3, ["3"] = S.S3, [3.5] = S.S3_5, ["3.5"] = S.S3_5, ["3_5"] = S.S3_5,
    [4] = S.S4, ["4"] = S.S4, [5] = S.S5, ["5"] = S.S5, [6] = S.S6, ["6"] = S.S6,
    [7] = S.S7, ["7"] = S.S7, [8] = S.S8, ["8"] = S.S8, [9] = S.S9, ["9"] = S.S9,
    [10] = S.S10, ["10"] = S.S10, [11] = S.S11, ["11"] = S.S11, [12] = S.S12, ["12"] = S.S12,
    [14] = S.S14, ["14"] = S.S14, [16] = S.S16, ["16"] = S.S16, [20] = S.S20, ["20"] = S.S20,
    [24] = S.S24, ["24"] = S.S24, [28] = S.S28, ["28"] = S.S28, [32] = S.S32, ["32"] = S.S32,
    [36] = S.S36, ["36"] = S.S36, [40] = S.S40, ["40"] = S.S40, [44] = S.S44, ["44"] = S.S44,
    [48] = S.S48, ["48"] = S.S48, [52] = S.S52, ["52"] = S.S52, [56] = S.S56, ["56"] = S.S56,
    [60] = S.S60, ["60"] = S.S60, [64] = S.S64, ["64"] = S.S64, [72] = S.S72, ["72"] = S.S72,
    [80] = S.S80, ["80"] = S.S80, [96] = S.S96, ["96"] = S.S96, px = S.SPx,
}

local frac = {
    ["1/2"] = S.F1_2, ["1/3"] = S.F1_3, ["2/3"] = S.F2_3,
    ["1/4"] = S.F1_4, ["2/4"] = S.F2_4, ["3/4"] = S.F3_4,
    ["1/5"] = S.F1_5, ["2/5"] = S.F2_5, ["3/5"] = S.F3_5, ["4/5"] = S.F4_5,
    ["1/6"] = S.F1_6, ["2/6"] = S.F2_6, ["3/6"] = S.F3_6, ["4/6"] = S.F4_6, ["5/6"] = S.F5_6,
    full = S.FFull,
}

local shade = { [50] = S.S50, [100] = S.S100, [200] = S.S200, [300] = S.S300, [400] = S.S400, [500] = S.S500, [600] = S.S600, [700] = S.S700, [800] = S.S800, [900] = S.S900, [950] = S.S950 }
local scale = {
    slate = S.Slate, gray = S.Gray, zinc = S.Zinc, neutral = S.Neutral, stone = S.Stone,
    red = S.Red, orange = S.Orange, amber = S.Amber, yellow = S.Yellow, lime = S.Lime,
    green = S.Green, emerald = S.Emerald, teal = S.Teal, cyan = S.Cyan, sky = S.Sky,
    blue = S.Blue, indigo = S.Indigo, violet = S.Violet, purple = S.Purple,
    fuchsia = S.Fuchsia, pink = S.Pink, rose = S.Rose,
}

local function as_space(v)
    local out = space[v]
    if out then return out end
    error("unknown spacing token: " .. tostring(v), 3)
end

local function as_frac(v)
    local out = frac[v]
    if out then return out end
    error("unknown fraction token: " .. tostring(v), 3)
end

local function indexed(fn)
    return setmetatable({}, {
        __index = function(_, key) return fn(key) end,
        __call = function(_, value) return fn(value) end,
    })
end

local function namespace(values)
    return setmetatable(values, {
        __index = function(_, key) error("unknown mlui tw token: " .. tostring(key), 2) end,
    })
end

local function length_ctor(kind, fixed)
    return function(v)
        return token(kind(BS.LFixed { px = v }))
    end
end

local function length_namespace(kind)
    local function fixed(v) return token(kind { value = BS.LFixed { px = v } }) end
    return setmetatable({
        auto = token(kind { value = S.LAuto }),
        hug = token(kind { value = S.LHug }),
        fill = token(kind { value = S.LFill }),
        full = token(kind { value = BS.LFrac { value = S.FFull } }),
        frac = indexed(function(v) return token(kind { value = BS.LFrac { value = as_frac(v) } }) end),
    }, {
        __index = function(_, key) return fixed(key) end,
        __call = function(_, value) return fixed(value) end,
    })
end

local function space_token(kind)
    return indexed(function(v) return token(kind { value = as_space(v) }) end)
end

M.group = group
M.list = list
M.token = token

M.flex = token(BS.ADisplay { value = S.DisplayFlex })
M.grid = token(BS.ADisplay { value = S.DisplayGrid })
M.flow = token(BS.ADisplay { value = S.DisplayFlow })
M.row = token(BS.AAxis { value = S.AxisRow })
M.col = token(BS.AAxis { value = S.AxisCol })
M.wrap = token(BS.AWrap { value = S.WrapOn })
M.nowrap = token(BS.AWrap { value = S.WrapOff })

M.p = space_token(BS.APad)
M.px = space_token(BS.APadX)
M.py = space_token(BS.APadY)
M.pt = space_token(BS.APadTop)
M.pr = space_token(BS.APadRight)
M.pb = space_token(BS.APadBottom)
M.pl = space_token(BS.APadLeft)
M.m = space_token(BS.AMargin)
M.mx = space_token(BS.AMarginX)
M.my = space_token(BS.AMarginY)
M.mt = space_token(BS.AMarginTop)
M.mr = space_token(BS.AMarginRight)
M.mb = space_token(BS.AMarginBottom)
M.ml = space_token(BS.AMarginLeft)
M.gap = setmetatable({ x = space_token(BS.AGapX), y = space_token(BS.AGapY) }, {
    __index = function(_, key) return token(BS.AGap { value = as_space(key) }) end,
    __call = function(_, value) return token(BS.AGap { value = as_space(value) }) end,
})
M.col_gap = space_token(BS.AColGap)
M.row_gap = space_token(BS.ARowGap)

M.w = length_namespace(BS.AWidth)
M.h = length_namespace(BS.AHeight)
M.min_w = length_namespace(BS.AMinWidth)
M.max_w = length_namespace(BS.AMaxWidth)
M.min_h = length_namespace(BS.AMinHeight)
M.max_h = length_namespace(BS.AMaxHeight)
M.grow = indexed(function(v) return token(BS.AGrow { value = v }) end)
M.shrink = indexed(function(v) return token(BS.AShrink { value = v }) end)
M.basis = setmetatable({
    auto = token(BS.ABasis { value = S.BAuto }),
    hug = token(BS.ABasis { value = S.BHug }),
    full = token(BS.ABasis { value = BS.BFrac { value = S.FFull } }),
    frac = indexed(function(v) return token(BS.ABasis { value = BS.BFrac { value = as_frac(v) } }) end),
}, {
    __index = function(_, key) return token(BS.ABasis { value = BS.BFixed { px = key } }) end,
    __call = function(_, value) return token(BS.ABasis { value = BS.BFixed { px = value } }) end,
})

M.justify = namespace({
    start = token(BS.AJustify { value = S.JustifyStart }),
    center = token(BS.AJustify { value = S.JustifyCenter }),
    ["end"] = token(BS.AJustify { value = S.JustifyEnd }),
    between = token(BS.AJustify { value = S.JustifyBetween }),
    around = token(BS.AJustify { value = S.JustifyAround }),
    evenly = token(BS.AJustify { value = S.JustifyEvenly }),
})
M.items = namespace({
    start = token(BS.AItems { value = S.ItemsStart }),
    center = token(BS.AItems { value = S.ItemsCenter }),
    ["end"] = token(BS.AItems { value = S.ItemsEnd }),
    stretch = token(BS.AItems { value = S.ItemsStretch }),
    baseline = token(BS.AItems { value = S.ItemsBaseline }),
})
M.self = namespace({
    auto = token(BS.ASelf { value = S.SelfAuto }),
    start = token(BS.ASelf { value = S.SelfStart }),
    center = token(BS.ASelf { value = S.SelfCenter }),
    ["end"] = token(BS.ASelf { value = S.SelfEnd }),
    stretch = token(BS.ASelf { value = S.SelfStretch }),
    baseline = token(BS.ASelf { value = S.SelfBaseline }),
})

local radius = { none = S.R0, sm = S.RSm, base = S.RBase, md = S.RMd, lg = S.RLg, xl = S.RXl, ["2xl"] = S.R2xl, ["3xl"] = S.R3xl, full = S.RFull }
M.rounded = setmetatable({}, { __index = function(_, key) return token(BS.ARounded { value = radius[key] or S.RBase }) end })
local borders = { [0] = S.BW0, [1] = S.BW1, [2] = S.BW2, [4] = S.BW4, [8] = S.BW8 }
M.border = indexed(function(v) return token(BS.ABorderWidth { value = borders[v] or S.BW1 }) end)
local opacities = { [0] = S.O0, [5] = S.O5, [10] = S.O10, [20] = S.O20, [25] = S.O25, [30] = S.O30, [40] = S.O40, [50] = S.O50, [60] = S.O60, [70] = S.O70, [75] = S.O75, [80] = S.O80, [90] = S.O90, [95] = S.O95, [100] = S.O100 }
M.opacity = indexed(function(v) return token(BS.AOpacity { value = opacities[v] or S.O100 }) end)

local function color_ref(name, sh)
    if name == "white" then return S.WhiteRef end
    if name == "black" then return S.BlackRef end
    if name == "transparent" then return S.TransparentRef end
    return BS.Palette { scale = scale[name], shade = shade[sh] or S.S500 }
end

local function color_namespace(kind)
    local out = {
        white = token(kind(color_ref("white"))),
        black = token(kind(color_ref("black"))),
        transparent = token(kind(color_ref("transparent"))),
    }
    for name in pairs(scale) do
        out[name] = indexed(function(sh) return token(kind(color_ref(name, sh))) end)
    end
    return out
end

M.bg = color_namespace(function(v) return BS.ABg { value = v } end)
M.fg = color_namespace(function(v) return BS.AFg { value = v } end)
M.border_color = color_namespace(function(v) return BS.ABorderColor { value = v } end)

M.text = namespace({
    xs = token(BS.ATextSize { value = S.TxtXs }),
    sm = token(BS.ATextSize { value = S.TxtSm }),
    base = token(BS.ATextSize { value = S.TxtBase }),
    lg = token(BS.ATextSize { value = S.TxtLg }),
    xl = token(BS.ATextSize { value = S.TxtXl }),
    ["2xl"] = token(BS.ATextSize { value = S.Txt2xl }),
    ["3xl"] = token(BS.ATextSize { value = S.Txt3xl }),
    ["4xl"] = token(BS.ATextSize { value = S.Txt4xl }),
    ["5xl"] = token(BS.ATextSize { value = S.Txt5xl }),
    ["6xl"] = token(BS.ATextSize { value = S.Txt6xl }),
    left = token(BS.ATextAlign { value = S.TLeft }),
    center = token(BS.ATextAlign { value = S.TCenter }),
    right = token(BS.ATextAlign { value = S.TRight }),
    justify = token(BS.ATextAlign { value = S.TJustify }),
})
M.font = namespace({
    thin = token(BS.ATextWeight { value = S.Thin }),
    extralight = token(BS.ATextWeight { value = S.ExtraLight }),
    light = token(BS.ATextWeight { value = S.Light }),
    normal = token(BS.ATextWeight { value = S.Normal }),
    medium = token(BS.ATextWeight { value = S.Medium }),
    semibold = token(BS.ATextWeight { value = S.Semibold }),
    bold = token(BS.ATextWeight { value = S.Bold }),
    extrabold = token(BS.ATextWeight { value = S.ExtraBold }),
    black = token(BS.ATextWeight { value = S.WeightBlack }),
})
M.cursor = namespace({
    default = token(BS.ACursor { value = S.CursorDefault }),
    pointer = token(BS.ACursor { value = S.CursorPointer }),
    text = token(BS.ACursor { value = S.CursorText }),
    move = token(BS.ACursor { value = S.CursorMove }),
    grab = token(BS.ACursor { value = S.CursorGrab }),
    grabbing = token(BS.ACursor { value = S.CursorGrabbing }),
    not_allowed = token(BS.ACursor { value = S.CursorNotAllowed }),
})

local function with_cond(value, build_cond)
    local g = group(value)
    local out = {}
    for i = 1, #g.items do
        out[i] = BS.Token { cond = build_cond(g.items[i].cond), atom = g.items[i].atom }
    end
    return BS.Group { items = out }
end

local function state_cond(base, field, req)
    return BS.StateCond {
        hovered = field == "hovered" and req or base.state.hovered,
        focused = field == "focused" and req or base.state.focused,
        active = field == "active" and req or base.state.active,
        selected = field == "selected" and req or base.state.selected,
        disabled = field == "disabled" and req or base.state.disabled,
    }
end

function M.hover(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = c.scheme, motion = c.motion, state = state_cond(c, "hovered", S.ReqOn) } end) end
function M.focus(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = c.scheme, motion = c.motion, state = state_cond(c, "focused", S.ReqOn) } end) end
function M.active(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = c.scheme, motion = c.motion, state = state_cond(c, "active", S.ReqOn) } end) end
function M.selected(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = c.scheme, motion = c.motion, state = state_cond(c, "selected", S.ReqOn) } end) end
function M.disabled(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = c.scheme, motion = c.motion, state = state_cond(c, "disabled", S.ReqOn) } end) end
function M.dark(v) return with_cond(v, function(c) return BS.Cond { bp = c.bp, scheme = S.DarkOnly, motion = c.motion, state = c.state } end) end
function M.md(v) return with_cond(v, function(c) return BS.Cond { bp = S.MdUp, scheme = c.scheme, motion = c.motion, state = c.state } end) end

function M.state(opts)
    opts = opts or {}
    return BS.State {
        hovered = not not opts.hovered,
        focused = not not opts.focused,
        active = not not opts.active,
        selected = not not opts.selected,
        disabled = not not opts.disabled,
    }
end

M.T = T
return M
