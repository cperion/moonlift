package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local moonlift = require("moonlift")
local Std = require("moonlift.std")
local Builtins = require("moonlift.builtins")

assert(moonlift.std == Std)
assert(moonlift.json == Std.json)
assert(moonlift.host == Std.host)
assert(moonlift.mlua == Std.mlua)
assert(Builtins == Std.builtins)
assert(type(Builtins.source("json")) == "string")

local src = [[{"id":42,"active":true}]]
local id, id_err = moonlift.json.get_i32(src, "id", { byte_cap = 64, tape_cap = 64, stack_cap = 64 })
assert(id == 42, tostring(id_err))
local active, active_err = moonlift.json.get_bool(src, "active", { byte_cap = 64, tape_cap = 64, stack_cap = 64 })
assert(active == true, tostring(active_err))

local decoded = assert(moonlift.json.decode_project({ { name = "id", type = "i32" }, { name = "active", type = "bool" } }, src))
assert(decoded.id == 42)
assert(decoded.active == true)

local view = assert(moonlift.json.decode_project_view({ { name = "id", type = "i32" }, { name = "active", type = "bool" } }, src))
assert(view.id == 42)
assert(view.active == true)

moonlift.json.free()
print("moonlift std ok")
