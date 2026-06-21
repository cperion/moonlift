package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local CEmit = require("moonlift.c_emit")

local T = pvm.context(); Schema.Define(T)

local src = [[
union Maybe
    some(i32)
  | none
end

func match_stmt(): i32
    let m = Maybe.some(33)
    switch m do
    case .some(x) then return x
    default then return 0
    end
end

func match_expr(): i32
    let m = Maybe.some(44)
    return switch m do
    case .some(x) then x
    default then 0
    end
end

func match_control(): i32
    return block choose(): i32
        let m = Maybe.some(55)
        switch m do
        case .some(x) then yield x
        default then yield 0
        end
    end
end
]]

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_tagged_union_to_c" })
assert(result.code_module ~= nil, "C pipeline should expose MoonCode module")
assert(result.code_report ~= nil and #result.code_report.issues == 0, "Code validation issues: " .. tostring(#result.code_report.issues))
assert(#result.c_report.issues == 0, "C validation issues: " .. tostring(#result.c_report.issues))

local c_src = CEmit.Define(T).emit_artifact(result.c_unit).source
assert(c_src:match("__tag"), "tagged union C should contain __tag field")
assert(c_src:match("__payload"), "tagged union C should contain __payload field")
assert(c_src:match("switch %("), "variant switch should lower through a C switch")

local function exec_ok(cmd)
    local a = os.execute(cmd)
    return a == true or a == 0
end
if exec_ok("command -v cc >/dev/null 2>&1") then
    local path = os.tmpname() .. ".c"
    local f = assert(io.open(path, "wb")); f:write(c_src); f:close()
    local ok = exec_ok("cc -std=c99 -fsyntax-only " .. path)
    os.remove(path)
    assert(ok, "emitted tagged-union C failed cc -std=c99 -fsyntax-only")
end

assert(package.loaded["moonlift.tree_to_c"] == nil)
io.write("moonlift tagged union code_to_c ok\n")
