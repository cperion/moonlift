local A = require("mlui.asdl")
local T = A.T
local B = A.B
local P = T.Paint
local Core = T.Core

local M = {}

local function id(value)
    if value == nil or value == false then return Core.NoId end
    local cls = require("pvm").classof(value)
    if cls and T.Core.Id.members[cls] then return value end
    return B.Core.IdValue { value = tostring(value) }
end

local function plain_array(items)
    local out = {}
    for i = 1, #items do
        if items[i] ~= nil and items[i] ~= false then out[#out + 1] = items[i] end
    end
    return out
end

local function callable(fn)
    return setmetatable({}, {
        __call = function(_, opts)
            if type(opts) ~= "table" then error("paint builder expects a plain table", 2) end
            return fn(opts)
        end,
    })
end

function M.stroke(opts)
    opts = opts or {}
    return B.Paint.Stroke { rgba8 = opts.color or opts.rgba8 or 0xffffffff, width = opts.width or 1 }
end

function M.fill(opts)
    opts = opts or {}
    return B.Paint.SolidFill { rgba8 = opts.color or opts.rgba8 or 0xffffffff }
end

M.no_fill = P.NoFill
M.mesh_triangles = P.MeshTriangles
M.mesh_strip = P.MeshStrip
M.mesh_fan = P.MeshFan

M.line = callable(function(o)
    return B.Paint.Line { x1 = o.x1 or o[1] or 0, y1 = o.y1 or o[2] or 0, x2 = o.x2 or o[3] or 0, y2 = o.y2 or o[4] or 0, stroke = o.stroke or M.stroke {} }
end)

M.polyline = callable(function(o)
    return B.Paint.Polyline { xy = plain_array(o.points or o.xy or o), stroke = o.stroke or M.stroke {} }
end)

M.polygon = callable(function(o)
    return B.Paint.Polygon { xy = plain_array(o.points or o.xy or o), fill = o.fill or P.NoFill, stroke = o.stroke }
end)

M.circle = callable(function(o)
    return B.Paint.Circle { cx = o.cx or o.x or 0, cy = o.cy or o.y or 0, r = o.r or o.radius or 0, fill = o.fill or P.NoFill, stroke = o.stroke }
end)

M.arc = callable(function(o)
    return B.Paint.Arc { cx = o.cx or o.x or 0, cy = o.cy or o.y or 0, r = o.r or o.radius or 0, a1 = o.a1 or 0, a2 = o.a2 or 0, segments = o.segments or 24, stroke = o.stroke or M.stroke {} }
end)

M.bezier = callable(function(o)
    return B.Paint.Bezier { xy = plain_array(o.points or o.xy or o), segments = o.segments or 24, stroke = o.stroke or M.stroke {} }
end)

M.vertex = callable(function(o)
    return B.Paint.Vertex { x = o.x or o[1] or 0, y = o.y or o[2] or 0, u = o.u or o[3] or 0, v = o.v or o[4] or 0 }
end)

M.mesh = callable(function(o)
    return B.Paint.Mesh {
        mode = o.mode or P.MeshTriangles,
        vertices = plain_array(o.vertices or {}),
        image_id = o.image_id and id(o.image_id) or nil,
        tint_rgba8 = o.tint or o.tint_rgba8 or 0xffffffff,
        opacity = o.opacity or 100,
    }
end)

M.image = callable(function(o)
    return B.Paint.Image {
        image_id = id(o.image or o.image_id or o.id),
        src_x = o.src_x or 0,
        src_y = o.src_y or 0,
        src_w = o.src_w or o.w or 0,
        src_h = o.src_h or o.h or 0,
        tint_rgba8 = o.tint or o.tint_rgba8 or 0xffffffff,
        opacity = o.opacity or 100,
    }
end)

M.T = T
M.B = B

return M
