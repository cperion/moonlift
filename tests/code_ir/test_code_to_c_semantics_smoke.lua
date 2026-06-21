package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")

local T = pvm.context()
Schema.Define(T)

local src = [[
extern host_add7(x: i32): i32 end

func assign_if(x: i32): i32
    var acc: i32 = 0
    if x > 0 then
        acc = x * 2
    else
        acc = 1
    end
    return acc
end

func classify_expr(op: i32): i32
    return switch op do
    case 11 then 100
    case 12 then
        let x: i32 = 20
        x + 2
    default then
        let y: i32 = 3
        y
    end
end

func classify_stmt(op: i32): i32
    var out: i32 = 0
    switch op do
    case 1 then
        out = 10
    case 2 then
        out = 20
    default then
        out = 30
    end
    return out
end

func load0(p: ptr(i32)): i32
    return p[0]
end

func load_deref(p: ptr(i32)): i32
    return *p
end

func store0(p: ptr(i32), x: i32): i32
    p[0] = x
    return x
end

func first_from_view(xs: ptr(i32), n: index): i32
    let v: view(i32) = view(xs, n)
    return v[0]
end

func call_host(x: i32): i32
    return host_add7(x)
end
]]

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_code_to_c_semantics_smoke" })
assert(result.code_module ~= nil and result.code_report ~= nil and #result.code_report.issues == 0, "Code validation issues")
assert(#result.c_report.issues == 0, "C validation issues: " .. tostring(result.c_report.issues[1]))
assert(#result.c_unit.funcs == 8, "expected eight funcs")
assert(#result.c_unit.externs == 1, "expected extern")

local CEmit = require("moonlift.c_emit").Define(T)
local c_src = CEmit.emit_artifact(result.c_unit).source
assert(c_src:match("if_then"), "expected nonterminal if CFG labels")
assert(c_src:match("switch %(v_classify_expr_arg_classify_expr_op%)") or c_src:match("switch %(v_classify_stmt_arg_classify_stmt_op%)"), "expected switch lowering")
assert(c_src:match("switch_join"), "expected switch expression/statement join")
assert(c_src:match("host_add7%(v_call_host_arg_call_host_x%)"), "expected extern call")
assert(c_src:match("%[v_"), "expected pointer/view indexing emission")
assert(c_src:match("ml_code_helper_"), "expected helper-mediated multiplication")

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

io.write("moonlift code_to_c_semantics_smoke ok\n")
