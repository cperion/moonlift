#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local Pipeline = require("moonlift.frontend_pipeline")
local Object = require("moonlift.back_object")
local LinkTarget = require("moonlift.link_target_model")
local LinkValidate = require("moonlift.link_plan_validate")
local LinkCommand = require("moonlift.link_command_plan")
local LinkExecute = require("moonlift.link_execute")

local function usage()
    io.stderr:write("usage: luajit emit_shared.lua input.mlua -o liboutput.so [--module-name name] [--keep-object path]\n")
    os.exit(2)
end

local input, output, module_name, keep_object
local i = 1
while i <= #(arg or {}) do
    local a = arg[i]
    if a == "-o" then i = i + 1; output = arg[i] or usage()
    elseif a == "--module-name" then i = i + 1; module_name = arg[i] or usage()
    elseif a == "--keep-object" then i = i + 1; keep_object = arg[i] or usage()
    elseif a == "-h" or a == "--help" then usage()
    elseif not input then input = a
    else usage() end
    i = i + 1
end
if not input or not output then usage() end
module_name = module_name or input:gsub("[/\\]", "_"):gsub("%.mlua$", "")

local f, err = io.open(input, "rb")
if not f then io.stderr:write(tostring(err), "\n"); os.exit(1) end
local source = f:read("*a")
f:close()

local T = pvm.context()
A2(T)
local O = Object(T)
local LT = LinkTarget(T)
local LV = LinkValidate(T)
local LC = LinkCommand(T)
local LE = LinkExecute(T)
local Link = T.MoonLink

local function issue_list(issues)
    for j = 1, #issues do io.stderr:write(tostring(issues[j].message or issues[j]), "\n") end
end

local ok, lowered_or_err = pcall(function()
    return Pipeline(T).parse_and_lower(source, { site = "emit_shared.lua" })
end)
if not ok then io.stderr:write(tostring(lowered_or_err), "\n"); os.exit(1) end
local program = lowered_or_err.program

local object_path = keep_object or (os.tmpname() .. ".o")
local object = O.compile(program, { module_name = module_name })
object:write(object_path)

local plan = Link.LinkPlan(
    LT.default_object(),
    Link.LinkArtifactSharedLibrary,
    Link.LinkTool(Link.LinkerSystemCc, Link.LinkPath("cc")),
    Link.LinkPath(output),
    { Link.LinkInputObject(Link.LinkPath(object_path)) },
    Link.LinkExportAll,
    Link.LinkExternRequireResolved,
    {}
)
local link_report = LV.validate(plan)
if #link_report.issues ~= 0 then issue_list(link_report.issues); os.exit(1) end
local commands = LC.plan(plan)
local result = LE.execute(commands)
if pvm.classof(result) == Link.LinkFailed then issue_list(result.report.issues); os.exit(1) end
if not keep_object then os.remove(object_path) end
print(output)
