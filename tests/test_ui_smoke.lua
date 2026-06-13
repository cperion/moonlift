package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")

assert(ui.T, "ui facade exposes ASDL context")
assert(ui.build, "ui facade exposes builders")
assert(ui.tw, "ui facade exposes Tailwind-style tokens")
assert(ui.paint, "ui facade exposes paint builders")
assert(require("pvm") == require("moonlift.pvm"), "top-level pvm compatibility shim")

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
    b.text { tw.text_xl, tw.fg.white, "Moonlift synth" },
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

print("ok test_ui_smoke")
