package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

-- Typed ID with splice using the session's moon API (not a separate require)
local typed = Host.eval [[
local T = moon.i32
return func typed_id(x: @{T}) -> @{T}
    return x
end
]]
local c_typed = typed:compile()
assert(c_typed(42) == 42)
c_typed:free()

-- Nested type in as expression
local nested_type_in_as = Host.eval [[
return func nested_type_in_as(p: ptr(i32)) -> ptr(i32)
    return as(ptr(i32), p)
end
]]
assert(nested_type_in_as.name == "nested_type_in_as")

-- Expression fragment use
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

-- Region fragment use
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

-- Error: non-type value in type splice position
local ok, err = pcall(function()
    Host.eval [[
local not_a_type = 42
return func bad(x: @{not_a_type}) -> i32
    return x
end
]]
end)
assert(not ok)
assert(tostring(err):match("type splice") or tostring(err):match("splice"))

-- Error: emit with non-fragment value
local ok_emit, err_emit = pcall(function()
    Host.eval [[
local S = 42
return func bad_emit() -> i32
    return emit @{S}()
end
]]
end)
assert(not ok_emit)
assert(tostring(err_emit):match("emit%-expr target") or tostring(err_emit):match("expected") or tostring(err_emit):match("splice"))

print("moonlift mlua splice shapes ok")
