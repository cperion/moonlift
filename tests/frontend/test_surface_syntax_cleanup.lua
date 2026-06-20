package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")
local T = pvm.context()
schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local Ty = T.MoonType
local C = T.MoonCore

local function has_issue(report, needle)
    for i = 1, #(report.issues or {}) do
        local msg = tostring(report.issues[i].message or report.issues[i])
        if msg:find(needle, 1, true) then return true end
    end
    return false
end

local array_ty = Parse.parse_type("[i32; 4]")
assert(#array_ty.issues == 0, array_ty.issues[1] and array_ty.issues[1].message)
assert(pvm.classof(array_ty.value) == Ty.TArray)
assert(pvm.classof(array_ty.value.count) == Ty.ArrayLenConst)
assert(array_ty.value.count.count == 4)
assert(pvm.classof(array_ty.value.elem) == Ty.TScalar)
assert(array_ty.value.elem.scalar == C.ScalarI32)

local old_array = Parse.parse_type("[4] i32")
assert(#old_array.issues > 0, "old [N] T array syntax must be rejected")

local arrow_result = Parse.parse_module([[
func old_arrow(): i32 -> i32
    return 0
end
]])
assert(#arrow_result.issues > 0, "arrow result marker must be rejected")

local fn_alias = Parse.parse_type("fn(i32): i32")
assert(has_issue(fn_alias, "function pointer type alias 'fn' was removed; use 'func'"))

local handle_type = Parse.parse_type("handle(Texture, u32)")
assert(has_issue(handle_type, "handle type syntax was removed"))

local func_ty = Parse.parse_type("func(i32): i32")
assert(#func_ty.issues == 0, func_ty.issues[1] and func_ty.issues[1].message)
assert(pvm.classof(func_ty.value) == Ty.TFunc)

print("moonlift surface syntax cleanup ok")
