package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local if_probe = moon.func [[
control_if_mutation(x: i32) -> i32
    return region -> i32
    entry start()
        var y: i32 = 0
        if x > 0 then
            y = 7
        else
            y = 3
        end
        yield y
    end
    end
end
]]

local if_compiled = if_probe:compile()
assert(if_compiled(5) == 7)
assert(if_compiled(-1) == 3)
if_compiled:free()

local switch_probe = moon.func [[
control_switch_mutation(x: i32) -> i32
    return region -> i32
    entry start()
        var y: i32 = 1
        switch x do
        case 0 then y = 10
        case 1 then y = 20
        default then y = 30
        end
        yield y
    end
    end
end
]]

local switch_compiled = switch_probe:compile()
assert(switch_compiled(0) == 10)
assert(switch_compiled(1) == 20)
assert(switch_compiled(2) == 30)
switch_compiled:free()

print("moonlift control var mutation ok")
