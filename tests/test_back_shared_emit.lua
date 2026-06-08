package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Pipeline = require("moonlift.frontend_pipeline")
local Object = require("moonlift.back_object")
local LinkTarget = require("moonlift.link_target_model")
local LinkValidate = require("moonlift.link_plan_validate")
local LinkCommand = require("moonlift.link_command_plan")
local LinkExecute = require("moonlift.link_execute")

local function have_cc()
    local ok = os.execute("cc --version >/dev/null 2>&1")
    return ok == true or ok == 0
end

if not have_cc() then
    io.stderr:write("test_back_shared_emit: cc not available; skipped\n")
    print("moonlift back_shared_emit ok")
    return
end

local T = pvm.context()
A2.Define(T)
local O = Object.Define(T)
local LT = LinkTarget.Define(T)
local LV = LinkValidate.Define(T)
local LC = LinkCommand.Define(T)
local LE = LinkExecute.Define(T)
local Link = T.MoonLink

local src = [[
func add_i32(a: i32, b: i32): i32
    return a + b
end
]]
local result = Pipeline.Define(T).parse_and_lower(src, { site = "test_back_shared_emit" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0)

local base = os.tmpname():gsub("[^A-Za-z0-9_./-]", "_")
local obj_path = base .. ".o"
local so_path = base .. (ffi.os == "OSX" and ".dylib" or ffi.os == "Windows" and ".dll" or ".so")
O.compile(program, { module_name = "moonlift_shared_smoke" }):write(obj_path)
local plan = Link.LinkPlan(
    LT.default_object(),
    Link.LinkArtifactSharedLibrary,
    Link.LinkTool(Link.LinkerSystemCc, Link.LinkPath("cc")),
    Link.LinkPath(so_path),
    { Link.LinkInputObject(Link.LinkPath(obj_path)) },
    Link.LinkExportAll,
    Link.LinkExternRequireResolved,
    {}
)
local link_report = LV.validate(plan)
assert(#link_report.issues == 0)
local command_plan = LC.plan(plan)
local result = LE.execute(command_plan)
assert(pvm.classof(result) == Link.LinkOk, "shared link failed")

ffi.cdef[[ int32_t add_i32(int32_t a, int32_t b); ]]
local lib = ffi.load(so_path)
assert(lib.add_i32(20, 22) == 42)

os.remove(obj_path)
os.remove(so_path)
print("moonlift back_shared_emit ok")
