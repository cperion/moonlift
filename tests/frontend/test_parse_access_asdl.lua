package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)

local Parse = require("moonlift.parse").Define(T)
local Ty = T.MoonType

local parsed_ty = Parse.parse_type("readonly view(u8)").value
assert(pvm.classof(parsed_ty) == Ty.TAccess)
assert(parsed_ty.access == Ty.TypeAccessReadonly)
assert(pvm.classof(parsed_ty.base) == Ty.TView)

local parsed_region = Parse.parse_module("region r(invalidate c: ptr(i32), readonly bytes: view(u8); ok) end")
assert(#parsed_region.issues == 0)

local parsed_struct = Parse.parse_module("struct Event text: readonly view(u8) end")
assert(#parsed_struct.issues == 0)
local field_ty = parsed_struct.module.items[1].t.fields[1].ty
assert(pvm.classof(field_ty) == Ty.TAccess)
assert(field_ty.access == Ty.TypeAccessReadonly)

local parsed_func = Parse.parse_module("func f(readonly p: ptr(i32), noescape q: ptr(i32)): void end")
assert(#parsed_func.issues == 0)
local params = parsed_func.module.items[1].func.params
assert(pvm.classof(params[1].ty) == Ty.TAccess)
assert(params[1].ty.access == Ty.TypeAccessReadonly)
assert(pvm.classof(params[2].ty) == Ty.TAccess)
assert(params[2].ty.access == Ty.TypeAccessNoEscape)
assert(pvm.classof(params[2].ty.base) == Ty.TLease)

print("moonlift parse access asdl ok")
