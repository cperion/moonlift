#!/usr/bin/env luajit
-- Test ELF parser on simple Moonlift-generated object files.

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local elf_parser = require("experiments.lua_interpreter_vm.src.jit.elf_parser")
local moon = require("moonlift")

print("=== Test 1: Simple i32 add function ===")

local simple_src = [[
func test_add(a: i32, b: i32): i32
    return a + b
end
]]

local simple_obj = moon.emit_object(simple_src, "test_simple")
if not simple_obj or #simple_obj == 0 then
    error("Failed to emit object file")
end

print("Emitted object file size:", #simple_obj, "bytes")

-- Parse the object file
local elf, err = elf_parser.parse(simple_obj)
if not elf then
    error("Failed to parse ELF: " .. err)
end

print("ELF machine:", string.format("0x%x", elf.header.machine))
print("ELF type:", elf.header.type)
print("Functions found:", #elf.functions)

-- Look for test_add function
local test_add_fn = nil
for _, fn in ipairs(elf.functions) do
    print("  - " .. fn.name .. " @ offset 0x" .. string.format("%x", fn.offset) ..
          ", size " .. fn.size .. ", relocs: " .. #fn.relocations)
    if fn.name == "test_add" then
        test_add_fn = fn
    end
end

if not test_add_fn then
    error("test_add function not found in ELF")
end

print("\ntest_add function details:")
print("  Offset:", test_add_fn.offset)
print("  Size:", test_add_fn.size)
print("  Bytes (hex):", elf_parser.bytes_to_hex(test_add_fn.bytes))
print("  Relocations:", #test_add_fn.relocations)
for i, rel in ipairs(test_add_fn.relocations) do
    print("    [" .. i .. "] offset=0x" .. string.format("%x", rel.offset) ..
          " sym=" .. rel.sym_name .. " type=" .. elf_parser.reloc_type_name(rel.type))
end

print("\n=== Test 2: Function with extern call ===")

local extern_src = [[
extern test_helper(x: i32): i32 end

func test_with_call(a: i32): i32
    return test_helper(a)
end
]]

local extern_obj = moon.emit_object(extern_src, "test_extern")
if not extern_obj or #extern_obj == 0 then
    error("Failed to emit object file for extern test")
end

print("Emitted object file size:", #extern_obj, "bytes")

local elf2, err2 = elf_parser.parse(extern_obj)
if not elf2 then
    error("Failed to parse ELF: " .. err2)
end

print("Functions found:", #elf2.functions)
for _, fn in ipairs(elf2.functions) do
    print("  - " .. fn.name .. " @ offset 0x" .. string.format("%x", fn.offset) ..
          ", size " .. fn.size .. ", relocs: " .. #fn.relocations)
    if fn.name == "test_with_call" then
        print("    Bytes (hex):", elf_parser.bytes_to_hex(fn.bytes))
        for i, rel in ipairs(fn.relocations) do
            print("    [" .. i .. "] offset=0x" .. string.format("%x", rel.offset) ..
                  " sym=" .. rel.sym_name .. " type=" .. elf_parser.reloc_type_name(rel.type))
        end
    end
end

print("\n=== Test 3: Verify extraction consistency ===")

-- Re-parse and check that we get the same results
local elf3, err3 = elf_parser.parse(simple_obj)
if not elf3 then
    error("Failed to re-parse ELF: " .. err3)
end

local fn3 = elf3.functions[1]
if fn3.name ~= test_add_fn.name then
    error("Function name mismatch on re-parse")
end

if fn3.size ~= test_add_fn.size then
    error("Function size mismatch on re-parse")
end

if fn3.bytes ~= test_add_fn.bytes then
    error("Function bytes mismatch on re-parse")
end

print("Consistency check: PASS")
print("  Same function name, size, and bytes after re-parsing")

print("\n=== All tests passed ===")
