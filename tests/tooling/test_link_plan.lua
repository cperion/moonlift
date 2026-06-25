package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A2 = require("lalin.schema_projection")
local LinkTarget = require("lalin.link_target_model")
local LinkValidate = require("lalin.link_plan_validate")
local LinkCommand = require("lalin.link_command_plan")

local T = pvm.context()
A2(T)
local LT = LinkTarget(T)
local LV = LinkValidate(T)
local LC = LinkCommand(T)
local L = T.LalinLink

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
    { L.LinkOptSoname("libml_link_test.so") }
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
print("lalin link_plan ok")
