#!/usr/bin/env luajit
-- Test StateOp to Moonlift code generation.

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local codegen = require("experiments.lua_interpreter_vm.src.jit.stencil_codegen")
local moon = require("moonlift")

print("=== Test 1: Generate simple ConstInt function ===")

local simple_candidate = {
    name = "test_const_int",
    id = 1,
    ops = {
        {op = "ConstInt", args = {value = "imm"}},
        {op = "Jump", args = {target = "next"}},
    }
}

local func1, err1 = codegen.generate_function(simple_candidate)
if not func1 then
    error("Failed to generate function: " .. err1)
end

print("Generated function source:")
print(func1.source)
print("\nHoles detected:")
for i, hole in ipairs(func1.holes) do
    print(string.format("  [%d] kind=%s, name=%s", i, hole.kind, hole.name))
end

print("\n=== Test 2: Generate simple ReadSlot function ===")

local readslot_candidate = {
    name = "test_read_slot",
    id = 2,
    ops = {
        {op = "ReadSlot", args = {slot = "lhs"}},
        {op = "Jump", args = {target = "next"}},
    }
}

local func2, err2 = codegen.generate_function(readslot_candidate)
if not func2 then
    error("Failed to generate function: " .. err2)
end

print("Generated function source:")
print(func2.source)

print("\n=== Test 3: Compile generated functions to object file ===")

-- Create a tiny module with both functions
local test_module_src = func1.source .. "\n" .. func2.source

print("Combined module (first 500 chars):")
print(string.sub(test_module_src, 1, 500))

-- Try to compile it
local obj_bytes, err = moon.emit_object(test_module_src, "test_codegen")
if not obj_bytes or #obj_bytes == 0 then
    error("Failed to emit object: " .. (err or "unknown"))
end

print("\nEmitted object file: " .. #obj_bytes .. " bytes")

-- Parse it
local elf_parser = require("experiments.lua_interpreter_vm.src.jit.elf_parser")
local elf, elf_err = elf_parser.parse(obj_bytes)
if not elf then
    error("Failed to parse ELF: " .. elf_err)
end

print("Functions in ELF:")
for _, fn in ipairs(elf.functions) do
    print(string.format("  - %s @ 0x%x, size %d bytes", fn.name, fn.offset, fn.size))
    print("    Bytes (hex): " .. elf_parser.bytes_to_hex(string.sub(fn.bytes, 1, math.min(16, #fn.bytes))))
end

print("\n=== Test 4: Generate module from multiple candidates ===")

local candidates = {
    simple_candidate,
    readslot_candidate,
}

local module, err = codegen.generate_module(candidates)
if not module then
    error("Failed to generate module: " .. err)
end

print("Generated " .. #module.generated .. " functions in module")
for _, gen in ipairs(module.generated) do
    print(string.format("  - %s (id=%d)", gen.name, gen.id))
end

print("\n=== All codegen tests passed ===")
