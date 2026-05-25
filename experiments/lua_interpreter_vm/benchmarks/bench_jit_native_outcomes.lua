-- Microbench native blocks with observable outcomes and branch labels.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local NRun = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not NRun.supported then
    print("native outcome bench skipped on this platform")
    os.exit(0)
end

local Tag = S.Tag
local N = tonumber(arg[1]) or 5000000

local function ns(dt) return dt * 1e9 / N end
local function time(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local function setv(a, i, tag, aux, bits)
    a[i].tag = tag
    a[i].aux = aux or 0
    a[i].bits = bits or 0
end

local add_block = NRun.build_block_with_outcome {
    { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 0, b = 1, c = 2 }, fixups = { side_exit = "exit", side_exit_2 = "exit" } },
    { spec = "outcome.ok", label = "ok" },
    { spec = "edge.jump_label", fixups = { target = "end_block" } },
    { spec = "outcome.side_exit", label = "exit", stamps = { exit_id = 11, resume_pc = 123 } },
}

local branch_block = NRun.build_block_with_outcome {
    { spec = "branch.truthy.sA.true_or_false", stamps = { a = 0 }, fixups = { true_edge = "true", false_edge = "false", false_edge_2 = "false" } },
    { spec = "value.load_i64.imm_to_sA.fall", label = "true", stamps = { a = 1, imm = 42 } },
    { spec = "edge.jump_label", fixups = { target = "done" } },
    { spec = "value.load_i64.imm_to_sA.fall", label = "false", stamps = { a = 1, imm = 99 } },
    { spec = "outcome.ok", label = "done" },
}

local add_ok_vals, add_exit_vals = NRun.new_values(4), NRun.new_values(4)
setv(add_ok_vals, 1, Tag.INTEGER, 0, 20); setv(add_ok_vals, 2, Tag.INTEGER, 0, 22)
setv(add_exit_vals, 1, Tag.TRUE, 0, 0); setv(add_exit_vals, 2, Tag.INTEGER, 0, 22)
local branch_true_vals, branch_false_vals = NRun.new_values(4), NRun.new_values(4)
setv(branch_true_vals, 0, Tag.INTEGER, 0, 1)
setv(branch_false_vals, 0, Tag.FALSE, 0, 0)
local out = NRun.new_outcome()

local cases = {
    { name = "add ok outcome", block = add_block, vals = add_ok_vals },
    { name = "add side exit", block = add_block, vals = add_exit_vals },
    { name = "branch true", block = branch_block, vals = branch_true_vals },
    { name = "branch false", block = branch_block, vals = branch_false_vals },
}

print(string.format("%-18s %12s", "case", "ns/block"))
print(string.rep("-", 32))
for _, c in ipairs(cases) do
    local fn = c.block.fn
    local vals = c.vals
    local dt = time(function()
        for _ = 1, N do fn(vals, out) end
    end)
    print(string.format("%-18s %12.2f", c.name, ns(dt)))
end

NRun.free(add_block)
NRun.free(branch_block)
