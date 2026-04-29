package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Plan = require("moonlift.vec_kernel_plan")
local ToBack = require("moonlift.vec_kernel_to_back")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local KP = Plan.Define(T)
local TB = ToBack.Define(T)
local V = Validate.Define(T)
local J = Jit.Define(T)
local Vec = T.MoonVec
local Core = T.MoonCore
local Back = T.MoonBack
local Tree = T.MoonTree

local src = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func fill_i32(xs: ptr(i32), n: i32, value: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        xs[i] = value
        jump loop(i = i + 1)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local func = checked.module.items[1].func
local fill_func = checked.module.items[2].func
local plan = KP.plan(func.name, Core.VisibilityExport, func.params, func.result, func.body)
assert(pvm.classof(plan) == Vec.VecKernelReduce)
assert(pvm.classof(plan.decision.schedule) == Vec.VecScheduleVector)

local old_schedule = plan.decision.schedule
local proofs = old_schedule.proofs
local reduction_schedule = Vec.VecReductionSchedule(plan.reduction.op, 2, proofs)
local schedule = Vec.VecScheduleVector(old_schedule.shape, 1, 1, old_schedule.tail, 2, { reduction_schedule }, proofs)
local decision = pvm.with(plan.decision, { schedule = schedule })
local scheduled_plan = pvm.with(plan, { decision = decision })

local lowered = TB.lower_func(func.name, Core.VisibilityExport, func.params, func.result, scheduled_plan)
assert(pvm.classof(lowered) == Tree.TreeBackFuncResult)
local cmds = {}
for i = 1, #lowered.cmds do cmds[#cmds + 1] = lowered.cmds[i] end
cmds[#cmds + 1] = Back.CmdFinalizeModule
local program = Back.BackProgram(cmds)
local report = V.validate(program)
assert(#report.issues == 0)

local saw_stride_8 = false
local vector_loads = 0
for i = 1, #cmds do
    local cmd = cmds[i]
    if pvm.classof(cmd) == Back.CmdConst and cmd.dst == Back.BackValId("vec:sum_i32:stride") and cmd.value.raw == "8" then saw_stride_8 = true end
    if pvm.classof(cmd) == Back.CmdLoadInfo and pvm.classof(cmd.ty) == Back.BackShapeVec then vector_loads = vector_loads + 1 end
end
assert(saw_stride_8, "expected two-accumulator i32x4 schedule to step by 8 elements")
assert(vector_loads >= 2, "expected one vector load per accumulator in the loop body")

local artifact = J.jit():compile(program)
local sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(Back.BackFuncId("sum_i32")))
local xs = ffi.new("int32_t[11]", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
assert(sum_i32(xs, 0) == 0)
assert(sum_i32(xs, 4) == 10)
assert(sum_i32(xs, 8) == 36)
assert(sum_i32(xs, 11) == 66)
artifact:free()

local fill_plan = KP.plan(fill_func.name, Core.VisibilityExport, fill_func.params, fill_func.result, fill_func.body)
assert(pvm.classof(fill_plan) == Vec.VecKernelMap)
local fill_old = fill_plan.decision.schedule
local fill_schedule = Vec.VecScheduleVector(fill_old.shape, 2, 1, fill_old.tail, 1, {}, fill_old.proofs)
local fill_decision = pvm.with(fill_plan.decision, { schedule = fill_schedule })
local scheduled_fill = pvm.with(fill_plan, { decision = fill_decision })
local fill_lowered = TB.lower_func(fill_func.name, Core.VisibilityExport, fill_func.params, fill_func.result, scheduled_fill)
assert(pvm.classof(fill_lowered) == Tree.TreeBackFuncResult)
local fill_cmds = {}
for i = 1, #fill_lowered.cmds do fill_cmds[#fill_cmds + 1] = fill_lowered.cmds[i] end
fill_cmds[#fill_cmds + 1] = Back.CmdFinalizeModule
local fill_program = Back.BackProgram(fill_cmds)
local fill_report = V.validate(fill_program)
assert(#fill_report.issues == 0)
local saw_fill_stride_8 = false
local fill_vec_stores = 0
for i = 1, #fill_cmds do
    local cmd = fill_cmds[i]
    if pvm.classof(cmd) == Back.CmdConst and cmd.dst == Back.BackValId("vec:fill_i32:stride") and cmd.value.raw == "8" then saw_fill_stride_8 = true end
    if pvm.classof(cmd) == Back.CmdStoreInfo and pvm.classof(cmd.ty) == Back.BackShapeVec then fill_vec_stores = fill_vec_stores + 1 end
end
assert(saw_fill_stride_8, "expected unrolled i32x4 map schedule to step by 8 elements")
assert(fill_vec_stores >= 2, "expected one vector store per unrolled map group")
local fill_artifact = J.jit():compile(fill_program)
local fill_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t, int32_t)", fill_artifact:getpointer(Back.BackFuncId("fill_i32")))
local ys = ffi.new("int32_t[11]")
assert(fill_i32(ys, 11, 42) == 0)
for i = 0, 10 do assert(ys[i] == 42) end
fill_artifact:free()

print("moonlift vec_kernel_schedule_to_back ok")
