package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local T = moon.T
local C, Ty = T.Moon2Core, T.Moon2Type

assert(moon.i32.ty == Ty.TScalar(C.ScalarI32))
assert(moon.bool.ty == Ty.TScalar(C.ScalarBool))

local p_i32 = moon.ptr(moon.i32)
assert(pvm.classof(p_i32.ty) == Ty.TPtr)
assert(p_i32.ty.elem == moon.i32.ty)
assert(p_i32.pointee == moon.i32)
assert(p_i32:moonlift_splice_source() == "ptr(i32)")

local v_i32 = moon.view(moon.i32)
assert(pvm.classof(v_i32.ty) == Ty.TView)
assert(v_i32.element == moon.i32)

local a4 = moon.array(4, moon.u8)
assert(pvm.classof(a4.ty) == Ty.TArray)
assert(a4.ty.count == Ty.ArrayLenConst(4))
assert(a4.element == moon.u8)

local fn = moon.func_type({ moon.i32, moon.i32 }, moon.i32)
assert(pvm.classof(fn.ty) == Ty.TFunc)
assert(#fn.ty.params == 2)
assert(fn.ty.result == moon.i32.ty)

local named = moon.named("Demo", "Pair")
assert(named.ty == Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))

local s = moon.new_session({ prefix = "test" })
local h = s:api()
assert(h.i64.ty == h.T.Moon2Type.TScalar(h.T.Moon2Core.ScalarI64))

print("moonlift host type values ok")
