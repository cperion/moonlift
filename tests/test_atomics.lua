package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B = T.MoonBack

local src = [[
func atomic_demo(p: ptr(i32)) -> i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0, parsed.issues[1] and parsed.issues[1].message)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0, checked.issues[1] and checked.issues[1].kind)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, report.issues[1] and report.issues[1].kind)

local saw_load, saw_store, saw_rmw, saw_cas, saw_fence = false, false, false, false, false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == B.CmdAtomicLoad then saw_load = true end
    if pvm.classof(cmd) == B.CmdAtomicStore then saw_store = true end
    if pvm.classof(cmd) == B.CmdAtomicRmw then saw_rmw = true end
    if pvm.classof(cmd) == B.CmdAtomicCas then saw_cas = true end
    if pvm.classof(cmd) == B.CmdAtomicFence then saw_fence = true end
end
assert(saw_load and saw_store and saw_rmw and saw_cas and saw_fence, "expected atomic BackCmds")

local artifact = jit_api.jit():compile(program)
local atomic_demo = ffi.cast("int32_t (*)(int32_t*)", artifact:getpointer(B.BackFuncId("atomic_demo")))
local cell = ffi.new("int32_t[1]", { 0 })
assert(atomic_demo(cell) == 46)
assert(cell[0] == 21)
artifact:free()
print("ok")
