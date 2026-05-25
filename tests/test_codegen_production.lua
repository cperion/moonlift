#!/usr/bin/env luajit
-- Test of production codegen with proper Moonlift syntax

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local codegen = require("experiments.lua_interpreter_vm.src.jit.stencil_codegen_production")
local moon = require("moonlift")

local simple_candidate = {
    name = "test_const",
    id = 1,
    ops = {
        {op = "ConstInt", args = {value = "imm"}},
        {op = "Jump", args = {target = "next"}},
    }
}

local guard_candidate = {
    name = "test_guard",
    id = 2,
    ops = {
        {op = "ReadSlot", args = {slot = "slot0"}},
        {op = "GuardTag", args = {exit = "exit0", tag = "INTEGER", value = "slot0"}},
        {op = "Jump", args = {target = "next"}},
    }
}

local add_candidate = {
    name = "test_add",
    id = 3,
    ops = {
        {op = "ReadSlot", args = {slot = "lhs"}},
        {op = "ReadSlot", args = {slot = "rhs"}},
        {op = "AddIntWrap", args = {lhs = "lhs", rhs = "rhs"}},
        {op = "Jump", args = {target = "next"}},
    }
}

print("=== Test 1: Simple const ===")
local func, err = codegen.generate_function(simple_candidate)
if not func then
    print("ERROR:", err)
    os.exit(1)
end
print("Generated:")
print(func.source)

print("\n=== Test 2: Guard tag ===")
local func2, err2 = codegen.generate_function(guard_candidate)
if not func2 then
    print("ERROR:", err2)
    os.exit(1)
end
print("Generated:")
print(func2.source)

print("\n=== Test 3: Addition ===")
local func3, err3 = codegen.generate_function(add_candidate)
if not func3 then
    print("ERROR:", err3)
    os.exit(1)
end
print("Generated:")
print(func3.source)

print("\n=== Module generation ===")
local module, err = codegen.generate_module({simple_candidate, guard_candidate, add_candidate})
if not module then
    print("ERROR:", err)
    os.exit(1)
end
print("Generated module with", #module.generated, "functions")

print("\n=== Try to compile ===")
local obj_bytes, err = moon.emit_object(module.source, "test")
if not obj_bytes or #obj_bytes == 0 then
    print("Compilation FAILED:", err or "unknown error")
    os.exit(1)
else
    print("Compilation SUCCEEDED! Object size:", #obj_bytes, "bytes")
end

print("\n✓ All tests passed")
