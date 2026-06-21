package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local CEmit = require("moonlift.c_emit")
local Harness = require("tests.c_backend.test_c_gcc_harness")

local T = pvm.context(); Schema.Define(T)

local src = [[
union Maybe
    some(i32)
  | none
end

func tag_stmt(): i32
    let m = Maybe.some(33)
    switch m do
    case .some(x) then return x
    default then return 0
    end
end

func tag_expr(): i32
    let m = Maybe.some(44)
    return switch m do
    case .some(x) then x
    default then 0
    end
end

func tag_default(): i32
    let m = Maybe.none()
    return switch m do
    case .some(x) then x
    default then 5
    end
end
]]

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_c_gcc_tagged_union" })
assert(result.code_module ~= nil, "C pipeline should expose MoonCode module")
assert(result.code_report ~= nil and #result.code_report.issues == 0, "Code validation issues: " .. tostring(#result.code_report.issues))
assert(#result.c_report.issues == 0, "C validation issues: " .. tostring(#result.c_report.issues))
local c_src = CEmit.Define(T).emit_artifact(result.c_unit).source .. [[
int main(void) {
    if (tag_stmt() != 33) return 102;
    if (tag_expr() != 44) return 103;
    if (tag_default() != 5) return 104;
    return 0;
}
]]

if Harness.have_cc() then local built = Harness.compile_c(c_src, { cflags = "-std=c99 -Wall -Wextra" }); Harness.run_executable(built.exe_path) end

local ok, err = pcall(function()
    Pipeline.Define(T).parse_and_lower_c([[
union Maybe
    some(i32)
  | none
end

func bad(): i32
    let m = Maybe.none()
    return switch m do
    case .missing then 1
    default then 0
    end
end
]], { site = "test_c_gcc_tagged_union:bad" })
end)
assert(not ok and tostring(err):match("variant"), "impossible variant arm should be diagnosed upstream")
assert(package.loaded["moonlift.tree_to_c"] == nil)

io.write("moonlift C gcc tagged union ok\n")
