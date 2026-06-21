package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local ui = require("mlui")
local tw = ui.tw
local W = ui.widgets

local T = ui.T

local save = W.button "save" {
    id = ui.id "save",
    label = "Save",
}

local root = ui.box "main" {
    tw.flex,
    tw.col,
    tw.gap.y[4],
    tw.p[6],
    tw.bg.slate[950],
    tw.fg.white,
    ui.text "Oscillator" { tw.text.lg, tw.font.semibold },
    ui.scroll.y "preset_list" {
        tw.h[240],
        child = ui.fragment {
            ui.text "A",
            false,
            ui.text "B",
        },
    },
    ui.input.activate "save" {
        child = save.node,
    },
}

assert(pvm.classof(root) == T.Auth.Box)
assert(root.children[2].axis == T.Style.ScrollY)
assert(pvm.classof(root.children[3]) == T.Auth.WithInput)

local overlay = ui.overlay "menu" {
    anchor = "save",
    placement = ui.place.below,
    modal = false,
    child = root,
}
assert(pvm.classof(overlay) == T.Auth.Overlay)

local workbench = ui.compose.workbench "synth" {
    toolbar = ui.text "Toolbar",
    sidebar = ui.text "Browser",
    main = root,
    bottom = ui.text "Bottom",
}
assert(pvm.classof(workbench) == T.Compose.Workbench)

local program = ui.program(root, { epoch = 42 })
assert(program.header.magic == "MLUI")
assert(program.header.root_kind == "auth")
assert(program.header.epoch == 42)
assert(program.auth.nodes[program.header.root_index].kind == ui.constants.AUTH_BOX)
assert(#program.auth.nodes >= 7)
assert(#program.auth.children >= 4)
assert(#program.auth.styles.tokens >= 8)
assert(#program.resources.ids >= 2)
assert(#program.resources.contents >= 3)

local text_row
for i = 1, #program.auth.nodes do
    if program.auth.nodes[i].kind == ui.constants.AUTH_TEXT then
        text_row = program.auth.nodes[i]
        break
    end
end
assert(text_row and text_row.content ~= 0)

print("ok")
