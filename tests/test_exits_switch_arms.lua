package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local exits = moon.exits[[ ok(i32) | err(i64) ]]
assert(exits.kind == "exit_protocol")
assert(#exits.exits == 2)

local U = moon.union{ exits = exits }[[ union Result @{exits...} end ]]
assert(#U.decl.variants == 2)
assert(U.decl.variants[1].name == "ok")
assert(U.decl.variants[2].name == "err")

local R = moon.region{ exits = exits }[[
region parse(x: i32; @{exits...})
entry start()
    jump ok(arg1 = x)
end
end
]]
assert(#R.frag.conts == 2)
assert(R.frag.conts[1].pretty_name == "ok")
assert(R.frag.conts[1].params[1].name == "arg1")

local arms = moon.switch_arms[[
case 34 then return 1
case 91 then return 2
]]
assert(#arms == 2)
assert(arms[1].raw_key == "34")
assert(arms[2].raw_key == "91")

local arms2 = moon.switch_arms { {34, moon.stmts[[ return 1 ]]}, {91, moon.stmts[[ return 2 ]]} }
assert(#arms2 == 2)
assert(arms2[1].raw_key == "34")

local spliced_body = moon.stmts[[ return 7 ]]
local arms3 = moon.switch_arms { spliced_body = spliced_body } [[
case 7 then @{spliced_body...}
]]
assert(#arms3 == 1)
assert(arms3[1].raw_key == "7")
assert(#arms3[1].body == 1)

local pvm = require("moonlift.pvm")
local O = moon.default_session.T.MoonOpen
local emit_done = moon.region[[
region emit_done(; done: cont())
entry start()
    jump done()
end
end
]]
local body = moon.stmts { emit_done = emit_done } [[
    emit @{emit_done}(; done = after)
]]
assert(pvm.classof(body[1].frag) == O.RegionFragRefName)
assert(body[1].frag.name == "emit_done")
assert(body[1].use_id:match("emit_done"))

print("moonlift exits/switch_arms ok")
