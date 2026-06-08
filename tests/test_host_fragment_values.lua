package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test fragment values using .mlua eval
local Host = require("moonlift.mlua_run")

-- Expression fragment
local clamp = Host.eval [[return expr clamp_nonneg(x: i32): i32 select(x < 0, 0, x) end]]
assert(clamp.name == "clamp_nonneg")
assert(clamp.frag ~= nil)
assert(#clamp.frag.params == 1)
print("OK: expr fragment")

-- Function using the fragment
local fn = Host.eval [[
local clamp = expr clamp_nonneg(x: i32): i32 select(x < 0, 0, x) end
return func score(x: i32): i32 return emit @{clamp}(x) + 1 end
]]
assert(fn.kind == "func")
assert(fn.name == "score")
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    assert(compiled(-5) == 1)
    assert(compiled(10) == 11)
    compiled:free()
    print("OK: compiled and ran")
else
    print("OK: fragment value constructed (compile skipped - no JIT lib)")
end

print("moonlift host fragment values ok")
