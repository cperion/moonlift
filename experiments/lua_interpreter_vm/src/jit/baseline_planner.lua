-- Baseline bytecode-range planner for the v0 copy-and-patch JIT.
--
-- This is intentionally small: it turns a decoded Lua 5.5 bytecode range into
-- native block nodes consumable by native_runner.build_block_with_outcome().
-- It is a StencilPlan producer, not a backend.

local bit = require("bit")
local const = require("experiments.lua_interpreter_vm.src.constants")

local M = {}

local Op = const.Op
M.Op = Op

local function decode(word)
    return {
        word = word,
        op = bit.band(word, 127),
        a = bit.band(bit.rshift(word, 7), 255),
        b = bit.band(bit.rshift(word, 16), 255),
        c = bit.band(bit.rshift(word, 24), 255),
        k = bit.band(bit.rshift(word, 15), 1),
        bx = bit.band(bit.rshift(word, 15), 131071),
        sbx = bit.band(bit.rshift(word, 15), 131071) - 65535,
    }
end

M.decode = decode

local function pc_label(pc)
    return "pc" .. tostring(pc)
end

M.pc_label = pc_label

local function word_at(words, pc)
    return words[pc + 1]
end

local function append_side_exit(nodes, plan)
    nodes[#nodes + 1] = { spec = "outcome.ok", label = plan.end_label }
    nodes[#nodes + 1] = { spec = "edge.jump_label", fixups = { target = "end_block" } }
    nodes[#nodes + 1] = {
        spec = "outcome.side_exit",
        label = plan.side_exit_label,
        stamps = { exit_id = plan.side_exit_id or 1, resume_pc = plan.side_exit_pc or plan.start_pc },
    }
end

local function target_label_for(plan, target_pc)
    if target_pc >= plan.end_pc then return plan.end_label end
    return pc_label(target_pc)
end

local function plan_one(plan, nodes, pc, d)
    local label = pc_label(pc)
    local op = d.op

    if op == Op.LOADI then
        nodes[#nodes + 1] = { label = label, spec = "value.load_i64.imm_to_sA.fall", stamps = { a = d.a, imm = d.sbx } }
        return pc + 1
    end

    if op == Op.LOADTRUE then
        nodes[#nodes + 1] = { label = label, spec = "value.load_bool.tag_to_sA.fall", stamps = { a = d.a, tag = 2 } }
        return pc + 1
    end

    if op == Op.LOADFALSE or op == Op.LFALSESKIP then
        nodes[#nodes + 1] = { label = label, spec = "value.load_bool.tag_to_sA.fall", stamps = { a = d.a, tag = 1 } }
        return pc + (op == Op.LFALSESKIP and 2 or 1)
    end

    if op == Op.LOADNIL then
        nodes[#nodes + 1] = { label = label, spec = "value.load_nil.sA_count.fall", stamps = { a = d.a, count_plus_one = d.b + 1 } }
        return pc + 1
    end

    if op == Op.LOADK then
        local k = assert(plan.constants and plan.constants[d.bx], "missing constant " .. tostring(d.bx))
        nodes[#nodes + 1] = { label = label, spec = "value.load_k.kB_to_sA.fall", stamps = { a = d.a, tag = k.tag or 0, aux = k.aux or 0, bits = k.bits or 0 } }
        return pc + 1
    end

    if op == Op.GETUPVAL then
        local up = assert(plan.upvalue_ptrs and plan.upvalue_ptrs[d.b], "missing upvalue pointer " .. tostring(d.b))
        nodes[#nodes + 1] = { label = label, spec = "value.getupval.generic.sU_to_sA.fall", stamps = { a = d.a, upvalue_ptr = up } }
        return pc + 1
    end

    if op == Op.GETFIELD then
        local ic = assert(plan.ics and plan.ics[pc], "missing GETFIELD ic at pc " .. tostring(pc))
        nodes[#nodes + 1] = {
            label = label,
            spec = "table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow",
            stamps = { a = d.a, t = d.b, table_ptr = ic.table_ptr, value_ptr = ic.value_ptr },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label },
        }
        return pc + 1
    end

    if op == Op.GETTABLE then
        local ic = assert(plan.ics and plan.ics[pc], "missing GETTABLE ic at pc " .. tostring(pc))
        nodes[#nodes + 1] = {
            label = label,
            spec = "table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow",
            stamps = { a = d.a, t = d.b, k = d.c, table_ptr = ic.table_ptr, expected_key = assert(ic.expected_key, "GETTABLE ic expected_key"), value_ptr = ic.value_ptr },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label, side_exit_3 = plan.side_exit_label, side_exit_4 = plan.side_exit_label },
        }
        return pc + 1
    end

    if op == Op.SETFIELD then
        if d.k ~= 0 then return nil, "SETFIELD constant value not supported at pc " .. tostring(pc) end
        local ic = assert(plan.ics and plan.ics[pc], "missing SETFIELD ic at pc " .. tostring(pc))
        nodes[#nodes + 1] = {
            label = label,
            spec = "table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier",
            stamps = { t = d.a, v = d.c, table_ptr = ic.table_ptr, value_ptr = ic.value_ptr },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label },
        }
        return pc + 1
    end

    if op == Op.SETTABLE then
        local ic = assert(plan.ics and plan.ics[pc], "missing SETTABLE ic at pc " .. tostring(pc))
        nodes[#nodes + 1] = {
            label = label,
            spec = "table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier",
            stamps = { t = d.b, k = d.c, v = d.a, table_ptr = ic.table_ptr, expected_key = assert(ic.expected_key, "SETTABLE ic expected_key"), value_ptr = ic.value_ptr },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label, side_exit_3 = plan.side_exit_label, side_exit_4 = plan.side_exit_label },
        }
        return pc + 1
    end

    if op == Op.SELF then
        local ic = assert(plan.ics and plan.ics[pc], "missing SELF ic at pc " .. tostring(pc))
        nodes[#nodes + 1] = {
            label = label,
            spec = "table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow",
            stamps = { obj = d.b, self = d.a + 1, func = d.a, table_ptr = ic.table_ptr, value_ptr = ic.value_ptr },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label },
        }
        return pc + 1
    end

    if op == Op.MOVE then
        nodes[#nodes + 1] = { label = label, spec = "value.move.sB_to_sA.fall", stamps = { a = d.a, b = d.b } }
        return pc + 1
    end

    if op == Op.ADD then
        nodes[#nodes + 1] = {
            label = label,
            spec = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
            stamps = { a = d.a, b = d.b, c = d.c },
            fixups = { side_exit = plan.side_exit_label, side_exit_2 = plan.side_exit_label },
        }
        -- Lua 5.5 arithmetic success skips the following MMBIN instruction.
        return pc + 2
    end

    if op == Op.ADDI then
        nodes[#nodes + 1] = {
            label = label,
            spec = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
            stamps = { a = d.a, b = d.b, imm = d.c },
            fixups = { side_exit = plan.side_exit_label },
        }
        return pc + 2
    end

    if op == Op.JMP then
        nodes[#nodes + 1] = {
            label = label,
            spec = "edge.jump_label",
            fixups = { target = target_label_for(plan, pc + d.sbx) },
        }
        return pc + 1
    end

    if op == Op.TEST then
        -- Interpreter contract: TEST advances by either 1 or 2.  The native
        -- fixture branches on truthiness, so map true/false to the same target
        -- PCs as op_test.
        local true_pc, false_pc
        if d.c == 0 then
            true_pc, false_pc = pc + 1, pc + 2
        else
            true_pc, false_pc = pc + 2, pc + 1
        end
        nodes[#nodes + 1] = {
            label = label,
            spec = "branch.test.sA.true_or_false",
            stamps = { a = d.a },
            fixups = {
                true_edge = target_label_for(plan, true_pc),
                false_edge = target_label_for(plan, false_pc),
                false_edge_2 = target_label_for(plan, false_pc),
            },
        }
        return pc + 1
    end

    if op == Op.CALL then
        nodes[#nodes + 1] = { label = label, spec = "call.generic.sF_args.boundary", fixups = { call_boundary = "call_boundary_pc" .. tostring(pc) } }
        nodes[#nodes + 1] = {
            label = "call_boundary_pc" .. tostring(pc),
            spec = "outcome.call_boundary",
            stamps = { call_id = plan.call_id or 1, resume_pc = pc },
        }
        nodes[#nodes + 1] = { spec = "edge.jump_label", fixups = { target = "end_block" } }
        return plan.end_pc
    end

    if op == Op.RETURN0 or op == Op.RETURN1 then
        nodes[#nodes + 1] = { label = label, spec = "edge.jump_label", fixups = { target = plan.end_label } }
        return plan.end_pc
    end

    return nil, "unsupported opcode " .. tostring(op) .. " at pc " .. tostring(pc)
end

function M.plan_range(spec)
    assert(type(spec) == "table", "plan_range spec required")
    local words = assert(spec.words, "plan_range words required")
    local start_pc = spec.start_pc or 0
    local end_pc = spec.end_pc or #words
    local plan = {
        kind = "BaselinePlan",
        start_pc = start_pc,
        end_pc = end_pc,
        end_label = spec.end_label or "pc_end",
        side_exit_label = spec.side_exit_label or "side_exit",
        side_exit_id = spec.side_exit_id or 1,
        side_exit_pc = spec.side_exit_pc or start_pc,
        constants = spec.constants,
        upvalue_ptrs = spec.upvalue_ptrs,
        ics = spec.ics,
        call_id = spec.call_id,
        nodes = {},
    }

    local pc = start_pc
    while pc < end_pc do
        local word = word_at(words, pc)
        if word == nil then return nil, "missing instruction at pc " .. tostring(pc) end
        local next_pc, err = plan_one(plan, plan.nodes, pc, decode(word))
        if not next_pc then return nil, err end
        if next_pc <= pc then return nil, "planner did not advance at pc " .. tostring(pc) end
        pc = next_pc
    end

    append_side_exit(plan.nodes, plan)
    return plan
end

function M.assert_plan_range(spec)
    local plan, err = M.plan_range(spec)
    if not plan then error(err) end
    return plan
end

return M
