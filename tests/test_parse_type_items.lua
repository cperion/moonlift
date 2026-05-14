package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test that struct and union islands produce correct type declarations
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local Parse = require("moonlift.parse")
local P = Parse.Define(T)

-- Struct type island
local scan1 = Parse.scan_document("local P = struct Pair x: i32; y: i32 end")
assert(#scan1.islands == 1)
assert(scan1.islands[1].kind == "struct")
local parsed1 = P.parse_island(scan1, 1)
assert(#parsed1.issues == 0)
assert(parsed1.value.name == "Pair")
assert(parsed1.value.decl ~= nil)
assert(parsed1.value.protocol_variants == nil)
print("OK: struct island parsed")

-- Union type island
local scan2 = Parse.scan_document("local R = union ok(i32) | err(string) | none end")
assert(#scan2.islands == 1)
assert(scan2.islands[1].kind == "union")
local parsed2 = P.parse_island(scan2, 1)
assert(#parsed2.issues == 0)
assert(parsed2.value.name == "R")
assert(parsed2.value.protocol_variants ~= nil)
assert(#parsed2.value.protocol_variants == 3)
print("OK: union island parsed")
assert(parsed2.value.protocol_variants[1].name == "ok")
assert(parsed2.value.protocol_variants[3].name == "none")
print("OK: union variants correct")

-- old/io pattern: region protocol using union
local T3 = pvm.context(); A.Define(T3)
local P3 = Parse.Define(T3)
local src3 = [[
local R = union ok(i32) | err(string) end
local r = region(s: ptr(i32); ok: cont(v: i32), err: cont(msg: ptr(u8)))
entry start()
    if *s >= 0 then jump ok(v = *s) else jump err(msg = "negative") end
end
end
return r
]]
local scan3 = Parse.scan_document(src3)
assert(#scan3.islands == 2)
assert(scan3.islands[1].kind == "union")
assert(scan3.islands[2].kind == "region")

-- Parse union first with protocol_types tracking
local parsed3_union = P3.parse_island(scan3, 1, {})
assert(#parsed3_union.issues == 0)
local parsed3_region = P3.parse_island(scan3, 2, { protocol_types = parsed3_union.protocol_types })
assert(#parsed3_region.issues == 0)
print("OK: union protocol types propagate to region fragments")

print("\nmoonlift parse type items ok")
