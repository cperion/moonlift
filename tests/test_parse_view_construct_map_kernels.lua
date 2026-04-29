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
export func add_construct_view_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i32) = view(dst, n)
    let va: view(i32) = view(a, n)
    let vb: view(i32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then
            return 0
        end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func copy_construct_view_i32(noalias dst: ptr(i32), readonly src: ptr(i32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    let vd: view(i32) = view(dst, n)
    let vs: view(i32) = view(src, n)
    block loop(i: index = 0)
        if i >= len(vd) then
            return 0
        end
        vd[i] = vs[i]
        jump loop(i = i + 1)
    end
end

export func add_construct_view_i64(noalias dst: ptr(i64), readonly a: ptr(i64), readonly b: ptr(i64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(i64) = view(dst, n)
    let va: view(i64) = view(a, n)
    let vb: view(i64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then
            return 0
        end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func add_construct_view_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u32) = view(dst, n)
    let va: view(u32) = view(a, n)
    let vb: view(u32) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then
            return 0
        end
        vd[i] = va[i] + vb[i]
        jump loop(i = i + 1)
    end
end

export func add_construct_view_u64(noalias dst: ptr(u64), readonly a: ptr(u64), readonly b: ptr(u64), n: index) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    let vd: view(u64) = view(dst, n)
    let va: view(u64) = view(a, n)
    let vb: view(u64) = view(b, n)
    block loop(i: index = 0)
        if i >= len(vd) then
            return 0
        end
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
    assert(pvm.classof(plan) == Vec.VecKernelMap, func.name)
    assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven, func.name)
end
local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw_vec_add = false
local saw_i64x2 = false
local saw_u64x2 = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.Moon2Back.CmdVecBinary and cmd.op == T.Moon2Back.BackVecIntAdd then saw_vec_add = true end
    if pvm.classof(cmd) == T.Moon2Back.CmdLoadInfo and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec and cmd.ty.vec.elem == T.Moon2Back.BackI64 and cmd.ty.vec.lanes == 2 then saw_i64x2 = true end
    if pvm.classof(cmd) == T.Moon2Back.CmdLoadInfo and pvm.classof(cmd.ty) == T.Moon2Back.BackShapeVec and cmd.ty.vec.elem == T.Moon2Back.BackU64 and cmd.ty.vec.lanes == 2 then saw_u64x2 = true end
end
assert(saw_vec_add, "expected constructed view map to vectorize")
assert(saw_i64x2, "expected constructed i64 view map to vectorize")
assert(saw_u64x2, "expected constructed u64 view map to vectorize")

local artifact = jit_api.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("add_construct_view_i32")))
local copy = ffi.cast("int32_t (*)(int32_t*, const int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("copy_construct_view_i32")))
local add64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("add_construct_view_i64")))
local addu32 = ffi.cast("int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("add_construct_view_u32")))
local addu64 = ffi.cast("int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("add_construct_view_u64")))
local a = ffi.new("int32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local b = ffi.new("int32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local out = ffi.new("int32_t[9]")
assert(add(out, a, b, 9) == 0)
for i = 0, 8 do assert(out[i] == a[i] + b[i]) end
assert(copy(out, a, 9) == 0)
for i = 0, 8 do assert(out[i] == a[i]) end
local a64 = ffi.new("int64_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local b64 = ffi.new("int64_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local out64 = ffi.new("int64_t[9]")
assert(add64(out64, a64, b64, 9) == 0)
for i = 0, 8 do assert(tonumber(out64[i]) == tonumber(a64[i] + b64[i])) end
local au32 = ffi.new("uint32_t[9]", { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
local bu32 = ffi.new("uint32_t[9]", { 10, 20, 30, 40, 50, 60, 70, 80, 90 })
local outu32 = ffi.new("uint32_t[9]")
assert(addu32(outu32, au32, bu32, 9) == 0)
for i = 0, 8 do assert(tonumber(outu32[i]) == tonumber(au32[i] + bu32[i])) end
local outu64 = ffi.new("uint64_t[9]")
assert(addu64(outu64, ffi.cast("const uint64_t*", a64), ffi.cast("const uint64_t*", b64), 9) == 0)
for i = 0, 8 do assert(tonumber(outu64[i]) == tonumber(a64[i] + b64[i])) end
artifact:free()

print("moonlift parse_view_construct_map_kernels ok")
