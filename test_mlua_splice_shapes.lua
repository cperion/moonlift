package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local Host = require("moonlift.host_quote")

local typed = Host.eval [[
local moon = require("moonlift.host")
local T = moon.i32
return func typed_id(x: @{T}) -> @{T}
    return x
end
]]
local c_typed = typed:compile()
assert(c_typed(42) == 42)
c_typed:free()

local use_expr = Host.eval [[
local inc = expr inc(x: i32) -> i32
    x + 1
end
return func use_expr(x: i32) -> i32
    return emit @{inc}(x)
end
]]
local c_expr = use_expr:compile()
assert(c_expr(41) == 42)
c_expr:free()

local use_region = Host.eval [[
local emit_hit = region emit_hit(x: i32; hit: cont(y: i32))
entry start()
    jump hit(y = x + 1)
end
end
return func use_region(x: i32) -> i32
    return region -> i32
    entry start()
        emit @{emit_hit}(x; hit = done)
    end
    block done(y: i32)
        yield y
    end
    end
end
]]
local c_region = use_region:compile()
assert(c_region(41) == 42)
c_region:free()

local ok, err = pcall(function()
    Host.eval [[
local not_a_type = 42
return func bad(x: @{not_a_type}) -> i32
    return x
end
]]
end)
assert(not ok)
assert(tostring(err):match("Moonlift splice kind mismatch"))

print("moonlift mlua splice shapes ok")
