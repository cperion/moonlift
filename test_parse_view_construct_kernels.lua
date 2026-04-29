package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local ContractFacts = require("moonlift.tree_contract_facts")
local KernelPlan = require("moonlift.vec_kernel_plan")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local CF = ContractFacts.Define(T)
local KP = KernelPlan.Define(T)
local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.Moon2Back
local C = T.Moon2Core
local Vec = T.Moon2Vec

local src = [[
export func sum_construct_view_scalar(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local func = checked.module.items[1].func
local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, CF.facts(func).facts)
assert(pvm.classof(plan) == Vec.VecKernelReduce)
assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyAssumed)
local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw_vec = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.Moon2Back.CmdLoad and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec then saw_vec = true end
end
assert(saw_vec, "expected constructed view kernel to vectorize")

local artifact = jit_api.jit():compile(program)
local sum = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_construct_view_scalar")))
local xs = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
assert(sum(xs, 0) == 0)
assert(sum(xs, 4) == 10)
assert(sum(xs, 9) == 45)
artifact:free()

print("moonlift parse_view_construct_kernels ok")
