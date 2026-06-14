local pvm = require("pvm")
local sdl3 = require("ui._sdl3")
local ui_asdl = require("ui.asdl")

local ffi = sdl3.ffi
local sdl = sdl3.sdl
local ttf = sdl3.ttf

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Layout = T.Layout
local Paint = T.Paint

local M = {}

M.capabilities = {
    runtime = {
        boxes = true,
        rounded_boxes = true,
        capsules = true,
        clipping = true,
        transforms = true,
        scrolling = true,
        layers = "generic",
        cursors = true,
        density = "logical-noop",
    },
    paint = {
        line = true,
        polyline = true,
        polygon_fill = true,
        circle_fill = true,
        arc = true,
        bezier = true,
        mesh = true,
        image = "texture-or-bmp-resolver",
        stroke_width = true,
    },
    text = {
        draw = true,
    },
}

local function round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return math.ceil(n - 0.5)
end

local function rgba8_bytes(rgba8, opacity)
    opacity = opacity or 1
    local a = ((rgba8 % 256) / 255) * opacity
    rgba8 = math.floor(rgba8 / 256)
    local b = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local g = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local r = rgba8 % 256
    return r, g, b, round(a * 255)
end

local function default_font_path()
    local candidates = {
        "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf",
        "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    }
    for i = 1, #candidates do
        local f = io.open(candidates[i], "rb")
        if f then f:close(); return candidates[i] end
    end
    return nil
end

local function normalize_font_spec(spec, default_path)
    if type(spec) == "string" then return { path = spec } end
    if type(spec) == "table" then return spec end
    if spec == nil and default_path ~= nil then return { path = default_path } end
    return nil
end

local function normalize_align(align)
    if align == 1 then return ffi.C.TTF_HORIZONTAL_ALIGN_CENTER end
    if align == 2 then return ffi.C.TTF_HORIZONTAL_ALIGN_RIGHT end
    return ffi.C.TTF_HORIZONTAL_ALIGN_LEFT
end

local function cursor_name(cursor)
    if cursor == nil or cursor == Style.CursorDefault then return nil end
    if cursor == Style.CursorPointer then return sdl3.SDL_SYSTEM_CURSOR_POINTER end
    if cursor == Style.CursorText then return sdl3.SDL_SYSTEM_CURSOR_TEXT end
    if cursor == Style.CursorMove then return sdl3.SDL_SYSTEM_CURSOR_MOVE end
    if cursor == Style.CursorNotAllowed then return sdl3.SDL_SYSTEM_CURSOR_NOT_ALLOWED end
    if cursor == Style.CursorGrab or cursor == Style.CursorGrabbing then return sdl3.SDL_SYSTEM_CURSOR_POINTER end
    return nil
end

local function with_color(renderer, rgba8, opacity)
    local r, g, b, a = rgba8_bytes(rgba8, opacity)
    if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
        sdl3.err("ui.runtime_sdl3: SDL_SetRenderDrawColor failed")
    end
end

local function frect(x, y, w, h)
    local r = ffi.new("SDL_FRect[1]")
    r[0].x = x
    r[0].y = y
    r[0].w = w
    r[0].h = h
    return r
end

local function srect(x, y, w, h)
    local r = ffi.new("SDL_Rect[1]")
    r[0].x = round(x)
    r[0].y = round(y)
    r[0].w = round(w)
    r[0].h = round(h)
    return r
end

local function poly_points(xy, ox, oy)
    local n = math.floor(#xy / 2)
    local pts = ffi.new("SDL_FPoint[?]", n)
    local k = 0
    for i = 1, #xy, 2 do
        pts[k].x = ox + xy[i]
        pts[k].y = oy + xy[i + 1]
        k = k + 1
    end
    return pts, n
end

local function circle_points(cx, cy, r, segments)
    segments = math.max(12, segments or math.floor(r * 0.8))
    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
    for i = 0, segments do
        local a = (i / segments) * math.pi * 2
        pts[i].x = cx + math.cos(a) * r
        pts[i].y = cy + math.sin(a) * r
    end
    return pts, segments + 1
end

local function arc_points(cx, cy, r, a1, a2, segments)
    segments = math.max(8, segments or 24)
    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
    for i = 0, segments do
        local t = i / segments
        local a = a1 + (a2 - a1) * t
        pts[i].x = cx + math.cos(a) * r
        pts[i].y = cy + math.sin(a) * r
    end
    return pts, segments + 1
end

local function resolved_round_rect_radius(box_visual, w, h)
    if box_visual == nil or box_visual.shape ~= Layout.ShapeRoundRect then
        return 0
    end
    local max_r = math.max(0, math.min(w, h) * 0.5)
    local r = box_visual.radius or 0
    if r < 0 then return 0 end
    if r > max_r then return max_r end
    return r
end

local function put_color(v, rgba8, opacity)
    opacity = opacity or 1
    local a = ((rgba8 % 256) / 255) * opacity
    rgba8 = math.floor(rgba8 / 256)
    local b = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local g = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local r = rgba8 % 256
    v.color.r = r / 255
    v.color.g = g / 255
    v.color.b = b / 255
    v.color.a = a
end

local function put_vertex(v, x, y, rgba8, opacity, u, tv)
    v.position.x = x
    v.position.y = y
    put_color(v, rgba8, opacity)
    v.tex_coord.x = u or 0
    v.tex_coord.y = tv or 0
end

local function render_geometry(renderer, texture, vertices, num_vertices, indices, num_indices)
    if num_vertices <= 0 then return end
    if sdl.SDL_RenderGeometry(renderer, texture, vertices, num_vertices, indices, num_indices or 0) == 0 then
        sdl3.err("ui.runtime_sdl3: SDL_RenderGeometry failed")
    end
end

local function fill_polygon_points(renderer, points, rgba8, opacity)
    local n = #points / 2
    if n < 3 then return end
    if points[1] == points[#points - 1] and points[2] == points[#points] then
        n = n - 1
        if n < 3 then return end
    end
    local vertices = ffi.new("SDL_Vertex[?]", n)
    for i = 0, n - 1 do
        put_vertex(vertices[i], points[i * 2 + 1], points[i * 2 + 2], rgba8, opacity)
    end
    local index_count = (n - 2) * 3
    local indices = ffi.new("int[?]", index_count)
    local k = 0
    for i = 1, n - 2 do
        indices[k] = 0
        indices[k + 1] = i
        indices[k + 2] = i + 1
        k = k + 3
    end
    render_geometry(renderer, nil, vertices, n, indices, index_count)
end

local function fill_polygon_xy(renderer, xy, ox, oy, rgba8, opacity)
    local n = math.floor(#xy / 2)
    if n < 3 then return end
    local points = {}
    for i = 1, n do
        points[#points + 1] = ox + xy[i * 2 - 1]
        points[#points + 1] = oy + xy[i * 2]
    end
    fill_polygon_points(renderer, points, rgba8, opacity)
end

local function draw_thick_segment(renderer, x1, y1, x2, y2, stroke)
    local width = math.max(1, stroke and stroke.width or 1)
    if width <= 1.25 then
        with_color(renderer, stroke.rgba8, 1)
        if sdl.SDL_RenderLine(renderer, x1, y1, x2, y2) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_RenderLine failed")
        end
        return
    end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0.00001 then return end
    local hw = width * 0.5
    local nx, ny = -dy / len * hw, dx / len * hw
    fill_polygon_points(renderer, {
        x1 + nx, y1 + ny,
        x2 + nx, y2 + ny,
        x2 - nx, y2 - ny,
        x1 - nx, y1 - ny,
    }, stroke.rgba8, 1)
end

local function draw_thick_polyline(renderer, pts, n, stroke)
    if n < 2 then return end
    for i = 0, n - 2 do
        draw_thick_segment(renderer, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, stroke)
    end
end

local function circle_segment_count(r)
    return math.max(16, math.min(96, math.floor(math.max(1, r) * 0.8)))
end

local function fill_circle(renderer, cx, cy, r, rgba8, opacity, segments)
    if r <= 0 then return end
    segments = math.max(8, segments or circle_segment_count(r))
    local vertices = ffi.new("SDL_Vertex[?]", segments + 1)
    put_vertex(vertices[0], cx, cy, rgba8, opacity)
    for i = 0, segments - 1 do
        local a = (i / segments) * math.pi * 2
        put_vertex(vertices[i + 1], cx + math.cos(a) * r, cy + math.sin(a) * r, rgba8, opacity)
    end
    local indices = ffi.new("int[?]", segments * 3)
    local k = 0
    for i = 1, segments do
        indices[k] = 0
        indices[k + 1] = i
        indices[k + 2] = (i == segments) and 1 or (i + 1)
        k = k + 3
    end
    render_geometry(renderer, nil, vertices, segments + 1, indices, segments * 3)
end

local function fill_rect(renderer, x, y, w, h, rgba8, opacity)
    if w <= 0 or h <= 0 then return end
    with_color(renderer, rgba8, opacity)
    if sdl.SDL_RenderFillRect(renderer, frect(x, y, w, h)) == 0 then
        sdl3.err("ui.runtime_sdl3: SDL_RenderFillRect failed")
    end
end

local function fill_box_shape(renderer, shape, x, y, w, h, radius, rgba8, opacity)
    if w <= 0 or h <= 0 then return end
    if shape == Layout.ShapeCapsule then
        if w > h then
            local r = h * 0.5
            fill_rect(renderer, x + r, y, w - h, h, rgba8, opacity)
            fill_circle(renderer, x + r, y + r, r, rgba8, opacity)
            fill_circle(renderer, x + w - r, y + r, r, rgba8, opacity)
        elseif h > w then
            local r = w * 0.5
            fill_rect(renderer, x, y + r, w, h - w, rgba8, opacity)
            fill_circle(renderer, x + r, y + r, r, rgba8, opacity)
            fill_circle(renderer, x + r, y + h - r, r, rgba8, opacity)
        else
            fill_circle(renderer, x + w * 0.5, y + h * 0.5, w * 0.5, rgba8, opacity)
        end
        return
    end
    if shape == Layout.ShapeRoundRect and radius > 0 then
        local r = math.min(radius, w * 0.5, h * 0.5)
        fill_rect(renderer, x + r, y, w - 2 * r, h, rgba8, opacity)
        fill_rect(renderer, x, y + r, r, h - 2 * r, rgba8, opacity)
        fill_rect(renderer, x + w - r, y + r, r, h - 2 * r, rgba8, opacity)
        fill_circle(renderer, x + r, y + r, r, rgba8, opacity)
        fill_circle(renderer, x + w - r, y + r, r, rgba8, opacity)
        fill_circle(renderer, x + w - r, y + h - r, r, rgba8, opacity)
        fill_circle(renderer, x + r, y + h - r, r, rgba8, opacity)
        return
    end
    fill_rect(renderer, x, y, w, h, rgba8, opacity)
end

local function draw_arc_stroke(renderer, cx, cy, r, a1, a2, stroke, segments)
    local width = math.max(1, stroke and stroke.width or 1)
    segments = math.max(6, segments or math.floor(math.abs(a2 - a1) * math.max(8, r) / 5))
    if width <= 1.25 then
        local pts, n = arc_points(cx, cy, r, a1, a2, segments)
        with_color(renderer, stroke.rgba8, 1)
        if sdl.SDL_RenderLines(renderer, pts, n) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_RenderLines failed")
        end
        return
    end
    local outer = r + width * 0.5
    local inner = math.max(0, r - width * 0.5)
    local vertices = ffi.new("SDL_Vertex[?]", (segments + 1) * 2)
    for i = 0, segments do
        local t = i / segments
        local a = a1 + (a2 - a1) * t
        put_vertex(vertices[i * 2], cx + math.cos(a) * outer, cy + math.sin(a) * outer, stroke.rgba8, 1)
        put_vertex(vertices[i * 2 + 1], cx + math.cos(a) * inner, cy + math.sin(a) * inner, stroke.rgba8, 1)
    end
    local indices = ffi.new("int[?]", segments * 6)
    local k = 0
    for i = 0, segments - 1 do
        local a, b, c, d = i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 3
        indices[k], indices[k + 1], indices[k + 2] = a, c, b
        indices[k + 3], indices[k + 4], indices[k + 5] = b, c, d
        k = k + 6
    end
    render_geometry(renderer, nil, vertices, (segments + 1) * 2, indices, segments * 6)
end

local function draw_box_border(renderer, shape, x, y, w, h, radius, border_w, rgba8, opacity)
    if border_w <= 0 or rgba8 == 0 or w <= 0 or h <= 0 then return end
    border_w = math.max(1, border_w)
    local stroke = { rgba8 = rgba8, width = border_w }
    if shape == Layout.ShapeCapsule then
        if w >= h then
            local r = h * 0.5
            draw_thick_segment(renderer, x + r, y + border_w * 0.5, x + w - r, y + border_w * 0.5, stroke)
            draw_thick_segment(renderer, x + r, y + h - border_w * 0.5, x + w - r, y + h - border_w * 0.5, stroke)
            draw_arc_stroke(renderer, x + w - r, y + r, r - border_w * 0.5, -math.pi * 0.5, math.pi * 0.5, stroke)
            draw_arc_stroke(renderer, x + r, y + r, r - border_w * 0.5, math.pi * 0.5, math.pi * 1.5, stroke)
        else
            local r = w * 0.5
            draw_thick_segment(renderer, x + border_w * 0.5, y + r, x + border_w * 0.5, y + h - r, stroke)
            draw_thick_segment(renderer, x + w - border_w * 0.5, y + r, x + w - border_w * 0.5, y + h - r, stroke)
            draw_arc_stroke(renderer, x + r, y + r, r - border_w * 0.5, math.pi, math.pi * 2, stroke)
            draw_arc_stroke(renderer, x + r, y + h - r, r - border_w * 0.5, 0, math.pi, stroke)
        end
        return
    end
    if shape == Layout.ShapeRoundRect and radius > 0 then
        local r = math.min(radius, w * 0.5, h * 0.5)
        local cr = math.max(0, r - border_w * 0.5)
        draw_thick_segment(renderer, x + r, y + border_w * 0.5, x + w - r, y + border_w * 0.5, stroke)
        draw_thick_segment(renderer, x + r, y + h - border_w * 0.5, x + w - r, y + h - border_w * 0.5, stroke)
        draw_thick_segment(renderer, x + border_w * 0.5, y + r, x + border_w * 0.5, y + h - r, stroke)
        draw_thick_segment(renderer, x + w - border_w * 0.5, y + r, x + w - border_w * 0.5, y + h - r, stroke)
        draw_arc_stroke(renderer, x + w - r, y + r, cr, -math.pi * 0.5, 0, stroke)
        draw_arc_stroke(renderer, x + w - r, y + h - r, cr, 0, math.pi * 0.5, stroke)
        draw_arc_stroke(renderer, x + r, y + h - r, cr, math.pi * 0.5, math.pi, stroke)
        draw_arc_stroke(renderer, x + r, y + r, cr, math.pi, math.pi * 1.5, stroke)
        return
    end
    fill_rect(renderer, x, y, w, border_w, rgba8, opacity)
    fill_rect(renderer, x, y + h - border_w, w, border_w, rgba8, opacity)
    fill_rect(renderer, x, y + border_w, border_w, h - border_w * 2, rgba8, opacity)
    fill_rect(renderer, x + w - border_w, y + border_w, border_w, h - border_w * 2, rgba8, opacity)
end

function M.new(opts)
    opts = opts or {}
    local renderer = opts.renderer
    if renderer == nil then
        error("ui.runtime_sdl3.new requires opts.renderer", 2)
    end

    sdl3.ensure_ttf()

    local provided_fonts = opts.fonts or {}
    local resolve_font = opts.resolve_font
    local default_font = opts.default_font or default_font_path()
    local engine = ttf.TTF_CreateRendererTextEngine(renderer)
    if engine == nil then
        sdl3.err("ui.runtime_sdl3: TTF_CreateRendererTextEngine failed")
    end

    local clip_stack = {}
    local cursor_cache = {}
    local current_cursor_id = false
    local font_cache = {}
    local text_cache = {}
    local texture_cache = {}
    local owned_textures = {}
    local resolve_image = opts.resolve_image
    local images = opts.images
    local missing_image = opts.missing_image or (opts.require_images and "error" or "skip")
    local on_missing_image = opts.on_missing_image
    local closed = false

    local self = {
        capabilities = M.capabilities,
    }

    local function load_bmp_texture(path)
        local texture = texture_cache[path]
        if texture ~= nil then
            return texture ~= false and texture or nil
        end
        local surface = sdl.SDL_LoadBMP(path)
        if surface == nil then
            texture_cache[path] = false
            return nil
        end
        texture = sdl.SDL_CreateTextureFromSurface(renderer, surface)
        sdl.SDL_DestroySurface(surface)
        if texture == nil then
            texture_cache[path] = false
            return nil
        end
        texture_cache[path] = texture
        owned_textures[#owned_textures + 1] = texture
        return texture
    end

    local function texture_from(value)
        if value == nil or value == false then return nil end
        if type(value) == "string" then
            return load_bmp_texture(value)
        end
        if type(value) == "cdata" then
            return value
        end
        if type(value) == "table" then
            if value.texture ~= nil then return value.texture end
            if value.sdl_texture ~= nil then return value.sdl_texture end
            if value.path ~= nil then return load_bmp_texture(value.path) end
        end
        return nil
    end

    local function report_missing_image(id, primitive)
        local name = id ~= nil and id ~= Core.NoId and id.value or "<none>"
        local msg = "ui.runtime_sdl3: unresolved image " .. tostring(name) .. " for " .. tostring(primitive)
        if type(on_missing_image) == "function" then
            on_missing_image(msg, id, primitive)
        end
        if missing_image == "error" then
            error(msg, 3)
        end
        return nil
    end

    local function lookup_texture(id, primitive)
        if id == nil or id == Core.NoId then return nil end
        if resolve_image ~= nil then
            local texture = texture_from(resolve_image(id))
            if texture ~= nil then return texture end
        end
        if images ~= nil then
            local texture = texture_from(images[id.value] or images[id])
            if texture ~= nil then return texture end
        end
        return report_missing_image(id, primitive)
    end

    local function mesh_indices(mode, vertex_count)
        if vertex_count < 3 then return nil, 0 end
        if mode == Paint.MeshStrip then
            local count = (vertex_count - 2) * 3
            local indices = ffi.new("int[?]", count)
            local k = 0
            for i = 0, vertex_count - 3 do
                if i % 2 == 0 then
                    indices[k], indices[k + 1], indices[k + 2] = i, i + 1, i + 2
                else
                    indices[k], indices[k + 1], indices[k + 2] = i + 1, i, i + 2
                end
                k = k + 3
            end
            return indices, count
        end
        if mode == Paint.MeshFan then
            local count = (vertex_count - 2) * 3
            local indices = ffi.new("int[?]", count)
            local k = 0
            for i = 1, vertex_count - 2 do
                indices[k], indices[k + 1], indices[k + 2] = 0, i, i + 1
                k = k + 3
            end
            return indices, count
        end
        return nil, 0
    end

    local function font_spec_for(font_id, style)
        local spec
        if resolve_font ~= nil then
            spec = resolve_font(font_id, style)
        else
            spec = provided_fonts[font_id]
        end
        spec = normalize_font_spec(spec, default_font)
        if spec == nil or spec.path == nil then
            error("ui.runtime_sdl3: no font path for font_id=" .. tostring(font_id), 3)
        end
        return spec
    end

    local function font_key(path, size)
        return path .. "\0" .. tostring(size)
    end

    local function get_font(font_id, font_size, style)
        local spec = font_spec_for(font_id, style)
        local key = font_key(spec.path, font_size)
        local font = font_cache[key]
        if font == nil then
            font = ttf.TTF_OpenFont(spec.path, font_size)
            if font == nil then
                sdl3.err("ui.runtime_sdl3: TTF_OpenFont failed for " .. tostring(spec.path))
            end
            font_cache[key] = font
        end
        ttf.TTF_SetFontWrapAlignment(font, normalize_align(style and style.align or 0))
        return font, key
    end

    local function get_text(font, font_key_value, text_value)
        text_value = text_value or ""
        local key = font_key_value .. "\0" .. text_value
        local cached = text_cache[key]
        if cached == nil then
            cached = ttf.TTF_CreateText(engine, font, text_value, #text_value)
            if cached == nil then
                sdl3.err("ui.runtime_sdl3: TTF_CreateText failed")
            end
            text_cache[key] = cached
        end
        return cached
    end

    function self:draw_box(x, y, w, h, visual)
        return self:draw_rect(x, y, w, h, visual)
    end

    function self:draw_rect(x, y, w, h, visual)
        if visual == nil then return end
        local opacity = (visual.opacity or 100) / 100
        local shape = visual.shape or Layout.ShapeRect
        local radius = resolved_round_rect_radius(visual, w, h)
        if visual.bg ~= 0 then
            fill_box_shape(renderer, shape, x, y, w, h, radius, visual.bg, opacity)
        end
        if visual.border_w > 0 and visual.border_color ~= 0 then
            draw_box_border(renderer, shape, x, y, w, h, radius, visual.border_w, visual.border_color, opacity)
        end
    end

    function self:draw_text(x, y, w, h, layout)
        if layout == nil then return end
        local align = layout.style.align
        for i = 1, #layout.lines do
            local line = layout.lines[i]
            local draw_x = x + line.x
            if align == 1 then
                draw_x = draw_x + math.max(0, math.floor((w - line.w) / 2))
            elseif align == 2 then
                draw_x = draw_x + math.max(0, w - line.w)
            end
            local draw_y = y + line.y
            for j = 1, #line.runs do
                local run = line.runs[j]
                local font, font_key_value = get_font(run.font_id, run.font_size, layout.style)
                local text = get_text(font, font_key_value, run.text)
                local r, g, b, a = rgba8_bytes(run.fg, 1)
                if ttf.TTF_SetTextColor(text, r, g, b, a) == 0 then
                    sdl3.err("ui.runtime_sdl3: TTF_SetTextColor failed")
                end
                if ttf.TTF_DrawRendererText(text, round(draw_x + run.x), round(draw_y + run.y)) == 0 then
                    sdl3.err("ui.runtime_sdl3: TTF_DrawRendererText failed")
                end
            end
        end
    end

    function self:draw_paint(x, y, w, h, paint)
        if paint == nil then return end
        local items = paint.items or paint
        for i = 1, #items do
            local item = items[i]
            local cls = pvm.classof(item)
            if cls == Paint.Line then
                draw_thick_segment(renderer, x + item.x1, y + item.y1, x + item.x2, y + item.y2, item.stroke)
            elseif cls == Paint.Polyline then
                if #item.xy >= 4 then
                    local pts, n = poly_points(item.xy, x, y)
                    draw_thick_polyline(renderer, pts, n, item.stroke)
                end
            elseif cls == Paint.Polygon then
                if #item.xy >= 6 then
                    if item.fill ~= Paint.NoFill then
                        fill_polygon_xy(renderer, item.xy, x, y, item.fill.rgba8, 1)
                    end
                    if item.stroke ~= nil then
                        local pts, n = poly_points(item.xy, x, y)
                        draw_thick_polyline(renderer, pts, n, item.stroke)
                        draw_thick_segment(renderer, pts[n - 1].x, pts[n - 1].y, pts[0].x, pts[0].y, item.stroke)
                    end
                end
            elseif cls == Paint.Circle then
                if item.fill ~= Paint.NoFill then
                    fill_circle(renderer, x + item.cx, y + item.cy, item.r, item.fill.rgba8, 1)
                end
                if item.stroke ~= nil then
                    draw_arc_stroke(renderer, x + item.cx, y + item.cy, item.r, 0, math.pi * 2, item.stroke, circle_segment_count(item.r))
                end
            elseif cls == Paint.Arc then
                draw_arc_stroke(renderer, x + item.cx, y + item.cy, item.r, item.a1, item.a2, item.stroke, item.segments)
            elseif cls == Paint.Bezier then
                local xy = item.xy
                if #xy >= 8 then
                    local segments = math.max(8, round(item.segments))
                    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
                    local function eval(t)
                        local mt = 1 - t
                        local x1, y1 = xy[1], xy[2]
                        local x2, y2 = xy[3], xy[4]
                        local x3, y3 = xy[5], xy[6]
                        local x4, y4 = xy[7], xy[8]
                        local px = mt^3 * x1 + 3 * mt^2 * t * x2 + 3 * mt * t^2 * x3 + t^3 * x4
                        local py = mt^3 * y1 + 3 * mt^2 * t * y2 + 3 * mt * t^2 * y3 + t^3 * y4
                        return px, py
                    end
                    for j = 0, segments do
                        local px, py = eval(j / segments)
                        pts[j].x = x + px
                        pts[j].y = y + py
                    end
                    draw_thick_polyline(renderer, pts, segments + 1, item.stroke)
                end
            elseif cls == Paint.Mesh then
                local vertex_count = #item.vertices
                if vertex_count >= 3 then
                    local texture = lookup_texture(item.image_id, "mesh")
                    local opacity = (item.opacity or 100) / 100
                    local vertices = ffi.new("SDL_Vertex[?]", vertex_count)
                    for j = 1, vertex_count do
                        local v = item.vertices[j]
                        put_vertex(vertices[j - 1], x + v.x, y + v.y, item.tint_rgba8, opacity, v.u, v.v)
                    end
                    local indices, index_count = mesh_indices(item.mode, vertex_count)
                    render_geometry(renderer, texture, vertices, vertex_count, indices, index_count)
                end
            elseif cls == Paint.Image then
                local texture = lookup_texture(item.image_id, "image")
                if texture ~= nil then
                    local r, g, b, a = rgba8_bytes(item.tint_rgba8, (item.opacity or 100) / 100)
                    sdl.SDL_SetTextureColorMod(texture, r, g, b)
                    sdl.SDL_SetTextureAlphaMod(texture, a)
                    local src = nil
                    if item.src_w ~= 0 and item.src_h ~= 0 then
                        src = frect(item.src_x, item.src_y, item.src_w, item.src_h)
                    end
                    if sdl.SDL_RenderTexture(renderer, texture, src, frect(x, y, w, h)) == 0 then
                        sdl3.err("ui.runtime_sdl3: SDL_RenderTexture failed")
                    end
                end
            end
        end
    end

    function self:push_clip_rect(x, y, w, h)
        return self:push_clip(x, y, w, h)
    end

    function self:push_clip(x, y, w, h)
        local top = srect(x, y, w, h)
        clip_stack[#clip_stack + 1] = top
        if sdl.SDL_SetRenderClipRect(renderer, top) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect failed")
        end
    end

    function self:pop_clip_rect()
        return self:pop_clip()
    end

    function self:pop_clip()
        clip_stack[#clip_stack] = nil
        local top = clip_stack[#clip_stack]
        if top == nil then
            if sdl.SDL_SetRenderClipRect(renderer, nil) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect clear failed")
            end
        else
            if sdl.SDL_SetRenderClipRect(renderer, top) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect restore failed")
            end
        end
    end

    function self:set_cursor_kind(cursor)
        local id = cursor_name(cursor)
        if current_cursor_id == id then
            sdl.SDL_ShowCursor()
            return
        end

        current_cursor_id = id

        if id == nil then
            sdl.SDL_SetCursor(nil)
            sdl.SDL_ShowCursor()
            return
        end

        local c = cursor_cache[id]
        if c == nil then
            c = sdl.SDL_CreateSystemCursor(id)
            cursor_cache[id] = c or false
        end
        if c == false then
            sdl.SDL_SetCursor(nil)
        else
            sdl.SDL_SetCursor(c)
        end
        sdl.SDL_ShowCursor()
    end

    function self:set_cursor(name)
        if name == "text" then
            return self:set_cursor_kind(Style.CursorText)
        elseif name == "pointer" then
            return self:set_cursor_kind(Style.CursorPointer)
        elseif name == "move" then
            return self:set_cursor_kind(Style.CursorMove)
        elseif name == "not-allowed" then
            return self:set_cursor_kind(Style.CursorNotAllowed)
        end
        return self:set_cursor_kind(Style.CursorDefault)
    end

    function self:reset()
        if sdl.SDL_SetRenderClipRect(renderer, nil) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect reset failed")
        end
        clip_stack = {}
    end

    function self:close()
        if closed then return end
        closed = true
        for _, cached_text in pairs(text_cache) do
            ttf.TTF_DestroyText(cached_text)
        end
        text_cache = {}
        for _, font in pairs(font_cache) do
            ttf.TTF_CloseFont(font)
        end
        for _, cursor in pairs(cursor_cache) do
            if cursor ~= nil and cursor ~= false then
                sdl.SDL_DestroyCursor(cursor)
            end
        end
        for i = 1, #owned_textures do
            sdl.SDL_DestroyTexture(owned_textures[i])
        end
        owned_textures = {}
        texture_cache = {}
        if engine ~= nil then
            ttf.TTF_DestroyRendererTextEngine(engine)
            engine = nil
        end
        sdl3.release_ttf()
    end

    return self
end

M.T = T

return M
