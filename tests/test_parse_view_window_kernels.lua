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
local C = T.MoonCore
local Vec = T.MoonVec
local B2 = T.MoonBack

local src = [[
export func sum_full_window_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, 0, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_window_i32(xs: ptr(i32), n: index, start: index, m: index) -> i32
    requires bounds(xs, n)
    requires window_bounds(xs, n, start, m)
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, start, m)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_prefix_shrink_window_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let m: index = n - 1
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, 1, m)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_alias_shrink_window_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let s: index = 2
    let m: index = n - s
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, s, m)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_suffix_shrink_window_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let m: index = n - 3
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, 0, m)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w) then yield acc end
        jump loop(i = i + 1, acc = acc + w[i])
    end
end

export func sum_nested_window_i32(xs: ptr(i32), n: index) -> i32
    requires bounds(xs, n)
    let m1: index = n - 1
    let v: view(i32) = view(xs, n)
    let w1: view(i32) = view_window(v, 1, m1)
    let m2: index = m1 - 1
    let w2: view(i32) = view_window(w1, 1, m2)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(w2) then yield acc end
        jump loop(i = i + 1, acc = acc + w2[i])
    end
end

export func add_window_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index, start: index, m: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires window_bounds(dst, n, start, m)
    requires window_bounds(a, n, start, m)
    requires window_bounds(b, n, start, m)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd0: view(i32) = view(dst, n)
    let va0: view(i32) = view(a, n)
    let vb0: view(i32) = view(b, n)
    let vd: view(i32) = view_window(vd0, start, m)
    let va: view(i32) = view_window(va0, start, m)
    let vb: view(i32) = view_window(vb0, start, m)
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
    local contracts = CF.facts(func).facts
    local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, contracts)
    assert(pvm.classof(plan) == ((func.name == "sum_window_i32" or func.name == "sum_full_window_i32" or func.name == "sum_prefix_shrink_window_i32" or func.name == "sum_alias_shrink_window_i32" or func.name == "sum_suffix_shrink_window_i32" or func.name == "sum_nested_window_i32") and Vec.VecKernelReduce or Vec.VecKernelMap))
    assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven)
end

local program = Lowerer.module(checked.module)
local report = Vd.validate(program)
assert(#report.issues == 0)
local artifact = jit_api.jit():compile(program)
local sum_full = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_full_window_i32")))
local sum = ffi.cast("int32_t (*)(const int32_t*, intptr_t, intptr_t, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_window_i32")))
local sum_shrink = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_prefix_shrink_window_i32")))
local sum_alias_shrink = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_alias_shrink_window_i32")))
local sum_suffix_shrink = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_suffix_shrink_window_i32")))
local sum_nested = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("sum_nested_window_i32")))
local add = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t, intptr_t, intptr_t)", artifact:getpointer(B2.BackFuncId("add_window_i32")))
local xs = ffi.new("int32_t[16]", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 })
assert(sum_full(xs, 16) == 136)
assert(sum(xs, 16, 3, 8) == 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11)
assert(sum_shrink(xs, 16) == 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16)
assert(sum_alias_shrink(xs, 16) == 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16)
assert(sum_suffix_shrink(xs, 16) == 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13)
assert(sum_nested(xs, 16) == 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16)
local a = ffi.new("int32_t[16]", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 })
local b = ffi.new("int32_t[16]", { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160 })
local dst = ffi.new("int32_t[16]", {})
assert(add(dst, a, b, 16, 4, 7) == 0)
for i = 0, 15 do
    if i >= 4 and i < 11 then assert(dst[i] == a[i] + b[i]) else assert(dst[i] == 0) end
end
artifact:free()

print("moonlift parse_view_window_kernels ok")
