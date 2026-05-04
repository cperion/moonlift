package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Host = require("moonlift.mlua_run")
local MluaParse = require("moonlift.mlua_parse")

local T = pvm.context()
A.Define(T)
local MP = MluaParse.Define(T)

local src = [[
module LocalRegion
region emit_inc(x: i32; done: cont(y: i32))
entry start()
    jump done(y = x + 1)
end
end

export func use_region(x: i32) -> i32
    return region -> i32
    entry start()
        emit emit_inc(x; done = finished)
    end
    block finished(y: i32)
        yield y
    end
    end
end
end
]]

local parsed = MP.parse(src, "module_local_region.mlua")
assert(#parsed.issues == 0, tostring(parsed.issues[1]))
assert(#parsed.region_frags == 1)
assert(#parsed.module.items == 1)
assert(parsed.module.items[1].func.name == "use_region")

local mod = Host.eval("local m = " .. src .. "\nreturn m")
local compiled = mod:compile()
assert(compiled:get("use_region")(41) == 42)
compiled:free()

print("moonlift mlua module local region ok")
