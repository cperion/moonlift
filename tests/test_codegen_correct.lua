#!/usr/bin/env luajit
-- Quick test of correct codegen

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local codegen = require("experiments.lua_interpreter_vm.src.jit.stencil_codegen_correct")
local moon = require("moonlift")

local simple_candidate = {
    name = "test_const",
    id = 1,
    ops = {
        {op = "ConstInt", args = {value = "imm"}},
        {op = "Jump", args = {target = "next"}},
    }
}

print("=== Generate function ===")
local func, err = codegen.generate_function(simple_candidate)
if not func then
    print("ERROR:", err)
    return
end

print("Generated source:")
print(func.source)

print("\n=== Try to compile ===")
local obj_bytes, err = moon.emit_object(func.source, "test")
if not obj_bytes or #obj_bytes == 0 then
    print("Compilation FAILED:", err or "unknown error")
else
    print("Compilation succeeded! Object size:", #obj_bytes, "bytes")
end
