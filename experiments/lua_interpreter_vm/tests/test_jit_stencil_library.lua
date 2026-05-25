-- Stencil library semantic smoke tests.
--
-- Each promoted semantic stencil is checked against a small reference
-- interpreter step for the same Lua 5.5 opcode shape.  Future machine-code
-- fixtures should be added behind the same contracts.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local Tag, Op = S.Tag, S.Op

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

local function base_state()
    return {
        stack = {},
        constants = {},
        pc = 10,
        base = 0,
        top = 16,
    }
end

local function compare_stencil_to_ref(name, holes, word, setup, first_slot, last_slot)
    local a = base_state()
    local b = base_state()
    if setup then setup(a); setup(b) end
    S.execute(name, a, holes)
    S.reference_step(b, word)
    local ok, where = S.same_state(a, b, first_slot, last_slot)
    check(name, ok, where)
    if a.outcome == "return1" or b.outcome == "return1" then
        check(name .. " return value", S.same_value(a.return_value, b.return_value))
    end
end

local E = S.encode

compare_stencil_to_ref(
    "value.move.sB_to_sA.fall",
    { a = 1, b = 2 },
    E.ABC(Op.MOVE, 1, 2, 0),
    function(st) st.stack[2] = S.value.int(99) end,
    0, 4)

compare_stencil_to_ref(
    "value.load_i64.imm_to_sA.fall",
    { a = 3, imm = 42 },
    E.AsBx(Op.LOADI, 3, 42),
    nil,
    0, 4)

compare_stencil_to_ref(
    "value.load_f64_bits.imm_to_sA.fall",
    { a = 3, num = -7 },
    E.AsBx(Op.LOADF, 3, -7),
    nil,
    0, 4)

compare_stencil_to_ref(
    "value.load_k.kB_to_sA.fall",
    { a = 4, bx = 6 },
    E.ABx(Op.LOADK, 4, 6),
    function(st) st.constants[6] = S.value.truev() end,
    0, 6)

compare_stencil_to_ref(
    "value.load_bool.tag_to_sA.fall",
    { a = 1, tag = Tag.FALSE, skip = false },
    E.ABC(Op.LOADFALSE, 1, 0, 0),
    nil,
    0, 3)

compare_stencil_to_ref(
    "value.load_bool.tag_to_sA.fall",
    { a = 1, tag = Tag.TRUE, skip = false },
    E.ABC(Op.LOADTRUE, 1, 0, 0),
    nil,
    0, 3)

compare_stencil_to_ref(
    "value.load_bool.tag_to_sA.fall",
    { a = 1, tag = Tag.FALSE, skip = true },
    E.ABC(Op.LFALSESKIP, 1, 0, 0),
    nil,
    0, 3)

compare_stencil_to_ref(
    "value.load_nil.sA_count.fall",
    { a = 2, count = 3 },
    E.ABC(Op.LOADNIL, 2, 3, 0),
    function(st)
        for i = 0, 6 do st.stack[i] = S.value.int(i + 1) end
    end,
    0, 6)

compare_stencil_to_ref(
    "arith.add.generic.sB_sC_to_sA.next_or_mm",
    { a = 0, b = 1, c = 2 },
    E.ABC(Op.ADD, 0, 1, 2),
    function(st)
        st.stack[1] = S.value.int(7)
        st.stack[2] = S.value.int(35)
    end,
    0, 3)

compare_stencil_to_ref(
    "arith.addi.generic.sB_imm_to_sA.next_or_mm",
    { a = 0, b = 1, imm = 5 },
    E.ABC(Op.ADDI, 0, 1, 5),
    function(st) st.stack[1] = S.value.int(37) end,
    0, 3)

compare_stencil_to_ref(
    "branch.test.sA.true_or_false",
    { a = 1, c = 0 },
    E.ABC(Op.TEST, 1, 0, 0),
    function(st) st.stack[1] = S.value.truev() end,
    0, 3)

compare_stencil_to_ref(
    "branch.test.sA.true_or_false",
    { a = 1, c = 1 },
    E.ABC(Op.TEST, 1, 0, 1),
    function(st) st.stack[1] = S.value.falsev() end,
    0, 3)

compare_stencil_to_ref(
    "cmp.lt.generic.sA_sB.true_or_false_or_mm",
    { a = 1, b = 2, c = 3 },
    E.ABC(Op.LT, 1, 2, 3),
    function(st)
        st.stack[2] = S.value.int(2)
        st.stack[3] = S.value.int(9)
    end,
    0, 4)

compare_stencil_to_ref(
    "cmp.eq.generic.sA_sB.true_or_false_or_mm",
    { a = 1, b = 2, c = 3 },
    E.ABC(Op.EQ, 1, 2, 3),
    function(st)
        st.stack[2] = S.value.int(9)
        st.stack[3] = S.value.int(9)
    end,
    0, 4)

compare_stencil_to_ref(
    "loop.forloop_i64.sA_Bx.loop_or_exit",
    { a = 0, sbx = -3 },
    E.AsBx(Op.FORLOOP, 0, -3),
    function(st)
        st.stack[0] = S.value.int(0)
        st.stack[1] = S.value.int(5)
        st.stack[2] = S.value.int(1)
    end,
    0, 4)

compare_stencil_to_ref(
    "return.one.sA",
    { a = 2 },
    E.ABC(Op.RETURN1, 2, 0, 0),
    function(st) st.stack[2] = S.value.int(123) end,
    0, 4)

compare_stencil_to_ref(
    "return.zero",
    {},
    E.ABC(Op.RETURN0, 0, 0, 0),
    nil,
    0, 4)

-- Specialized guarded stencils should match the generic interpreter on success
-- and produce explicit side exits on failed facts.
do
    local a = base_state()
    local b = base_state()
    a.stack[1], a.stack[2] = S.value.int(12), S.value.int(30)
    b.stack[1], b.stack[2] = S.value.int(12), S.value.int(30)
    S.execute("arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", a, { a = 0, b = 1, c = 2 })
    S.reference_step(b, E.ABC(Op.ADD, 0, 1, 2))
    local ok, where = S.same_state(a, b, 0, 3)
    check("arith.add_i64_guarded success", ok, where)
end

do
    local st = base_state()
    st.stack[1], st.stack[2] = S.value.truev(), S.value.int(30)
    local result = S.execute("arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", st, { a = 0, b = 1, c = 2 })
    check("arith.add_i64_guarded side exit", result == "side_exit" and st.side_exit == "guard_int_pair")
end

do
    local st = base_state()
    st.stack[1] = S.value.falsev()
    S.execute("branch.truthy.sA.true_or_false", st, { a = 1, true_pc = 111, false_pc = 222 })
    check("branch.truthy false target", st.pc == 222)
    st.stack[1] = S.value.int(1)
    S.execute("branch.truthy.sA.true_or_false", st, { a = 1, true_pc = 111, false_pc = 222 })
    check("branch.truthy true target", st.pc == 111)
end

-- Product/catalog checks: the library is a backend vocabulary, not just the
-- currently executable semantic subset.
do
    local required = {
        "entry.vm_state_to_unit",
        "edge.jump_indirect",
        "project.live_slots.bundle",
        "boundary.call_helper",
        "table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow",
        "table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow",
        "call.known_lclosure.sF_args.enter_lua",
        "super.method_self_move_call.ic1",
        "super.field_field_add_setfield.ic1",
        "super.array_get_test_forloop.ic1",
    }
    for _, name in ipairs(required) do
        local e = S.by_name[name]
        check("catalog " .. name, type(e) == "table" and type(e.ring) == "number" and type(e.effects) == "table")
    end
end

print(string.format("JIT stencil library: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
