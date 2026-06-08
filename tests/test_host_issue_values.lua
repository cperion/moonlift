package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test host issue values
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local H = T.MoonHost

-- Standalone issue construction
local issue = H.HostIssueDuplicateType("Demo", "Pair")
local report = H.HostReport({ issue })
assert(pvm.classof(report) == H.HostReport)
assert(#report.issues == 1)
assert(report.issues[1] == issue)
print("OK: host issue construction")

-- Region fragment via .mlua eval
local Host = require("moonlift.mlua_run")
local fn = Host.eval [[
local frag = region needs_out(x: i32; out: cont(y: i32))
entry start() jump out(y = x + 1) end
end
return func f(): i32
    return region: i32
    entry start() emit @{frag}(41; out = done) end
    block done(y: i32) yield y end
    end
end
]]
assert(fn.name == "f")
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    assert(compiled() == 42)
    compiled:free()
    print("OK: compiled")
else
    print("OK: region value constructed")
end

print("moonlift host issue values ok")
