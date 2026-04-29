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
local B2 = T.MoonBack
local C = T.MoonCore
local Vec = T.MoonVec
local Tr = T.MoonTree

local src = [[
export func add_view_i32(noalias dst: view(i32), readonly a: view(i32), readonly b: view(i32)) -> i32
    requires same_len(dst, a)
    requires same_len(dst, b)
    block loop(i: index = 0)
        if i >= len(dst) then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func copy_view_i32(noalias dst: view(i32), readonly src: view(i32)) -> i32
    requires same_len(dst, src)
    block loop(i: index = 0)
        if i >= len(dst) then
            return 0
        end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local func = checked.module.items[1].func
local copy_func = checked.module.items[2].func
local facts = CF.facts(func)
local copy_facts = CF.facts(copy_func)
local same_len = 0
for i = 1, #facts.facts do if pvm.classof(facts.facts[i]) == Tr.ContractFactSameLen then same_len = same_len + 1 end end
assert(same_len == 2)
local copy_same_len = 0
for i = 1, #copy_facts.facts do if pvm.classof(copy_facts.facts[i]) == Tr.ContractFactSameLen then copy_same_len = copy_same_len + 1 end end
assert(copy_same_len == 1)
local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, facts.facts)
local copy_plan = KP.plan(copy_func.name, C.VisibilityExport, copy_func.params, copy_func.result, copy_func.body, copy_facts.facts)
assert(pvm.classof(plan) == Vec.VecKernelMap)
assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven)
assert(pvm.classof(copy_plan) == Vec.VecKernelMap)
assert(pvm.classof(copy_plan.safety) == Vec.VecKernelSafetyProven)

local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw_vec_add = false
local saw_vec_store = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.MoonBack.CmdVecBinary and cmd.op == T.MoonBack.BackVecIntAdd then saw_vec_add = true end
    if pvm.classof(cmd) == T.MoonBack.CmdStoreInfo and pvm.classof(cmd.ty) == T.MoonBack.BackShapeVec then saw_vec_store = true end
end
assert(saw_vec_add, "expected vector add for view map")
assert(saw_vec_store, "expected vector store for view maps")

ffi.cdef[[ typedef struct MoonliftTestViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftTestViewI32; ]]
local artifact = jit_api.jit():compile(program)
local add = ffi.cast("int32_t (*)(MoonliftTestViewI32*, MoonliftTestViewI32*, MoonliftTestViewI32*)", artifact:getpointer(B2.BackFuncId("add_view_i32")))
local copy = ffi.cast("int32_t (*)(MoonliftTestViewI32*, MoonliftTestViewI32*)", artifact:getpointer(B2.BackFuncId("copy_view_i32")))
local a = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local b = ffi.new("int32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local out = ffi.new("int32_t[9]")
local av = ffi.new("MoonliftTestViewI32[1]", { { a, 9, 1 } })
local bv = ffi.new("MoonliftTestViewI32[1]", { { b, 9, 1 } })
local ov = ffi.new("MoonliftTestViewI32[1]", { { out, 9, 1 } })
assert(add(ov, av, bv) == 0)
for i = 0, 8 do assert(out[i] == a[i] + b[i]) end
assert(copy(ov, av) == 0)
for i = 0, 8 do assert(out[i] == a[i]) end
artifact:free()

print("moonlift parse_view_map_kernels ok")
