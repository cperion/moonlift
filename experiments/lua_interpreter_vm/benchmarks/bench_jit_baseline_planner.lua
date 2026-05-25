-- Microbench planned baseline native block vs reference interpreter sequence.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local P = require("experiments.lua_interpreter_vm.src.jit.baseline_planner")
local NRun = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not NRun.supported then
    print("baseline planner bench skipped on this platform")
    os.exit(0)
end

local Op, E = S.Op, S.encode
local N = tonumber(arg[1]) or 5000000

local words = {
    E.AsBx(Op.LOADI, 0, 20),
    E.AsBx(Op.LOADI, 1, 22),
    E.ABC(Op.ADD, 2, 0, 1),
    E.ABC(Op.MMBIN, 0, 0, 0),
    E.ABC(Op.MOVE, 3, 2, 0),
}

local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words, side_exit_id = 77, side_exit_pc = 2 }
local block = NRun.build_block_with_outcome(plan.nodes)
local vals = NRun.new_values(8)
local out = NRun.new_outcome()

local function time(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local function ns_block(dt) return dt * 1e9 / N end
local function ns_op(dt) return dt * 1e9 / (N * 4) end -- executable semantic ops, not skipped MMBIN

local ref = { stack = {}, constants = {}, pc = 0, base = 0, top = 8 }
local t_ref = time(function()
    for _ = 1, N do
        S.reference_step(ref, words[1])
        S.reference_step(ref, words[2])
        S.reference_step(ref, words[3])
        S.reference_step(ref, words[5])
    end
end)

local t_native = time(function()
    local fn = block.fn
    for _ = 1, N do fn(vals, out) end
end)

print(string.format("planned nodes: %d, body bytes: %d, wrapper bytes: %d", #plan.nodes, block.body_size, block.code_size))
print(string.format("%-18s %12s %12s", "path", "ns/block", "ns/op"))
print(string.rep("-", 46))
print(string.format("%-18s %12.2f %12.2f", "reference", ns_block(t_ref), ns_op(t_ref)))
print(string.format("%-18s %12.2f %12.2f", "planned native", ns_block(t_native), ns_op(t_native)))

NRun.free(block)
