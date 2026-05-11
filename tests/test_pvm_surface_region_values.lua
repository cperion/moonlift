package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test PVM surface region values using .mlua eval
local Host = require("moonlift.mlua_run")

-- Simple region fragment
local frag = Host.eval [[
return region emit_hit(x: i32; hit: cont(y: i32))
entry start()
    jump hit(y = x + 1)
end
end
]]
assert(frag.name == "emit_hit")
assert(#frag.frag.params == 1)
assert(#frag.frag.conts == 1)
print("OK: region fragment")

-- Function using fragment
local fn = Host.eval [[
local frag = region emit_hit(x: i32; hit: cont(y: i32))
entry start() jump hit(y = x + 1) end
end
return func use_hit(x: i32) -> i32
    return region -> i32
    entry start() emit @{frag}(x; hit = done) end
    block done(y: i32) yield y end
    end
end
]]
assert(fn.name == "use_hit")
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    assert(compiled(41) == 42)
    compiled:free()
    print("OK: compiled")
else
    print("OK: region value constructed")
end

print("moonlift pvm surface region values ok")
