-- Microbench one native executable unit containing multiple stencils.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local NRun = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not NRun.supported then
    print("native block bench skipped on this platform")
    os.exit(0)
end

local Op, E = S.Op, S.encode
local N = tonumber(arg[1]) or 5000000

local function ns_per(dt, ops_per_iter) return dt * 1e9 / (N * (ops_per_iter or 1)) end
local function time(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local nodes = {
    { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 0, imm = 20 } },
    { spec = "value.load_i64.imm_to_sA.fall", stamps = { a = 1, imm = 22 } },
    { spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", stamps = { a = 2, b = 0, c = 1 } },
    { spec = "value.move.sB_to_sA.fall", stamps = { a = 3, b = 2 } },
}
local block = NRun.build_block(nodes)
local arr = NRun.new_values(8)

local words = {
    E.AsBx(Op.LOADI, 0, 20),
    E.AsBx(Op.LOADI, 1, 22),
    E.ABC(Op.ADD, 2, 0, 1),
    E.ABC(Op.MOVE, 3, 2, 0),
}

local ref = { stack = {}, constants = {}, pc = 0, base = 0, top = 8 }
local sem = { stack = {}, constants = {}, pc = 0, base = 0, top = 8 }

local t_ref = time(function()
    local st = ref
    for _ = 1, N do
        S.reference_step(st, words[1])
        S.reference_step(st, words[2])
        S.reference_step(st, words[3])
        S.reference_step(st, words[4])
    end
end)

local t_sem = time(function()
    local st = sem
    for _ = 1, N do
        S.execute("value.load_i64.imm_to_sA.fall", st, nodes[1].stamps)
        S.execute("value.load_i64.imm_to_sA.fall", st, nodes[2].stamps)
        S.execute("arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", st, nodes[3].stamps)
        S.execute("value.move.sB_to_sA.fall", st, nodes[4].stamps)
    end
end)

local t_native = time(function()
    local fn = block.fn
    for _ = 1, N do fn(arr) end
end)

print(string.format("block body bytes: %d, wrapper bytes: %d", block.body_size, block.code_size))
print(string.format("%-18s %12s %12s", "path", "ns/block", "ns/op"))
print(string.rep("-", 46))
print(string.format("%-18s %12.2f %12.2f", "interpreter", ns_per(t_ref), ns_per(t_ref, 4)))
print(string.format("%-18s %12.2f %12.2f", "semantic", ns_per(t_sem), ns_per(t_sem, 4)))
print(string.format("%-18s %12.2f %12.2f", "native block", ns_per(t_native), ns_per(t_native, 4)))

NRun.free(block)
