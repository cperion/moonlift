package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

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
export func sum_view_i32(xs: view(i32)) -> i32
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(xs) then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
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
assert(pvm.classof(plan.counter) == Vec.VecKernelCounterIndex)
assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven)

local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
assert(program.cmds[1].params[1] == T.Moon2Back.BackPtr)
assert(program.cmds[1].params[2] == T.Moon2Back.BackIndex)
assert(program.cmds[1].params[3] == T.Moon2Back.BackIndex)
local saw_vec = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.Moon2Back.CmdLoadInfo and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec then saw_vec = true end
end
assert(saw_vec, "expected vector load for view sum")

ffi.cdef[[ typedef struct MoonliftTestViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftTestViewI32; ]]
local artifact = jit_api.jit():compile(program)
local sum = ffi.cast("int32_t (*)(MoonliftTestViewI32*)", artifact:getpointer(B2.BackFuncId("sum_view_i32")))
local xs = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local view = ffi.new("MoonliftTestViewI32[1]")
view[0].data = xs
view[0].stride = 1
view[0].len = 0
assert(sum(view) == 0)
view[0].len = 4
assert(sum(view) == 10)
view[0].len = 9
assert(sum(view) == 45)
artifact:free()

print("moonlift parse_view_kernels ok")
