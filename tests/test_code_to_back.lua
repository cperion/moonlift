package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)
local CodeToBack = require("moonlift.code_to_back").Define(T)
local BackValidate = require("moonlift.back_validate").Define(T)
local Jit = require("moonlift.back_jit").Define(T)
local Pipeline = require("moonlift.frontend_pipeline").Define(T)

local Back = T.MoonBack
local Code = T.MoonCode

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function code_pipeline(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module)
    assert_no_issues("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local checked = Typecheck.check_module(ClosureConvert.module(expanded))
    assert_no_issues("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code_module = TreeToCode.module(resolved)
    assert_no_issues("code", CodeValidate.validate(code_module).issues)
    return code_module
end

local code_module = code_pipeline([[
func add_i32_code(a: i32, b: i32): i32
    return a + b
end

func max_i32_code(a: i32, b: i32): i32
    return select(a > b, a, b)
end

func branch_i32_code(a: i32, b: i32): i32
    if a > b then return a else return b end
end

func classify_i32_code(n: i32): i32
    return switch n do
    case 1 then 10
    case 2 then 20
    default then 0
    end
end

func inc_i32_code(x: i32): i32
    return x + 1
end

func direct_call_i32_code(x: i32): i32
    return inc_i32_code(x)
end

func indirect_call_i32_code(x: i32): i32
    let f: func(i32): i32 = inc_i32_code
    return f(x)
end
]])

local program = CodeToBack.module(code_module)
local report = BackValidate.validate(program)
assert_no_issues("back", report.issues)

local saw_add, saw_select, saw_branch, saw_switch, saw_call, saw_func_addr = false, false, false, false, false, false
for _, cmd in ipairs(program.cmds) do
    local cls = pvm.classof(cmd)
    if cls == Back.CmdIntBinary then saw_add = true end
    if cls == Back.CmdSelect then saw_select = true end
    if cls == Back.CmdBrIf then saw_branch = true end
    if cls == Back.CmdSwitchInt then saw_switch = true end
    if cls == Back.CmdCall then saw_call = true end
    if cls == Back.CmdFuncAddr then saw_func_addr = true end
end
assert(saw_add, "CodeInstBinary should lower to CmdIntBinary")
assert(saw_select, "CodeInstSelect should lower to CmdSelect")
assert(saw_branch, "CodeTermBranch should lower to CmdBrIf")
assert(saw_switch, "CodeTermSwitch should lower to CmdSwitchInt")
assert(saw_call, "CodeInstCall should lower to CmdCall")
assert(saw_func_addr, "function values should lower to CmdFuncAddr")

local artifact = Jit.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("add_i32_code")))
local max = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("max_i32_code")))
local branch = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("branch_i32_code")))
local classify = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("classify_i32_code")))
local direct = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("direct_call_i32_code")))
local indirect = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("indirect_call_i32_code")))
assert(add(20, 22) == 42)
assert(max(4, 9) == 9 and max(12, 7) == 12)
assert(branch(4, 9) == 9 and branch(12, 7) == 12)
assert(classify(1) == 10 and classify(2) == 20 and classify(99) == 0)
assert(direct(41) == 42)
assert(indirect(41) == 42)
artifact:free()

local public_src = [[
func public_inc_i32_code(x: i32): i32
    return x + 1
end

func public_sum_i32_code(xs: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

func public_direct_call_i32_code(x: i32): i32
    return public_inc_i32_code(x)
end

func public_indirect_call_i32_code(x: i32): i32
    let f: func(i32): i32 = public_inc_i32_code
    return f(x)
end
]]

local public_result = Pipeline.parse_and_lower(public_src, { site = "test_code_to_back:public" })
assert(public_result.code_module ~= nil, "public native pipeline should expose CodeModule")
assert(public_result.code_report ~= nil and #public_result.code_report.issues == 0, "public code validation issues")
assert(#public_result.back_report.issues == 0, "public back validation issues")
local public_artifact = Jit.jit():compile(public_result.program)
local public_sum = ffi.cast("int32_t (*)(const int32_t*, int32_t)", public_artifact:getpointer(Back.BackFuncId("public_sum_i32_code")))
local public_direct = ffi.cast("int32_t (*)(int32_t)", public_artifact:getpointer(Back.BackFuncId("public_direct_call_i32_code")))
local public_indirect = ffi.cast("int32_t (*)(int32_t)", public_artifact:getpointer(Back.BackFuncId("public_indirect_call_i32_code")))
local public_xs = ffi.new("int32_t[4]", { 5, 6, 7, 8 })
assert(public_sum(public_xs, 4) == 26)
assert(public_direct(41) == 42)
assert(public_indirect(41) == 42)
public_artifact:free()

local fh = assert(io.open("lua/moonlift/code_to_back.lua", "r"))
local source = fh:read("*a"); fh:close()
assert(not source:find("ctx%." .. "view_defs"), "Back lowering must not keep hidden view-def side table")
assert(not source:find("collect_" .. "view_defs"), "Back lowering must not pre-scan view defs")
assert(not source:find("view_" .. "parts"), "Back lowering must not use view component side table")

print("moonlift code_to_back ok")
