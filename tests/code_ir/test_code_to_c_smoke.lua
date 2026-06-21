package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local Coverage = require("moonlift.c_coverage")

local T = pvm.context()
Schema.Define(T)

local src = [[
extern host_add7(x: i32): i32 end

func add_i32(a: i32, b: i32): i32
    return a + b
end

func pos_or_one(x: i32): i32
    return block choose(): i32
        if x > 0 then yield x else yield 1 end
    end
end

func sum_to(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then
            yield acc
        else
            jump loop(i = i + 1, acc = acc + i)
        end
    end
end

func pick(x: i32): i32
    return block choose(): i32
        switch x do
        case 0 then
            yield 10
        case 1 then
            yield 20
        default then
            yield 30
        end
    end
end

func call_host(x: i32): i32
    return host_add7(x)
end
]]

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_code_to_c_smoke" })
assert(result.code_module ~= nil and result.code_report ~= nil and #result.code_report.issues == 0, "Code validation issues")
assert(#result.c_report.issues == 0, "C validation issues: " .. #result.c_report.issues)
assert(#result.c_unit.funcs == 5, "expected five C backend funcs")
assert(#result.c_unit.externs == 1, "expected one C backend extern")
assert(#result.c_unit.sigs >= 1, "expected collected function signature(s)")
assert(Coverage.classification("MoonTree.Expr", "ExprCall").status == "supported", "coverage matrix should classify calls")
assert(Coverage.classification("MoonTree.Stmt", "StmtControl").status == "supported", "coverage matrix should classify control statements")

local CEmit = require("moonlift.c_emit").Define(T)
local c_src = CEmit.emit_artifact(result.c_unit).source
assert(c_src:match("int32_t add_i32%("), "expected add_i32 definition/prototype")
assert(c_src:match("extern int32_t host_add7%("), "expected extern declaration")
assert(c_src:match("switch %(v_pick_arg_pick_x%)"), "expected switch/goto lowering")
assert(c_src:match("goto block_"), "expected label/goto lowering")
assert(c_src:match("ml_code_helper_"), "expected arithmetic helper use")

local function exec_ok(cmd)
    local a = os.execute(cmd)
    return a == true or a == 0
end

if exec_ok("command -v cc >/dev/null 2>&1") then
    local path = os.tmpname() .. ".c"
    local f = assert(io.open(path, "wb"))
    f:write(c_src)
    f:close()
    local ok = exec_ok("cc -std=c99 -fsyntax-only " .. path)
    os.remove(path)
    assert(ok, "emitted C failed cc -std=c99 -fsyntax-only")
else
    io.write("cc not found; skipping emitted C syntax check\n")
end

io.write("moonlift code_to_c_smoke ok\n")
