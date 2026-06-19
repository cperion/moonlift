package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Pipeline = require("moonlift.frontend_pipeline")
local J = require("moonlift.back_jit")

local T = pvm.context()
A.Define(T)
local jit_api = J.Define(T)
local B = T.MoonBack

local src = [[
func atomic_demo(p: ptr(i32)): i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end
]]

local result = Pipeline.Define(T).parse_and_lower(src, { site = "test_atomics" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0, report.issues[1] and report.issues[1].kind)

local counts = { load = 0, store = 0, rmw = 0, cas = 0, fence = 0 }
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == B.CmdAtomicLoad then counts.load = counts.load + 1 end
    if pvm.classof(cmd) == B.CmdAtomicStore then counts.store = counts.store + 1 end
    if pvm.classof(cmd) == B.CmdAtomicRmw then counts.rmw = counts.rmw + 1 end
    if pvm.classof(cmd) == B.CmdAtomicCas then counts.cas = counts.cas + 1 end
    if pvm.classof(cmd) == B.CmdAtomicFence then counts.fence = counts.fence + 1 end
end
assert(counts.load == 1, "expected one CmdAtomicLoad, saw " .. tostring(counts.load))
assert(counts.store == 1, "expected one CmdAtomicStore, saw " .. tostring(counts.store))
assert(counts.rmw == 1, "expected one CmdAtomicRmw, saw " .. tostring(counts.rmw))
assert(counts.cas == 1, "expected one CmdAtomicCas, saw " .. tostring(counts.cas))
assert(counts.fence == 1, "expected one CmdAtomicFence, saw " .. tostring(counts.fence))

local artifact = jit_api.jit():compile(program)
local atomic_demo = ffi.cast("int32_t (*)(int32_t*)", artifact:getpointer(B.BackFuncId("atomic_demo")))
local cell = ffi.new("int32_t[1]", { 0 })
local got = atomic_demo(cell)
assert(got == 46, "atomic_demo returned " .. tostring(got))
assert(cell[0] == 21, "cell[0] was " .. tostring(cell[0]))
artifact:free()
print("ok")
