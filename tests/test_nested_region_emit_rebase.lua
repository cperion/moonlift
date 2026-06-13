package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

-- Nested region emits can be partially expanded before final compilation when a
-- header/body or dependent region is packed into a function body. Continuation
-- fills that target an imported parent block must be rebased to that imported
-- block label, and jumps to that block must carry the parent's captured runtime
-- parameters.
local child = moon.region [[
child(x: i32; ok(y: i32))
entry start()
    jump ok(y = x + 1)
end
end
]]

local parent = moon.region { child = child } [[
parent(x: i32; ok(y: i32))
entry start()
    emit @{child}(x; ok = got)
end
block got(y: i32)
    jump ok(y = y + 1)
end
end
]]

local run_header = moon.func [[
func run(x: i32): i32
end
]]

local run = run_header { parent = parent } [[
return region: i32
entry start()
    emit @{parent}(x; ok = done)
end
block done(y: i32)
    yield y
end
end
]]

local compiled = run:compile()
assert(compiled(40) == 42)
compiled:free()

return "nested region emit rebase ok"
