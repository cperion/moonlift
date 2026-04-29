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
local Vd = Validate.Define(T)
local jit_api = J.Define(T)
local C = T.Moon2Core
local Vec = T.Moon2Vec
local B2 = T.Moon2Back

local src = [[
export func sum_view_full_window_i32(xs: view(i32)) -> i32
    let n: index = len(xs)
    let w: view(i32) = view_window(xs, 0, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_view_prefix_window_i32(xs: view(i32)) -> i32
    let m: index = len(xs) - 1
    let w: view(i32) = view_window(xs, 1, m)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_view_nested_window_i32(xs: view(i32)) -> i32
    let m1: index = len(xs) - 1
    let w1: view(i32) = view_window(xs, 1, m1)
    let m2: index = m1 - 1
    let w2: view(i32) = view_window(w1, 1, m2)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w2) then yield acc end
        jump loop(i = i + 1, acc = acc + w2[i])
    end
end

export func add_view_window_i32(noalias dst: view(i32), readonly a: view(i32), readonly b: view(i32)) -> i32
    requires same_len(dst, a)
    requires same_len(dst, b)
    let n: index = len(dst)
    let m: index = n - 1
    let vd: view(i32) = view_window(dst, 1, m)
    let va: view(i32) = view_window(a, 1, m)
    let vb: view(i32) = view_window(b, 1, m)
    block loop(i: index = 0)
        if i >= len(vd) then return 0 end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)

for i = 1, #checked.module.items do
    local func = checked.module.items[i].func
    local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, CF.facts(func).facts)
    assert(pvm.classof(plan) == (func.name == "add_view_window_i32" and Vec.VecKernelMap or Vec.VecKernelReduce))
    assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven)
end

local program = Lowerer.module(checked.module)
local report = Vd.validate(program)
assert(#report.issues == 0)
local artifact = jit_api.jit():compile(program)
local sum_full = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_view_full_window_i32")))
local sum_prefix = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_view_prefix_window_i32")))
local sum_nested = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_view_nested_window_i32")))
local add = ffi.cast("int32_t (*)(int32_t*, intptr_t, const int32_t*, intptr_t, const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("add_view_window_i32")))
local xs = ffi.new("int32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
assert(sum_full(xs, 8) == 36)
assert(sum_prefix(xs, 8) == 2 + 3 + 4 + 5 + 6 + 7 + 8)
assert(sum_nested(xs, 8) == 3 + 4 + 5 + 6 + 7 + 8)
local dst = ffi.new("int32_t[8]", {})
local a = ffi.new("int32_t[8]", { 1, 2, 3, 4, 5, 6, 7, 8 })
local b = ffi.new("int32_t[8]", { 10, 20, 30, 40, 50, 60, 70, 80 })
assert(add(dst, 8, a, 8, b, 8) == 0)
assert(dst[0] == 0)
for i = 1, 7 do assert(dst[i] == a[i] + b[i]) end
artifact:free()

print("moonlift parse_view_param_window_kernels ok")
