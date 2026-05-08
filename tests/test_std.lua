package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;./lib/?/init.lua;" .. package.path

local moonlift = require("moonlift")
local Std = require("moonlift.std")

assert(moonlift.std == Std)
assert(moonlift.json == nil)
assert(Std.json == nil)
assert(moonlift.host == Std.host)
assert(moonlift.mlua == Std.mlua)
assert(moonlift.region_compose == Std.region_compose)
assert(moonlift.parser_compose == Std.parser_compose)
assert(moonlift.builtins == nil)
assert(Std.builtins == nil)

print("moonlift std ok")
