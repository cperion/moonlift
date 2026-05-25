-- Baseline planner tests: bytecode words -> native executable block nodes.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local P = require("experiments.lua_interpreter_vm.src.jit.baseline_planner")
local N = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not N.supported then
    print("JIT baseline planner: native portion skipped on " .. tostring(ffi.os) .. "/" .. tostring(ffi.arch))
    os.exit(0)
end

local Tag, Op, E = S.Tag, S.Op, S.encode
local Status = N.OutcomeStatus
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

-- Straight-line range with Lua 5.5 arithmetic skip:
--   pc0 LOADI R0,20
--   pc1 LOADI R1,22
--   pc2 ADD   R2,R0,R1
--   pc3 MMBIN placeholder skipped by ADD success
--   pc4 MOVE  R3,R2
do
    local words = {
        E.AsBx(Op.LOADI, 0, 20),
        E.AsBx(Op.LOADI, 1, 22),
        E.ABC(Op.ADD, 2, 0, 1),
        E.ABC(Op.MMBIN, 0, 0, 0),
        E.ABC(Op.MOVE, 3, 2, 0),
    }
    local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words, side_exit_id = 77, side_exit_pc = 2 }
    check("straight plan kind", plan.kind == "BaselinePlan")
    check("straight plan nodes", #plan.nodes == 7, tostring(#plan.nodes)) -- 4 op nodes + ok + jump + side_exit
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(8), N.new_outcome()
    block.fn(a, out)
    checkv("straight R0", a, 0, Tag.INTEGER, 0, 20)
    checkv("straight R1", a, 1, Tag.INTEGER, 0, 22)
    checkv("straight R2", a, 2, Tag.INTEGER, 0, 42)
    checkv("straight R3", a, 3, Tag.INTEGER, 0, 42)
    check("straight outcome OK", tonumber(out[0].status) == Status.OK, tostring(out[0].status))
end

-- Guard failure from planned ADDI exits to observable side-exit outcome.
do
    local words = {
        E.ABC(Op.ADDI, 0, 1, 7),
        E.ABC(Op.MMBINI, 0, 0, 0),
    }
    local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words, side_exit_id = 88, side_exit_pc = 0 }
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    setv(a, 1, Tag.TRUE, 0, 0)
    block.fn(a, out)
    check("addi failure side exit", tonumber(out[0].status) == Status.SIDE_EXIT, tostring(out[0].status))
    check("addi failure exit id", tonumber(out[0].exit_id) == 88, tostring(out[0].exit_id))
    check("addi failure resume pc", tonumber(out[0].pc) == 0, tostring(out[0].pc))
end

-- Planned JMP skips over a bad LOADI.
do
    local words = {
        E.AsBx(Op.LOADI, 0, 1),
        E.AsBx(Op.JMP, 0, 2), -- pc1 -> pc3
        E.AsBx(Op.LOADI, 0, 99),
        E.AsBx(Op.LOADI, 1, 42),
    }
    local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words }
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    block.fn(a, out)
    checkv("jmp keeps R0", a, 0, Tag.INTEGER, 0, 1)
    checkv("jmp target R1", a, 1, Tag.INTEGER, 0, 42)
    check("jmp outcome OK", tonumber(out[0].status) == Status.OK)
end

-- Planned scalar loads: LOADTRUE, LOADFALSE/LFALSESKIP, LOADNIL, LOADK, GETUPVAL.
do
    local up = N.new_values(1)
    setv(up, 0, Tag.INTEGER, 12, 777)
    local words = {
        E.ABC(Op.LOADTRUE, 0, 0, 0),
        E.ABC(Op.LOADFALSE, 1, 0, 0),
        E.ABC(Op.LOADNIL, 2, 2, 0),
        E.ABx(Op.LOADK, 5, 3),
        E.ABC(Op.GETUPVAL, 6, 0, 0),
    }
    local plan = P.assert_plan_range {
        words = words,
        start_pc = 0,
        end_pc = #words,
        constants = { [3] = S.value.int(123) },
        upvalue_ptrs = { [0] = up },
    }
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(8), N.new_outcome()
    block.fn(a, out)
    checkv("planned LOADTRUE", a, 0, Tag.TRUE, 0, 0)
    checkv("planned LOADFALSE", a, 1, Tag.FALSE, 0, 0)
    checkv("planned LOADNIL 2", a, 2, Tag.NIL, 0, 0)
    checkv("planned LOADNIL 3", a, 3, Tag.NIL, 0, 0)
    checkv("planned LOADNIL 4", a, 4, Tag.NIL, 0, 0)
    checkv("planned LOADK", a, 5, Tag.INTEGER, 0, 123)
    checkv("planned GETUPVAL", a, 6, Tag.INTEGER, 12, 777)
    check("planned scalar outcome OK", tonumber(out[0].status) == Status.OK)
end

-- Planned LFALSESKIP skips the following instruction.
do
    local words = {
        E.ABC(Op.LFALSESKIP, 0, 0, 0),
        E.AsBx(Op.LOADI, 1, 99),
        E.AsBx(Op.LOADI, 1, 42),
    }
    local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words }
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    block.fn(a, out)
    checkv("planned LFALSESKIP false", a, 0, Tag.FALSE, 0, 0)
    checkv("planned LFALSESKIP target", a, 1, Tag.INTEGER, 0, 42)
    check("planned LFALSESKIP outcome OK", tonumber(out[0].status) == Status.OK)
end

-- Planned TEST follows the interpreter pc+1/pc+2 convention.  For c=1,
-- truthy skips pc1 and executes pc2.
do
    local words = {
        E.ABC(Op.TEST, 0, 0, 1),
        E.AsBx(Op.LOADI, 1, 99),
        E.AsBx(Op.LOADI, 1, 42),
    }
    local plan = P.assert_plan_range { words = words, start_pc = 0, end_pc = #words }
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(4), N.new_outcome()
    setv(a, 0, Tag.INTEGER, 0, 1)
    block.fn(a, out)
    checkv("test truthy R1", a, 1, Tag.INTEGER, 0, 42)
    check("test outcome OK", tonumber(out[0].status) == Status.OK)
end

-- Planned object/table IC stencils and CALL boundary.
do
    local table_id = 0x123456
    local field = N.new_values(1)
    local elem = N.new_values(1)
    local method = N.new_values(1)
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
    local block = N.build_block_with_outcome(plan.nodes)
    units[#units + 1] = block
    local a, out = N.new_values(10), N.new_outcome()
    setv(a, 1, Tag.TABLE, 0, table_id)
    setv(a, 2, Tag.INTEGER, 3, 33)
    setv(a, 4, Tag.INTEGER, 0, 5)
    setv(a, 5, Tag.INTEGER, 4, 44)
    block.fn(a, out)
    checkv("planned GETFIELD dst", a, 0, Tag.INTEGER, 1, 11)
    checkv("planned SETFIELD field", field, 0, Tag.INTEGER, 3, 33)
    checkv("planned GETTABLE dst", a, 3, Tag.INTEGER, 2, 22)
    checkv("planned SETTABLE elem", elem, 0, Tag.INTEGER, 4, 44)
    checkv("planned SELF func", a, 6, Tag.LCLOSURE, 0, 0x77)
    checkv("planned SELF receiver", a, 7, Tag.TABLE, 0, table_id)
    check("planned CALL boundary", tonumber(out[0].status) == Status.CALL_BOUNDARY, tostring(out[0].status))
    check("planned CALL id", tonumber(out[0].exit_id) == 99, tostring(out[0].exit_id))
end

do
    local plan, err = P.plan_range { words = { E.ABC(Op.NEWTABLE, 0, 0, 0) }, start_pc = 0, end_pc = 1 }
    check("unsupported rejected", plan == nil and tostring(err):match("unsupported opcode") ~= nil, tostring(err))
end

for _, u in ipairs(units) do N.free(u) end

print(string.format("JIT baseline planner: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
