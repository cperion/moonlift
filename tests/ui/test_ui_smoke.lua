package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

assert(ui.T, "ui facade exposes ASDL context")
assert(ui.build, "ui facade exposes builders")
assert(ui.tw, "ui facade exposes Tailwind-style tokens")
assert(ui.paint, "ui facade exposes paint builders")
assert(ui.theme, "ui facade exposes default theme/env helpers")
assert(require("pvm") == require("lalin.pvm"), "top-level pvm compatibility shim")

local b = ui.build
local tw = ui.tw
local paint = ui.paint

local root = b.box {
    b.id("synth-root"),
    tw.flex,
    tw.col,
    tw.w_px(640),
    tw.h_px(360),
    tw.bg.slate[950],
    b.text { tw.text_xl, tw.fg.white, "Lalin synth" },
    b.paint {
        b.id("scope"),
        tw.w_px(256),
        tw.h_px(96),
        paint.line(0, 48, 256, 48, paint.stroke(0x334155ff, 1)),
        paint.polyline({ 0, 48, 64, 24, 128, 72, 192, 28, 256, 48 }, paint.stroke(0x38bdf8ff, 2)),
    },
}

assert(root.id.value == "synth-root")
assert(#root.children == 2)
assert(root.children[2].id.value == "scope")

local theme = ui.theme.default()
local env = ui.theme.env_for_width(640)
local lowered = pvm.drain(ui.lower.phase(root, theme, env))
assert(#lowered == 1, "root lowers to one layout node")

local solve_env = ui.T.Solve.Env(640, 360)
local solved = pvm.one(ui.solve.root(lowered[1].layout, solve_env, false))
local rg, rp, rc = ui.render.root(solved, lowered[1].decor)
local report = ui.runtime.run(nil, { pointer_x = 10, pointer_y = 10 }, rg, rp, rc)
assert(report ~= nil, "runtime can consume rendered op stream without a driver")

local sdl3 = require("ui._sdl3")
assert(sdl3.SDLK_PAGEUP ~= nil, "SDL3 PageUp key constant is defined")
assert(sdl3.SDLK_PAGEDOWN ~= nil, "SDL3 PageDown key constant is defined")
assert(sdl3.SDLK_TAB ~= nil, "SDL3 Tab key constant is defined")
assert(sdl3.SDLK_SPACE ~= nil, "SDL3 Space key constant is defined")

print("ok test_ui_smoke")
