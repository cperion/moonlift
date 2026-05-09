package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

-- Lua-style module tables: a module island returns a sealed table of typed
-- compile-time fields, and qualified fields inside later islands become static
-- slots rather than runtime Lua lookups.
local m = Host.eval [[
local dep = module "test.dep"
const K: i32 = 41
type Pair = struct
    a: i32
end
end

local main = module "test.main"
export func answer() -> i32
    return dep.K + 1
end
export func accepts_dep_type(p: ptr(dep.Pair)) -> i32
    return 7
end
end
return main
]]

local c = m:compile()
assert(c:get("answer")() == 42)
c:free()

-- moon.require loads and caches .mlua modules by Lua-style path and makes their
-- exported fields available as module-table values.
local req = Host.eval [[
local value = moon.require("luajitvm.core.value")
local main = module "test.require.value"
export func check_const() -> i32
    return value.LUA_TINT
end
export func check_call() -> i32
    return value.value_const_check()
end
end
return main
]]

local rc = req:compile()
assert(rc:get("check_const")() == 3)
assert(rc:get("check_call")() == 44)
rc:free()

print("mlua module tables ok")
