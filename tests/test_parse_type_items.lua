package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local ModuleType = require("moonlift.tree_module_type")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local MT = ModuleType.Define(T)
local C, Ty, B, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree

local parsed = P.parse_module [[
type Pair = struct
    x: i32
    y: i32
end
type Bits = union
    i: i32
    f: f32
end
type Color = enum
    red
    green
    blue
end
type Result = ok(i32) | err(i32) | none
export func id(x: i32) -> i32
    return x
end
]]
assert(#parsed.issues == 0, tostring(parsed.issues[1]))
local module = parsed.module
assert(#module.items == 5)
assert(pvm.classof(module.items[1].t) == Tr.TypeDeclStruct)
assert(module.items[1].t.fields[1] == Ty.FieldDecl("x", Ty.TScalar(C.ScalarI32)))
assert(pvm.classof(module.items[2].t) == Tr.TypeDeclUnion)
assert(pvm.classof(module.items[3].t) == Tr.TypeDeclEnumSugar)
assert(pvm.classof(module.items[4].t) == Tr.TypeDeclTaggedUnionSugar)
assert(module.items[4].t.variants[1] == Ty.VariantDecl("ok", Ty.TScalar(C.ScalarI32)))
assert(module.items[4].t.variants[3] == Ty.VariantDecl("none", Ty.TScalar(C.ScalarVoid)))
local typed_module = Tr.Module(Tr.ModuleTyped("Demo"), module.items)
local env = MT.env(typed_module)
assert(#env.types == 4)
assert(env.types[1] == B.TypeEntry("Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))))

local braced = P.parse_module [[
type OldPair = struct { x: i32, y: i32 }
]]
assert(#braced.issues >= 1)
assert(braced.issues[1].message:match("keyword...end, not braces"))

print("moonlift parse type items ok")
