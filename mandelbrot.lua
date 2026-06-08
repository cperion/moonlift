package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

-- Escape-time kernel. Takes fx,fy as scaled integers (Q16.16 fixed-point).
-- Returns iteration count clamped to 0..max_it.
-- zx, zy, cr, ci all Q16.16. |z| > 2 check via (zx^2 + zy^2) > 4 * 65536^2
local mandel = Host.eval [[
local mandel = func(cr: i32, ci: i32, max_it: i32): i32
    block loop(i: i32 = 0, zx: i32 = 0, zy: i32 = 0)
        if i >= max_it then return i end
        let zx2: i32 = as(i32, (as(i64, zx) * as(i64, zx)) >> 16)
        let zy2: i32 = as(i32, (as(i64, zy) * as(i64, zy)) >> 16)
        if zx2 + zy2 > 4 * 65536 then return i end
        let nzy: i32 = as(i32, (as(i64, zx) * as(i64, zy) * 2) >> 16) + ci
        let nzx: i32 = zx2 - zy2 + cr
        jump loop(i = i + 1, zx = nzx, zy = nzy)
    end
end
return mandel
]]
local c_mandel = mandel:compile()

-- ASCII shade ramp (dense → sparse)
local ramp = " .:-=+*#%@"
local W, H = 80, 30
local xmin, xmax = -2.0, 1.0
local ymin, ymax = -1.2, 1.2
local max_it = 256
local scale = 65536.0  -- Q16.16

for py = 0, H - 1 do
    local row = {}
    local ci = math.floor((ymin + (ymax - ymin) * py / (H - 1)) * scale)
    for px = 0, W - 1 do
        local cr = math.floor((xmin + (xmax - xmin) * px / (W - 1)) * scale)
        local it = c_mandel(cr, ci, max_it)
        local idx = it >= max_it and #ramp or (it % (#ramp - 1)) + 1
        row[#row + 1] = ramp:sub(idx, idx)
    end
    print(table.concat(row))
end

c_mandel:free()
