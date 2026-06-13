package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

local src = [[
struct HasView
    xs: view(i32),
    n: index,
end

struct HasNilView
    xs: view(f32),
    n: index,
end

local wrap = func(xs: ptr(i32), n: index): index
    let v: view(i32) = view(xs, n)
    let h: HasView = { xs = v, n = n }
    return as(index, h.xs[2]) + len(h.xs) + h.n
end

local nil_view_len = func(): index
    let h: HasNilView = { xs = view(as(ptr(f32), nil), as(index, 0)), n = as(index, 7) }
    return len(h.xs) + h.n
end

return { wrap = wrap, nil_view_len = nil_view_len }
]]

local mod = moon.loadstring(src, "test_view_aggregate_lowering.mlua")()
local wrap = mod.wrap:compile()
local xs = ffi.new("int32_t[3]", { 10, 20, 30 })
assert(wrap(xs, 3) == 36)
wrap:free()

local nil_view_len = mod.nil_view_len:compile()
assert(nil_view_len() == 7)
nil_view_len:free()

return "view aggregate lowering ok"
