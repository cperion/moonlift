-- Microbench executable stencil fixtures against interpreter/semantic paths.
--
-- Native numbers include one LuaJIT FFI C-call into a wrapped snippet.  The
-- production JIT will not pay this call boundary on every opcode, but these
-- numbers are real machine-code execution of the promoted stencil bytes.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local F = require("experiments.lua_interpreter_vm.src.jit.stencil_fixtures")
local NRun = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not NRun.supported then
    print("native stencil bench skipped on this platform")
    os.exit(0)
end

local Op, E, Tag = S.Op, S.encode, S.Tag
local N = tonumber(arg[1]) or 5000000

local function ns_per(dt) return dt * 1e9 / N end
local function time(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local function lua_state()
    return { stack = {}, constants = {}, pc = 0, base = 0, top = 16 }
end

local function setv(a, i, tag, aux, bits)
    a[i].tag = tag
    a[i].aux = aux or 0
    a[i].bits = bits or 0
end

local cases = {
    {
        name = "LOADI",
        spec = "value.load_i64.imm_to_sA.fall",
        holes = { a = 0, imm = 42 },
        word = E.AsBx(Op.LOADI, 0, 42),
        native_setup = function(a) end,
        lua_setup = function(st) end,
    },
    {
        name = "MOVE",
        spec = "value.move.sB_to_sA.fall",
        holes = { a = 0, b = 1 },
        word = E.ABC(Op.MOVE, 0, 1, 0),
        native_setup = function(a) setv(a, 1, Tag.INTEGER, 0, 99) end,
        lua_setup = function(st) st.stack[1] = S.value.int(99) end,
    },
    {
        name = "ADD i64 guarded",
        spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
        holes = { a = 0, b = 1, c = 2 },
        fixups = { side_exit = 0, side_exit_2 = 0 },
        word = E.ABC(Op.ADD, 0, 1, 2),
        semantic_spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
        native_setup = function(a) setv(a, 1, Tag.INTEGER, 0, 20); setv(a, 2, Tag.INTEGER, 0, 22) end,
        lua_setup = function(st) st.stack[1] = S.value.int(20); st.stack[2] = S.value.int(22) end,
    },
    {
        name = "ADDI i64 guarded",
        spec = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
        holes = { a = 0, b = 1, imm = 7 },
        fixups = { side_exit = 0 },
        word = E.ABC(Op.ADDI, 0, 1, 7),
        semantic_spec = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
        native_setup = function(a) setv(a, 1, Tag.INTEGER, 0, 35) end,
        lua_setup = function(st) st.stack[1] = S.value.int(35) end,
    },
}

print(string.format("%-18s %12s %12s %12s", "case", "interp ns", "semantic ns", "native ns"))
print(string.rep("-", 62))

local units = {}
for _, c in ipairs(cases) do
    local fx = assert(F.first_fixture(c.spec), "missing native fixture " .. c.spec)
    local unit = NRun.build_callable(fx, c.holes, c.fixups)
    units[#units + 1] = unit
    local arr = NRun.new_values(8)
    c.native_setup(arr)

    local interp = lua_state()
    c.lua_setup(interp)
    local sem = lua_state()
    c.lua_setup(sem)
    local sem_entry = S.get(c.semantic_spec or c.spec)

    local ti = time(function()
        for _ = 1, N do S.reference_step(interp, c.word) end
    end)
    local ts = time(function()
        for _ = 1, N do sem_entry.execute(sem, c.holes) end
    end)
    local tn = time(function()
        local fn = unit.fn
        for _ = 1, N do fn(arr) end
    end)

    print(string.format("%-18s %12.2f %12.2f %12.2f", c.name, ns_per(ti), ns_per(ts), ns_per(tn)))
end

for _, u in ipairs(units) do NRun.free(u) end
