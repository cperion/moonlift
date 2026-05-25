-- Microbench planned object/table/call-boundary native block.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local P = require("experiments.lua_interpreter_vm.src.jit.baseline_planner")
local NRun = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not NRun.supported then
    print("object baseline bench skipped on this platform")
    os.exit(0)
end

local Tag, Op, E = S.Tag, S.Op, S.encode
local N = tonumber(arg[1]) or 5000000

local function setv(a, i, tag, aux, bits)
    a[i].tag = tag
    a[i].aux = aux or 0
    a[i].bits = bits or 0
end

local table_id = 0x123456
local field = NRun.new_values(1)
local elem = NRun.new_values(1)
local method = NRun.new_values(1)
setv(field, 0, Tag.INTEGER, 1, 11)
setv(elem, 0, Tag.INTEGER, 2, 22)
setv(method, 0, Tag.LCLOSURE, 0, 0x77)

local words = {
    E.ABC(Op.GETFIELD, 0, 1, 0),
    E.ABC(Op.SETFIELD, 1, 0, 2),
    E.ABC(Op.GETTABLE, 3, 1, 4),
    E.ABC(Op.SETTABLE, 5, 1, 4),
    E.ABC(Op.SELF, 6, 1, 4),
    E.ABC(Op.CALL, 6, 2, 1),
}

local plan = P.assert_plan_range {
    words = words,
    start_pc = 0,
    end_pc = #words,
    call_id = 99,
    ics = {
        [0] = { table_ptr = table_id, value_ptr = field },
        [1] = { table_ptr = table_id, value_ptr = field },
        [2] = { table_ptr = table_id, expected_key = 5, value_ptr = elem },
        [3] = { table_ptr = table_id, expected_key = 5, value_ptr = elem },
        [4] = { table_ptr = table_id, value_ptr = method },
    },
}

local block = NRun.build_block_with_outcome(plan.nodes)
local vals, out = NRun.new_values(10), NRun.new_outcome()
setv(vals, 1, Tag.TABLE, 0, table_id)
setv(vals, 2, Tag.INTEGER, 3, 33)
setv(vals, 4, Tag.INTEGER, 0, 5)
setv(vals, 5, Tag.INTEGER, 4, 44)

local function time(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local dt = time(function()
    local fn = block.fn
    for _ = 1, N do fn(vals, out) end
end)

local ns_block = dt * 1e9 / N
local ns_op = ns_block / #words
print(string.format("planned object nodes: %d, body bytes: %d, wrapper bytes: %d", #plan.nodes, block.body_size, block.code_size))
print(string.format("native object/call boundary: %.2f ns/block, %.2f ns/op", ns_block, ns_op))

NRun.free(block)
