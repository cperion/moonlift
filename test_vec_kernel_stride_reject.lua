package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

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
local Vec = T.Moon2Vec

local src = [[
export func sum_stride1(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n, 1)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func sum_stride2(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n, 2)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func sum_window(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, 1, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local stride1 = checked.module.items[1].func
local stride2 = checked.module.items[2].func
local window = checked.module.items[3].func
local plan1 = KP.plan(stride1.name, C.VisibilityExport, stride1.params, stride1.result, stride1.body, CF.facts(stride1).facts)
local plan2 = KP.plan(stride2.name, C.VisibilityExport, stride2.params, stride2.result, stride2.body, CF.facts(stride2).facts)
local plan3 = KP.plan(window.name, C.VisibilityExport, window.params, window.result, window.body, CF.facts(window).facts)
assert(pvm.classof(plan1) == Vec.VecKernelReduce)
assert(pvm.classof(plan1.safety) == Vec.VecKernelSafetyProven)
assert(pvm.classof(plan2) == Vec.VecKernelNoPlan)
assert(#plan2.rejects == 1)
assert(pvm.classof(plan2.rejects[1]) == Vec.VecRejectUnsupportedMemory)
assert(plan2.rejects[1].reason:find("non%-unit", 1) ~= nil)
assert(pvm.classof(plan3) == Vec.VecKernelReduce)
assert(pvm.classof(plan3.safety) == Vec.VecKernelSafetyRejected)
assert(#plan3.safety.rejects == 1)
assert(pvm.classof(plan3.safety.rejects[1]) == Vec.VecRejectUnsupportedMemory)
assert(plan3.safety.rejects[1].reason:find("window_bounds", 1) ~= nil)

print("moonlift vec_kernel_stride_reject ok")
