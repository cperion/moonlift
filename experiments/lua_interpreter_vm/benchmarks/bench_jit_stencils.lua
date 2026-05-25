-- Microbench promoted semantic stencils against the reference interpreter step.
--
-- This measures the current harness shape: direct stencil semantic executor vs
-- decoded/switch interpreter reference.  It is not claiming native-code speed;
-- it gives every promoted stencil a repeatable before/after number and catches
-- regressions in stencil selection/executor overhead.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local Op = S.Op
local E = S.encode

local N = tonumber(arg[1]) or 5000000

local function ns_per_op(seconds, n)
    return seconds * 1e9 / n
end

local function time_loop(fn, n)
    collectgarbage("collect")
    local t0 = os.clock()
    fn(n)
    return os.clock() - t0
end

local function state()
    return { stack = {}, constants = {}, pc = 0, base = 0, top = 16 }
end

local cases = {
    {
        name = "MOVE",
        stencil = "value.move.sB_to_sA.fall",
        holes = { a = 0, b = 1 },
        word = E.ABC(Op.MOVE, 0, 1, 0),
        setup = function(st) st.stack[1] = S.value.int(99) end,
    },
    {
        name = "LOADI",
        stencil = "value.load_i64.imm_to_sA.fall",
        holes = { a = 0, imm = 123 },
        word = E.AsBx(Op.LOADI, 0, 123),
    },
    {
        name = "LOADK",
        stencil = "value.load_k.kB_to_sA.fall",
        holes = { a = 0, bx = 3 },
        word = E.ABx(Op.LOADK, 0, 3),
        setup = function(st) st.constants[3] = S.value.int(456) end,
    },
    {
        name = "ADD generic i64",
        stencil = "arith.add.generic.sB_sC_to_sA.next_or_mm",
        holes = { a = 0, b = 1, c = 2 },
        word = E.ABC(Op.ADD, 0, 1, 2),
        setup = function(st) st.stack[1] = S.value.int(20); st.stack[2] = S.value.int(22) end,
    },
    {
        name = "ADD guarded i64",
        stencil = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
        reference_stencil = "arith.add.generic.sB_sC_to_sA.next_or_mm",
        holes = { a = 0, b = 1, c = 2 },
        word = E.ABC(Op.ADD, 0, 1, 2),
        setup = function(st) st.stack[1] = S.value.int(20); st.stack[2] = S.value.int(22) end,
    },
    {
        name = "ADDI guarded i64",
        stencil = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
        holes = { a = 0, b = 1, imm = 7 },
        word = E.ABC(Op.ADDI, 0, 1, 7),
        setup = function(st) st.stack[1] = S.value.int(35) end,
    },
    {
        name = "TEST true",
        stencil = "branch.test.sA.true_or_false",
        holes = { a = 1, c = 0 },
        word = E.ABC(Op.TEST, 1, 0, 0),
        setup = function(st) st.stack[1] = S.value.int(1) end,
    },
    {
        name = "FORLOOP i64",
        stencil = "loop.forloop_i64.sA_Bx.loop_or_exit",
        holes = { a = 0, sbx = -1 },
        word = E.AsBx(Op.FORLOOP, 0, -1),
        setup = function(st)
            st.stack[0] = S.value.int(0)
            st.stack[1] = S.value.int(N + 10)
            st.stack[2] = S.value.int(1)
        end,
    },
}

print(string.format("%-18s %12s %12s %8s", "case", "interp ns", "stencil ns", "speedup"))
print(string.rep("-", 58))

for _, c in ipairs(cases) do
    local interp_state = state()
    local stencil_state = state()
    if c.setup then c.setup(interp_state); c.setup(stencil_state) end
    local exec = assert(S.get(c.stencil).execute)
    local holes = c.holes
    local word = c.word

    local ti = time_loop(function(n)
        local st = interp_state
        for _ = 1, n do S.reference_step(st, word) end
    end, N)

    local ts = time_loop(function(n)
        local st = stencil_state
        for _ = 1, n do exec(st, holes) end
    end, N)

    local ni, ns = ns_per_op(ti, N), ns_per_op(ts, N)
    print(string.format("%-18s %12.2f %12.2f %7.2fx", c.name, ni, ns, ni / ns))
end
