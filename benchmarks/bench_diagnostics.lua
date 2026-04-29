-- Diagnostics for the benchmark kernels.
-- Prints schedule, backend fact summaries, command counts, and optional disassembly.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local KernelPlan = require("moonlift.vec_kernel_plan")
local BackInspect = require("moonlift.back_inspect")
local BackDiagnostics = require("moonlift.back_diagnostics")

local SRC = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end
]]

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local KP = KernelPlan.Define(T)
local BI = BackInspect.Define(T)
local BD = BackDiagnostics.Define(T)
local B = T.MoonBack
local Vec = T.MoonVec
local Core = T.MoonCore

local parsed = P.parse_module(SRC)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)

local decisions = {}
for i = 1, #checked.module.items do
    local item = checked.module.items[i]
    local func = item.func
    local plan = KP.plan(func.name, Core.VisibilityExport, func.params, func.result, func.body)
    if pvm.classof(plan) == Vec.VecKernelReduce or pvm.classof(plan) == Vec.VecKernelMap then
        decisions[#decisions + 1] = plan.decision
        local sched = plan.decision.schedule
        if pvm.classof(sched) == Vec.VecScheduleVector then
            io.write(string.format("schedule %-10s elem=%s lanes=%d unroll=%d interleave=%d accumulators=%d tail=%s\n",
                func.name,
                sched.shape.elem.kind,
                sched.shape.lanes,
                sched.unroll,
                sched.interleave,
                sched.accumulators,
                sched.tail.kind))
        end
    end
end

local inspection = BI.inspect(program)
for i = 1, #inspection.command_counts do
    local c = inspection.command_counts[i]
    io.write(string.format("cmd %-24s %d\n", c.command_kind, c.count))
end

local align, deref, traps = {}, {}, {}
for i = 1, #inspection.memory do
    local m = inspection.memory[i]
    align[m.alignment.kind] = (align[m.alignment.kind] or 0) + 1
    deref[m.dereference.kind] = (deref[m.dereference.kind] or 0) + 1
    traps[m.trap.kind] = (traps[m.trap.kind] or 0) + 1
end
for k, v in pairs(align) do io.write(string.format("memory_alignment %-20s %d\n", k, v)) end
for k, v in pairs(deref) do io.write(string.format("memory_dereference %-18s %d\n", k, v)) end
for k, v in pairs(traps) do io.write(string.format("memory_trap %-25s %d\n", k, v)) end
io.write(string.format("aliases %d\n", #inspection.aliases))
io.write(string.format("addresses %d\n", #inspection.addresses))
io.write(string.format("pointer_offsets %d\n", #inspection.pointer_offsets))

if os.getenv("MOONLIFT_BENCH_DIAGNOSTICS_DISASM") == "1" then
    local funcs = { B.BackFuncId("sum_i32"), B.BackFuncId("dot_i32"), B.BackFuncId("add_i32"), B.BackFuncId("scale_i32") }
    local diag = BD.diagnostics(program, decisions, funcs, { bytes = tonumber(os.getenv("MOONLIFT_BENCH_DISASM_BYTES") or "220") })
    for i = 1, #diag.disassembly do
        io.write(string.format("disasm %s\n%s\n", diag.disassembly[i].func.text, diag.disassembly[i].text))
    end
end
