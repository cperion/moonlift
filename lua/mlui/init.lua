local builder = require("mlui.builder")
local program = require("mlui.program")

local M = {}
for k, v in pairs(builder) do M[k] = v end

M.asdl = require("mlui.asdl")
M.T = M.asdl.T
M.B = M.asdl.B
M.tw = require("mlui.tw")
M.paint_ops = require("mlui.paint")
M.program = program.auth
M.encode = program.encode
M.constants = program.K

M.paint = setmetatable({}, {
    __call = function(_, arg) return builder.paint(arg) end,
    __index = function(_, key) return M.paint_ops[key] end,
})

local function bundle(kind, id, node, extra)
    extra = extra or {}
    extra.kind = kind
    extra.id = id
    extra.node = node
    return extra
end

local function widget_builder(kind, build_node)
    local function build(staged, opts)
        opts = opts or {}
        local widget_id = opts.id or staged
        local node = build_node(widget_id, opts)
        return bundle(kind, builder.id(widget_id), node, {
            surfaces = opts.surfaces or {},
            events = opts.events,
            model = opts.model,
            report = opts.report,
        })
    end
    return setmetatable({}, {
        __call = function(_, arg)
            if type(arg) == "string" then
                return setmetatable({ _staged = arg }, {
                    __call = function(staged, opts) return build(staged._staged, opts) end,
                })
            end
            if type(arg) == "table" then return build(nil, arg) end
            error("widget builder expects string stage or plain table", 2)
        end,
    })
end

M.widgets = {
    button = widget_builder("button", function(id, opts)
        return M.input.activate {
            id = id or opts.id or "button",
            child = M.box {
                M.tw.flex, M.tw.row, M.tw.items.center, M.tw.justify.center,
                M.tw.gap.x[2], M.tw.px[4], M.tw.py[2], M.tw.rounded.lg,
                M.tw.border[1], M.tw.cursor.pointer,
                opts.styles,
                M.text(tostring(opts.label or opts.text or id or "Button")) { opts.label_styles },
            },
        }
    end),
    label = widget_builder("label", function(id, opts)
        return M.text(tostring(opts.label or opts.text or id or "")) { opts.styles }
    end),
}

M.theme = {}
M.env = {}
M.kernel = { program = M.program, encode = M.encode }

return M
