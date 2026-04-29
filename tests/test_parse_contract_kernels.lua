package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.MoonBack

local src = [[
export func add_noalias_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)

local saw_vec = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.MoonBack.CmdVecBinary and cmd.op == T.MoonBack.BackVecIntAdd then saw_vec = true end
end
assert(saw_vec, "expected contract kernel to vectorize")

local artifact = jit_api.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_noalias_i32")))
local a = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local b = ffi.new("int32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local out = ffi.new("int32_t[9]")
assert(add(out, a, b, 9) == 0)
for i = 0, 8 do assert(out[i] == a[i] + b[i]) end
artifact:free()

print("moonlift parse_contract_kernels ok")
