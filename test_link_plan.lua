package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local LinkTarget = require("moonlift.link_target_model")
local LinkValidate = require("moonlift.link_plan_validate")
local LinkCommand = require("moonlift.link_command_plan")

local T = pvm.context()
A2.Define(T)
local LT = LinkTarget.Define(T)
local LV = LinkValidate.Define(T)
local LC = LinkCommand.Define(T)
local L = T.Moon2Link

local obj = os.tmpname() .. ".o"
local f = assert(io.open(obj, "wb")); f:write("x"); f:close()
local out = os.tmpname() .. ".so"

local plan = L.LinkPlan(
    LT.default_object(),
    L.LinkArtifactSharedLibrary,
    L.LinkTool(L.LinkerSystemCc, L.LinkPath("cc")),
    L.LinkPath(out),
    { L.LinkInputObject(L.LinkPath(obj)), L.LinkInputSystemLibrary("m") },
    L.LinkExportAll,
    L.LinkExternRequireResolved,
    { L.LinkOptSoname("libmoonlift_link_test.so") }
)
local report = LV.validate(plan)
assert(#report.issues == 0, "expected valid link plan")
local command_plan = LC.plan(plan)
assert(pvm.classof(command_plan) == L.LinkCommandPlan)
assert(#command_plan.commands == 1)
local cmd = command_plan.commands[1]
assert(pvm.classof(cmd) == L.LinkCmdRun)
local saw_shared, saw_obj, saw_out, saw_lib = false, false, false, false
for i = 1, #cmd.args do
    if cmd.args[i] == "-shared" or cmd.args[i] == "-dynamiclib" then saw_shared = true end
    if cmd.args[i] == obj then saw_obj = true end
    if cmd.args[i] == out then saw_out = true end
    if cmd.args[i] == "-lm" then saw_lib = true end
end
assert(saw_shared)
assert(saw_obj)
assert(saw_out)
assert(saw_lib)
os.remove(obj)
print("moonlift link_plan ok")
