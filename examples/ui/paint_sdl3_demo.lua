package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local sdl3 = ui.backends.sdl3
local input = ui.input
local paint = ui.paint
local T = ui.T
local Layout = T.Layout

local function main()
    local host = sdl3.new_host {
        title = "Lalin SDL3 paint demo",
        width = 900,
        height = 560,
        vsync = true,
    }

    local auto_quit_ms = tonumber(os.getenv("AUTO_QUIT_MS") or "")
    local start = host:now_ms()
    local running = true
    local phase = 0

    while running do
        for _, ev in ipairs(host:poll_events()) do
            if ev.type == "quit" or ev.type == "window_close_requested" then
                running = false
            elseif ev.type == "key_down" and ev.key == input.KeyEscape then
                running = false
            end
        end

        local w, h = host:size()
        phase = phase + 0.035
        local d = host.driver

        host:begin_frame(0x020617ff)

        d:draw_rect(24, 24, w - 48, h - 48, T.Resolved.BoxVisual(
            0x0f172aff,
            0x334155ff,
            1,
            Layout.ShapeRoundRect,
            18,
            100
        ))
        d:draw_rect(48, 54, 250, 72, T.Resolved.BoxVisual(
            0x1e293bff,
            0x38bdf8ff,
            3,
            Layout.ShapeCapsule,
            999,
            100
        ))
        d:draw_rect(320, 54, 250, 72, T.Resolved.BoxVisual(
            0x111827ff,
            0xf59e0bff,
            4,
            Layout.ShapeRoundRect,
            16,
            100
        ))

        local scope = {}
        for i = 0, 160 do
            local x = 52 + i * 2.4
            local y = 220 + math.sin(i * 0.09 + phase) * 42 + math.sin(i * 0.23 + phase * 0.7) * 12
            scope[#scope + 1] = x
            scope[#scope + 1] = y
        end

        d:draw_paint(0, 0, w, h, paint.list {
            paint.line(52, 220, 440, 220, paint.stroke(0x334155ff, 1)),
            paint.polyline(scope, paint.stroke(0x38bdf8ff, 3)),
            paint.polygon({ 520, 170, 840, 170, 790, 320, 565, 320 }, paint.fill(0x14b8a622), paint.stroke(0x2dd4bfff, 3)),
            paint.circle(630, 245, 48, paint.fill(0xf59e0b55), paint.stroke(0xfbbf24ff, 5)),
            paint.arc(735, 245, 60, -2.4 + phase * 0.2, 1.0 + phase * 0.2, 40, paint.stroke(0xef4444ff, 7)),
            paint.bezier({ 70, 390, 180, 300, 310, 480, 445, 370 }, 48, paint.stroke(0x22c55eff, 4)),
            paint.mesh(paint.mesh_fan, {
                paint.vertex(620, 390),
                paint.vertex(760, 350),
                paint.vertex(840, 430),
                paint.vertex(760, 500),
                paint.vertex(610, 470),
                paint.vertex(560, 410),
            }, nil, 0x8b5cf6cc, 100),
        })

        host:present()

        if auto_quit_ms ~= nil and host:now_ms() - start >= auto_quit_ms then
            running = false
        end
        host:delay(8)
    end

    host:close()
end

main()
