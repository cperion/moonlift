-- Native executable blocks with observable JitOutcome-style results.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local N = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not N.supported then
    print("JIT native outcomes: skipped on " .. tostring(ffi.os) .. "/" .. tostring(ffi.arch))
    os.exit(0)
end

local Tag, Status = S.Tag, N.OutcomeStatus
local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. (detail and (" -- " .. detail) or "")) end
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

-- Guarded ADD success writes OK outcome.
do
    local block = N.build_block_with_outcome {
        { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 0, b = 1, c = 2 }, fixups = { side_exit = "exit", side_exit_2 = "exit" } },
        { spec = "outcome.ok", label = "ok" },
        { spec = "edge.jump_label", fixups = { target = "end_block" } },
        { spec = "outcome.side_exit", label = "exit", stamps = { exit_id = 11, resume_pc = 123 } },
    }
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    setv(a, 1, Tag.INTEGER, 0, 20)
    setv(a, 2, Tag.INTEGER, 0, 22)
    block.fn(a, out)
    checkv("outcome ADD success dst", a, 0, Tag.INTEGER, 0, 42)
    check("outcome ADD success status", tonumber(out[0].status) == Status.OK, tostring(out[0].status))
    check("outcome ADD success exit_id", tonumber(out[0].exit_id) == 0, tostring(out[0].exit_id))
end

-- Guarded ADD failure jumps to side-exit outcome.
do
    local block = N.build_block_with_outcome {
        { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 0, b = 1, c = 2 }, fixups = { side_exit = "exit", side_exit_2 = "exit" } },
        { spec = "outcome.ok", label = "ok" },
        { spec = "edge.jump_label", fixups = { target = "end_block" } },
        { spec = "outcome.side_exit", label = "exit", stamps = { exit_id = 11, resume_pc = 123 } },
    }
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    setv(a, 1, Tag.TRUE, 0, 0)
    setv(a, 2, Tag.INTEGER, 0, 22)
    block.fn(a, out)
    check("outcome ADD fail status", tonumber(out[0].status) == Status.SIDE_EXIT, tostring(out[0].status))
    check("outcome ADD fail exit_id", tonumber(out[0].exit_id) == 11, tostring(out[0].exit_id))
    check("outcome ADD fail pc", tonumber(out[0].pc) == 123, tostring(out[0].pc))
end

-- Branch labels: truthy path writes 42; falsey path writes 99.
do
    local block = N.build_block_with_outcome {
        { spec = "branch.truthy.sA.true_or_false", stamps = { a = 0 }, fixups = { true_edge = "true", false_edge = "false", false_edge_2 = "false" } },
        { spec = "value.load_i64.imm_to_sA.fall", label = "true", stamps = { a = 1, imm = 42 } },
        { spec = "edge.jump_label", fixups = { target = "done" } },
        { spec = "value.load_i64.imm_to_sA.fall", label = "false", stamps = { a = 1, imm = 99 } },
        { spec = "outcome.ok", label = "done" },
    }
    units[#units + 1] = block

    local a1, out1 = N.new_values(4), N.new_outcome()
    setv(a1, 0, Tag.INTEGER, 0, 1)
    block.fn(a1, out1)
    checkv("truthy branch true dst", a1, 1, Tag.INTEGER, 0, 42)
    check("truthy branch true status", tonumber(out1[0].status) == Status.OK)

    local a2, out2 = N.new_values(4), N.new_outcome()
    setv(a2, 0, Tag.FALSE, 0, 0)
    block.fn(a2, out2)
    checkv("truthy branch false dst", a2, 1, Tag.INTEGER, 0, 99)
    check("truthy branch false status", tonumber(out2[0].status) == Status.OK)
end

for _, u in ipairs(units) do N.free(u) end

print(string.format("JIT native outcomes: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
