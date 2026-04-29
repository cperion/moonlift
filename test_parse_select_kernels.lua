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
local B2 = T.Moon2Back
local C = T.Moon2Core
local Vec = T.Moon2Vec

local src = [[
export func clamp_nonneg_i32(noalias dst: ptr(i32), readonly a: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires disjoint(dst, a)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = select(a[i] < 0, 0, a[i])
        jump loop(i = i + 1)
    end
end

export func max_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = select(a[i] > b[i], a[i], b[i])
        jump loop(i = i + 1)
    end
end

export func min_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = select(a[i] < b[i], a[i], b[i])
        jump loop(i = i + 1)
    end
end

export func in_range_i32(noalias dst: ptr(i32), readonly a: ptr(i32), n: i32, lo: i32, hi: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires disjoint(dst, a)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = select(a[i] >= lo and a[i] <= hi, 1, 0)
        jump loop(i = i + 1)
    end
end

export func nonzero_or_negative_i32(noalias dst: ptr(i32), readonly a: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires disjoint(dst, a)
    block loop(i: i32 = 0)
        if i >= n then
            return 0
        end
        dst[i] = select(not (a[i] == 0) or a[i] < 0, 1, 0)
        jump loop(i = i + 1)
    end
end

export func threshold_view_i32(noalias dst: view(i32), readonly a: view(i32), t: i32, lo: i32, hi: i32) -> i32
    requires same_len(dst, a)
    block loop(i: index = 0)
        if i >= len(dst) then
            return 0
        end
        dst[i] = select(a[i] > t, hi, lo)
        jump loop(i = i + 1)
    end
end

export func max_view_prefix_window_i32(noalias dst: view(i32), readonly a: view(i32), readonly b: view(i32)) -> i32
    requires same_len(dst, a)
    requires same_len(dst, b)
    let m: index = len(dst) - 1
    let wd: view(i32) = view_window(dst, 1, m)
    let wa: view(i32) = view_window(a, 1, m)
    let wb: view(i32) = view_window(b, 1, m)
    block loop(i: index = 0)
        if i >= len(wd) then
            return 0
        end
        wd[i] = select(wa[i] > wb[i], wa[i], wb[i])
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
    local facts = CF.facts(func)
    local plan = KP.plan(func.name, C.VisibilityExport, func.params, func.result, func.body, facts.facts)
    assert(pvm.classof(plan) == Vec.VecKernelMap, "expected vector select map for " .. func.name)
    assert(pvm.classof(plan.safety) == Vec.VecKernelSafetyProven, "expected proven vector safety for " .. func.name)
end

local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)
local saw_cmp, saw_select, saw_mask = false, false, false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == B2.CmdVecCompare then saw_cmp = true end
    if pvm.classof(cmd) == B2.CmdVecSelect then saw_select = true end
    if pvm.classof(cmd) == B2.CmdVecMask then saw_mask = true end
end
assert(saw_cmp, "expected vector compare commands")
assert(saw_select, "expected vector select commands")
assert(saw_mask, "expected vector mask commands")

local artifact = jit_api.jit():compile(program)
local clamp = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("clamp_nonneg_i32")))
local max_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("max_i32")))
local min_u32 = ffi.cast("int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("min_u32")))
local in_range = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("in_range_i32")))
local nonzero_or_negative = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("nonzero_or_negative_i32")))
ffi.cdef[[ typedef struct MoonliftTestViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftTestViewI32; ]]
local threshold = ffi.cast("int32_t (*)(MoonliftTestViewI32*, MoonliftTestViewI32*, int32_t, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("threshold_view_i32")))
local max_window = ffi.cast("int32_t (*)(MoonliftTestViewI32*, MoonliftTestViewI32*, MoonliftTestViewI32*)", artifact:getpointer(B2.BackFuncId("max_view_prefix_window_i32")))

local a = ffi.new("int32_t[9]", { -3, -1, 0, 2, 5, -8, 7, 1, -2 })
local out = ffi.new("int32_t[9]")
assert(clamp(out, a, 9) == 0)
for i = 0, 8 do local expected = a[i] < 0 and 0 or a[i]; assert(out[i] == expected) end

local x = ffi.new("int32_t[9]", { 1, 50, -3, 9, 10, -20, 7, 8, 100 })
local y = ffi.new("int32_t[9]", { 2, 40, -4, 10, 10, -10, 99, 1, -100 })
assert(max_i32(out, x, y, 9) == 0)
for i = 0, 8 do local expected = x[i] > y[i] and x[i] or y[i]; assert(out[i] == expected) end

local ux = ffi.new("uint32_t[9]", { 1, 4000000000, 7, 9, 0, 22, 5, 10, 100 })
local uy = ffi.new("uint32_t[9]", { 2, 3, 8, 1, 0, 11, 6, 9, 99 })
local uout = ffi.new("uint32_t[9]")
assert(min_u32(uout, ux, uy, 9) == 0)
for i = 0, 8 do local expected = ux[i] < uy[i] and ux[i] or uy[i]; assert(uout[i] == expected) end

assert(in_range(out, x, 9, 1, 10) == 0)
for i = 0, 8 do local expected = (x[i] >= 1 and x[i] <= 10) and 1 or 0; assert(out[i] == expected) end
assert(nonzero_or_negative(out, x, 9) == 0)
for i = 0, 8 do local expected = ((not (x[i] == 0)) or x[i] < 0) and 1 or 0; assert(out[i] == expected) end

local out_view = ffi.new("MoonliftTestViewI32[1]", { { out, 9, 1 } })
local x_view = ffi.new("MoonliftTestViewI32[1]", { { x, 9, 1 } })
local y_view = ffi.new("MoonliftTestViewI32[1]", { { y, 9, 1 } })
assert(threshold(out_view, x_view, 8, -1, 1) == 0)
for i = 0, 8 do local expected = x[i] > 8 and 1 or -1; assert(out[i] == expected) end

for i = 0, 8 do out[i] = -999 end
assert(max_window(out_view, x_view, y_view) == 0)
assert(out[0] == -999)
for i = 1, 8 do local expected = x[i] > y[i] and x[i] or y[i]; assert(out[i] == expected) end

artifact:free()

print("moonlift parse_select_kernels ok")
