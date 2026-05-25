-- Native executable block tests: multiple stencils, one callable unit.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local N = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not N.supported then
    print("JIT native blocks: skipped on " .. tostring(ffi.os) .. "/" .. tostring(ffi.arch))
    os.exit(0)
end

local Tag, Op, E = S.Tag, S.Op, S.encode
local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. (detail and (" -- " .. detail) or "")) end
end

local function checkv(name, a, i, tag, aux, bits)
    check(name .. ".tag", tonumber(a[i].tag) == tag, tostring(a[i].tag))
    check(name .. ".aux", tonumber(a[i].aux) == (aux or 0), tostring(a[i].aux))
    check(name .. ".bits", tonumber(a[i].bits) == (bits or 0), tostring(a[i].bits))
end

local units = {}

-- LOADI R0,20; LOADI R1,22; ADD R2,R0,R1; MOVE R3,R2
do
    local block = N.build_block {
        { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 0, imm = 20 } },
        { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 1, imm = 22 } },
        { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 2, b = 0, c = 1 } },
        { spec = "value.move.sB_to_sA.fall", stamps = { a = 3, b = 2 } },
    }
    units[#units + 1] = block

    local a = N.new_values(8)
    block.fn(a)
    checkv("block R0", a, 0, Tag.INTEGER, 0, 20)
    checkv("block R1", a, 1, Tag.INTEGER, 0, 22)
    checkv("block R2", a, 2, Tag.INTEGER, 0, 42)
    checkv("block R3", a, 3, Tag.INTEGER, 0, 42)
    check("block body has concatenated stencils", block.body_size > 100)
end

-- Same block checked against the reference interpreter sequence.
do
    local block = N.build_block {
        { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 0, imm = 5 } },
        { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 1, imm = 6 } },
        { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 2, b = 0, c = 1 } },
        { spec = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit", stamps = { a = 3, b = 2, imm = 31 } },
    }
    units[#units + 1] = block

    local native = N.new_values(8)
    block.fn(native)

    local ref = { stack = {}, constants = {}, pc = 0, base = 0, top = 8 }
    S.reference_step(ref, E.AsBx(Op.LOADI, 0, 5))
    S.reference_step(ref, E.AsBx(Op.LOADI, 1, 6))
    S.reference_step(ref, E.ABC(Op.ADD, 2, 0, 1))
    S.reference_step(ref, E.ABC(Op.ADDI, 3, 2, 31))

    check("native/ref R0", tonumber(native[0].bits) == ref.stack[0].bits)
    check("native/ref R1", tonumber(native[1].bits) == ref.stack[1].bits)
    check("native/ref R2", tonumber(native[2].bits) == ref.stack[2].bits)
    check("native/ref R3", tonumber(native[3].bits) == ref.stack[3].bits)
end

for _, u in ipairs(units) do N.free(u) end

print(string.format("JIT native blocks: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
