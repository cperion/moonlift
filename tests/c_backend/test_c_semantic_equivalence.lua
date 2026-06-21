package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local CEmit = require("moonlift.c_emit")

local function exec_ok(cmd)
    local a = os.execute(cmd)
    return a == true or a == 0
end

if not exec_ok("command -v cc >/dev/null 2>&1") then
    io.write("cc not found; skipping C semantic equivalence smoke\n")
    return
end

local T = pvm.context(); Schema.Define(T)
local src = [[
func add_i32(a: i32, b: i32): i32
    return a + b
end

func assign_if(x: i32): i32
    var acc: i32 = 0
    if x > 0 then acc = x * 2 else acc = 1 end
    return acc
end

func classify_expr(op: i32): i32
    return switch op do
    case 11 then 100
    case 12 then
        let x: i32 = 20
        x + 2
    default then 3
    end
end
]]

local expected = { add = 7, pos = 10, neg = 1, c11 = 100, c12 = 22, c99 = 3 }
local ok_jit, jit_or_err = pcall(function()
    local Run = require("moonlift.mlua_run")
    local bundle = Run.eval([[local add_i32 = func add_i32(a: i32, b: i32): i32
    return a + b
end
local assign_if = func assign_if(x: i32): i32
    var acc: i32 = 0
    if x > 0 then acc = x * 2 else acc = 1 end
    return acc
end
local classify_expr = func classify_expr(op: i32): i32
    return switch op do
    case 11 then 100
    case 12 then
        let x: i32 = 20
        x + 2
    default then 3
    end
end
return { add_i32 = add_i32, assign_if = assign_if, classify_expr = classify_expr }]])
    local add = bundle.add_i32:compile()
    local assign = bundle.assign_if:compile()
    local classify = bundle.classify_expr:compile()
    local out = { add = tonumber(add(3, 4)), pos = tonumber(assign(5)), neg = tonumber(assign(-1)), c11 = tonumber(classify(11)), c12 = tonumber(classify(12)), c99 = tonumber(classify(99)) }
    add:free(); assign:free(); classify:free()
    return out
end)
if ok_jit then expected = jit_or_err else io.write("JIT unavailable; using literal expectations: " .. tostring(jit_or_err) .. "\n") end

local result = Pipeline.Define(T).parse_and_lower_c(src, { site = "test_c_semantic_equivalence" })
assert(#result.c_report.issues == 0, "C validation issues: " .. tostring(result.c_report.issues[1]))
local c_src = CEmit.Define(T).emit_artifact(result.c_unit).source
local main = string.format([[#include <stdio.h>
int main(void) {
  if (add_i32(3, 4) != %d) return 10;
  if (assign_if(5) != %d) return 11;
  if (assign_if(-1) != %d) return 12;
  if (classify_expr(11) != %d) return 13;
  if (classify_expr(12) != %d) return 14;
  if (classify_expr(99) != %d) return 15;
  return 0;
}
]], expected.add, expected.pos, expected.neg, expected.c11, expected.c12, expected.c99)
local c_path = os.tmpname() .. ".c"
local exe_path = os.tmpname()
local f = assert(io.open(c_path, "wb")); f:write(c_src); f:write("\n"); f:write(main); f:close()
local ok = exec_ok("cc -std=c99 " .. c_path .. " -lm -o " .. exe_path .. " && " .. exe_path)
os.remove(c_path); os.remove(exe_path)
assert(ok, "compiled C semantic smoke failed")

io.write("moonlift c_semantic_equivalence ok\n")
