package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Run = require("moonlift.mlua_run")

local function run_src(name, src)
    local path = "/tmp/" .. name .. ".mlua"
    local f = assert(io.open(path, "w"))
    f:write(src)
    f:close()
    return Run.dofile(path)
end

local semicolon_compact = [[
local m = module "stabilization.semicolon"
const A: i32 = 1; const B: i32 = 2
export func sentinel() -> i32 return A + B end
end
local c = m:compile()
local v = c:get("sentinel")()
c:free()
return v
]]
assert(run_src("moonlift_stabilization_semicolon", semicolon_compact) == 3)

local parts = { 'local m = module "stabilization.large"\n' }
for i = 1, 64 do
    parts[#parts + 1] = string.format('export func f%d() -> i32 return %d end\n', i, i)
end
parts[#parts + 1] = [[
end
local c = m:compile()
local v = c:get("f64")()
c:free()
return v
]]
assert(run_src("moonlift_stabilization_large", table.concat(parts)) == 64)

local nested_switch_region = [[
local m = module "stabilization.switch_region"
region R(op: i32; ok: cont(v: i32), fail: cont())
entry start()
    switch op do
    case 1 then
        if op == 1 then
            jump ok(v = 1)
        else
            jump fail()
        end
    default then
        jump fail()
    end
end
end
end
return "nested switch region ok"
]]
assert(run_src("moonlift_stabilization_nested_switch", nested_switch_region) == "nested switch region ok")

print("mlua_stabilization ok")
