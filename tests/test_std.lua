package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;./lib/?/init.lua;" .. package.path

local moonlift = require("moonlift")
local Std = require("moonlift.std")

assert(moonlift.std == Std)
assert(moonlift.json == Std.json)
assert(moonlift.host == Std.host)
assert(moonlift.mlua == Std.mlua)
assert(moonlift.region_compose == Std.region_compose)
assert(moonlift.parser_compose == Std.parser_compose)
assert(moonlift.builtins == nil)
assert(Std.builtins == nil)

local src = [[{"id":42,"active":true}]]
if _M_HOSTED then
    local decoded = assert(moonlift.json.decode(src))
    assert(decoded.id == 42)
    assert(decoded.active == true)
    moonlift.json.free()
else
    local ok_json = pcall(function() moonlift.json.decode(src) end)
    assert(not ok_json)
end
print("moonlift std ok")
