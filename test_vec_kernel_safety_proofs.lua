package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local ContractFacts = require("moonlift.tree_contract_facts")
local KernelPlan = require("moonlift.vec_kernel_plan")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local CF = ContractFacts.Define(T)
local KP = KernelPlan.Define(T)
local C = T.Moon2Core
local Tr = T.Moon2Tree
local V = T.Moon2Vec

local src = [[
export func add_raw_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

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

local raw = checked.module.items[1].func
local proven = checked.module.items[2].func
local raw_plan = KP.plan(raw.name, C.VisibilityExport, raw.params, raw.result, raw.body, CF.facts(raw).facts)
local proven_plan = KP.plan(proven.name, C.VisibilityExport, proven.params, proven.result, proven.body, CF.facts(proven).facts)
assert(pvm.classof(raw_plan) == V.VecKernelMap)
assert(pvm.classof(proven_plan) == V.VecKernelMap)
assert(pvm.classof(raw_plan.safety) == V.VecKernelSafetyAssumed)
assert(pvm.classof(proven_plan.safety) == V.VecKernelSafetyProven)

print("moonlift vec_kernel_safety_proofs ok")
