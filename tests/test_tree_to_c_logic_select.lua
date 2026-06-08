package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")

local T = pvm.context()
Schema.Define(T)

local src = [[
extern probe(x: i32): i32 end

func logic_expr(a: i32, b: i32, c: i32): bool
    return (a == 0) and (probe(b) ~= 0) or (probe(a) ~= 0)
end

func select_expr(a: i32, b: i32, c: i32): i32
    return select(a == 0, probe(b), probe(c))
end
]]

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_tree_to_c_logic_select" })
assert(#result.c_report.issues == 0, "C validation issues: " .. tostring(result.c_report.issues[1]))

local CEmit = require("moonlift.c_emit").Define(T)
local c_src = CEmit.emit(result.c_unit)

assert(c_src:match("logic_true_"), "expected logic short-circuit true branch label")
assert(c_src:match("logic_false_"), "expected logic short-circuit false branch label")
assert(c_src:match("logic_join_"), "expected logic join label")
assert(c_src:match("select_true_"), "expected select true branch label")
assert(c_src:match("select_false_"), "expected select false branch label")
assert(c_src:match("select_join_"), "expected select join label")
assert(c_src:match("if %("), "expected generated branch test")

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

io.write("moonlift tree_to_c_logic_select ok\n")
