package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local MluaParse = require("moonlift.mlua_parse")
local Parse = require("moonlift.parse")

local T = pvm.context()
A.Define(T)
local MP = MluaParse.Define(T)
local P = Parse.Define(T)
local C, Ty, Tr = T.MoonCore, T.MoonType, T.MoonTree

local parsed_type = P.parse_module [[
type Scanner = hit(pos: i32) | miss(pos: i32)
]]
assert(#parsed_type.issues == 0, tostring(parsed_type.issues[1]))
local scanner = parsed_type.module.items[1].t
assert(pvm.classof(scanner) == Tr.TypeDeclTaggedUnionSugar)
assert(scanner.variants[1] == Ty.VariantDecl("hit", Ty.TScalar(C.ScalarI32), { Ty.FieldDecl("pos", Ty.TScalar(C.ScalarI32)) }))

local src = [[
type Scanner = hit(pos: i32) | miss(pos: i32)

region scan_until(p: ptr(u8), n: i32, target: i32) -> Scanner
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
]]

local result = MP.parse(src, "protocol_syntax.mlua")
assert(#result.issues == 0, tostring(result.issues[1]))
assert(#result.module.items == 1)
assert(#result.region_frags == 1)
local frag = result.region_frags[1]
assert(#frag.conts == 2)
assert(frag.conts[1].pretty_name == "hit")
assert(frag.conts[1].params[1].name == "pos")
assert(frag.conts[1].params[1].ty == Ty.TScalar(C.ScalarI32))
assert(frag.conts[2].pretty_name == "miss")

local bad = MP.parse([[type Bad = ok(i32)
region r() -> Bad
entry start()
    jump ok(value = 1)
end
end
]], "bad_protocol.mlua")
assert(#bad.issues >= 1)
assert(bad.issues[1].message:match("named fields"))

print("moonlift protocol syntax ok")
