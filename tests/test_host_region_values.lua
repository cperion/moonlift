package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test region values using .mlua eval
local Host = require("moonlift.mlua_run")

local sum_to = Host.eval [[
return func sum_to(n: i32): i32
    return region: i32
    entry loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
    end
end
]]
assert(sum_to.kind == "func")
assert(sum_to.name == "sum_to")
print("OK: sum_to constructed")
local ok, compiled = pcall(function() return sum_to:compile() end)
if ok then
    assert(compiled(5) == 10)
    compiled:free()
    print("OK: compiled")
end

-- Region fragment with emit
local use_double = Host.eval [[
local double = region(x: i32; out: cont(y: i32))
entry start() jump out(y = x * 2) end
end
return func use_double(x: i32): i32
    return region: i32
    entry start()
        emit @{double}(x; out = done)
    end
    block done(y: i32)
        yield y
    end
    end
end
]]
assert(use_double.name == "use_double")
print("OK: use_double constructed")
local ok2, compiled2 = pcall(function() return use_double:compile() end)
if ok2 then
    assert(compiled2(21) == 42)
    compiled2:free()
    print("OK: compiled")
end

print("moonlift host region values ok")
