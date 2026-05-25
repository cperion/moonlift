-- Native executable smoke tests for materialized stencil fixtures.
--
-- These tests use a C-call wrapper around snippets, not the production pinned
-- entry path.  They prove that the current fixture bytes can execute and match
-- the semantic stencil contract for straight-line success cases.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local F = require("experiments.lua_interpreter_vm.src.jit.stencil_fixtures")
local N = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not N.supported then
    print("JIT native stencils: skipped on " .. tostring(ffi.os) .. "/" .. tostring(ffi.arch))
    os.exit(0)
end

local Tag = S.Tag
local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

local function setv(a, i, tag, aux, bits)
    a[i].tag = tag
    a[i].aux = aux or 0
    a[i].bits = bits or 0
end

local function checkv(name, a, i, tag, aux, bits)
    check(name .. ".tag", tonumber(a[i].tag) == tag, tostring(a[i].tag))
    check(name .. ".aux", tonumber(a[i].aux) == (aux or 0), tostring(a[i].aux))
    check(name .. ".bits", tonumber(a[i].bits) == (bits or 0), tostring(a[i].bits))
end

local units = {}
local function run_fixture(spec_name, stamps, fixups, arr)
    local fx = assert(F.first_fixture(spec_name), "missing fixture " .. spec_name)
    local unit = N.build_callable(fx, stamps, fixups)
    units[#units + 1] = unit
    unit.fn(arr)
    return unit
end

-- LOADI writes an integer Value to slot A.
do
    local a = N.new_values(8)
    run_fixture("value.load_i64.imm_to_sA.fall", { a = 3, imm = 777 }, nil, a)
    checkv("native LOADI dst", a, 3, Tag.INTEGER, 0, 777)
end

-- MOVE copies all three scalar fields.
do
    local a = N.new_values(8)
    setv(a, 5, Tag.NUM, 123, 456)
    run_fixture("value.move.sB_to_sA.fall", { a = 2, b = 5 }, nil, a)
    checkv("native MOVE dst", a, 2, Tag.NUM, 123, 456)
end

-- Guarded ADD success path.  The side-exit relocs are present but not taken.
do
    local a = N.new_values(8)
    setv(a, 1, Tag.INTEGER, 0, 20)
    setv(a, 2, Tag.INTEGER, 0, 22)
    run_fixture("arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", { a = 0, b = 1, c = 2 }, { side_exit = 0, side_exit_2 = 0 }, a)
    checkv("native ADD dst", a, 0, Tag.INTEGER, 0, 42)
end

-- Guarded ADDI success path.
do
    local a = N.new_values(8)
    setv(a, 1, Tag.INTEGER, 0, 35)
    run_fixture("arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit", { a = 0, b = 1, imm = 7 }, { side_exit = 0 }, a)
    checkv("native ADDI dst", a, 0, Tag.INTEGER, 0, 42)
end

-- Boolean loads.
do
    local a = N.new_values(8)
    run_fixture("value.load_bool.tag_to_sA.fall", { a = 2, tag = Tag.TRUE }, nil, a)
    checkv("native LOADTRUE dst", a, 2, Tag.TRUE, 0, 0)
    run_fixture("value.load_bool.tag_to_sA.fall", { a = 3, tag = Tag.FALSE }, nil, a)
    checkv("native LOADFALSE dst", a, 3, Tag.FALSE, 0, 0)
end

-- LOADK literal value.
do
    local a = N.new_values(8)
    run_fixture("value.load_k.kB_to_sA.fall", { a = 4, tag = Tag.NUM, aux = 17, bits = 1234 }, nil, a)
    checkv("native LOADK dst", a, 4, Tag.NUM, 17, 1234)
end

-- LOADNIL range.
do
    local a = N.new_values(8)
    for i = 0, 5 do setv(a, i, Tag.INTEGER, 0, i + 1) end
    run_fixture("value.load_nil.sA_count.fall", { a = 1, count_plus_one = 3 }, nil, a)
    checkv("native LOADNIL first", a, 1, Tag.NIL, 0, 0)
    checkv("native LOADNIL mid", a, 2, Tag.NIL, 0, 0)
    checkv("native LOADNIL last", a, 3, Tag.NIL, 0, 0)
    checkv("native LOADNIL after", a, 4, Tag.INTEGER, 0, 5)
end

-- GETUPVAL direct Value* copy.
do
    local a = N.new_values(8)
    local up = N.new_values(1)
    setv(up, 0, Tag.INTEGER, 33, 444)
    run_fixture("value.getupval.generic.sU_to_sA.fall", { a = 5, upvalue_ptr = up }, nil, a)
    checkv("native GETUPVAL dst", a, 5, Tag.INTEGER, 33, 444)
end

for _, u in ipairs(units) do N.free(u) end

print(string.format("JIT native stencils: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
