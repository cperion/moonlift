-- Moonlift Lua VM JIT stencil library v0.
--
-- This is the first executable library surface for the copy-and-patch JIT.
-- It records the curated stencil vocabulary and gives the initially promoted
-- stencils a plain-Lua semantic executor.  The executor is not the hot path;
-- it is the correctness/microbench harness that every future byte stencil must
-- match before promotion.

local bit = require("bit")
local const = require("experiments.lua_interpreter_vm.src.constants")
local miner = require("experiments.lua_interpreter_vm.src.jit.miner_contracts")

local M = {}

local Tag, Op = const.Tag, const.Op
M.Tag, M.Op = Tag, Op

local function clone_value(v)
    if not v then return { tag = Tag.NIL, aux = 0, bits = 0 } end
    return { tag = v.tag or Tag.NIL, aux = v.aux or 0, bits = v.bits or 0, ref = v.ref }
end

local function v_nil() return { tag = Tag.NIL, aux = 0, bits = 0 } end
local function v_false() return { tag = Tag.FALSE, aux = 0, bits = 0 } end
local function v_true() return { tag = Tag.TRUE, aux = 0, bits = 0 } end
local function v_int(x) return { tag = Tag.INTEGER, aux = 0, bits = x } end
local function v_num(x) return { tag = Tag.NUM, aux = 0, bits = x } end

M.value = {
    clone = clone_value,
    nilv = v_nil,
    falsev = v_false,
    truev = v_true,
    int = v_int,
    num = v_num,
}

local function truthy(v)
    return v and v.tag ~= Tag.NIL and v.tag ~= Tag.FALSE
end
M.truthy = truthy

local function slot(state, s)
    return (state.base or 0) + s
end

local function read_slot(state, s)
    return state.stack[slot(state, s)] or v_nil()
end

local function write_slot(state, s, v)
    state.stack[slot(state, s)] = clone_value(v)
end

local function same_value(a, b)
    a, b = a or v_nil(), b or v_nil()
    return a.tag == b.tag and a.aux == b.aux and a.bits == b.bits and a.ref == b.ref
end
M.same_value = same_value

function M.clone_state(state)
    local out = {
        stack = {},
        constants = {},
        upvalues = {},
        pc = state.pc or 0,
        base = state.base or 0,
        top = state.top or 0,
        outcome = state.outcome,
        side_exit = state.side_exit,
        error = state.error,
    }
    for k, v in pairs(state.stack or {}) do out.stack[k] = clone_value(v) end
    for k, v in pairs(state.constants or {}) do out.constants[k] = clone_value(v) end
    for k, v in pairs(state.upvalues or {}) do out.upvalues[k] = clone_value(v) end
    return out
end

function M.same_state(a, b, first_slot, last_slot)
    if (a.pc or 0) ~= (b.pc or 0) then return false, "pc" end
    if (a.side_exit or false) ~= (b.side_exit or false) then return false, "side_exit" end
    if (a.error or false) ~= (b.error or false) then return false, "error" end
    if (a.outcome or "") ~= (b.outcome or "") then return false, "outcome" end
    first_slot = first_slot or 0
    last_slot = last_slot or math.max(a.top or 0, b.top or 0, 12)
    for i = first_slot, last_slot do
        if not same_value(a.stack[i], b.stack[i]) then return false, "stack[" .. tostring(i) .. "]" end
    end
    return true
end

local function pat(name, class, ops, effects, exits, projections, notes)
    return miner.StatePattern {
        name = name,
        class = class,
        ops = ops,
        effects = effects,
        exits = exits,
        projections = projections,
        notes = notes,
    }
end

local StateOp = miner.StateOp

local library = { by_name = {}, entries = {} }

local function add(spec)
    assert(type(spec.name) == "string" and spec.name ~= "", "stencil name required")
    assert(not library.by_name[spec.name], "duplicate stencil " .. spec.name)
    spec.kind = "CodeStencilSpec"
    spec.status = spec.status or (spec.execute and "semantic" or "catalog")
    spec.effects = spec.effects or { "PURE" }
    spec.holes = spec.holes or {}
    spec.relocs = spec.relocs or {}
    spec.payloads = spec.payloads or {}
    spec.config_axes = spec.config_axes or {}
    spec.clobbers = spec.clobbers or {}
    spec.pattern = spec.pattern or pat(spec.name, spec.family or "unknown", {}, spec.effects)
    library.entries[#library.entries + 1] = spec
    library.by_name[spec.name] = spec
    return spec
end

-- Ring 0: execution skeleton/catalog stencils.
add { name = "entry.vm_state_to_unit", ring = 0, family = "entry", status = "catalog", effects = { "PURE" } }
add { name = "exit.to_interpreter_next", ring = 0, family = "exit", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "exit.to_interpreter_jump", ring = 0, family = "exit", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "outcome.write_status", ring = 0, family = "outcome", status = "catalog", effects = { "MATERIALIZE_VM_STATE" } }
add { name = "outcome.ok", ring = 0, family = "outcome", status = "catalog", effects = { "MATERIALIZE_VM_STATE" } }
add { name = "outcome.side_exit", ring = 0, family = "outcome", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "TARGET" } }
add { name = "outcome.call_boundary", ring = 0, family = "outcome", status = "catalog", effects = { "MAY_CALL_LUA", "MAY_CALL_NATIVE", "MATERIALIZE_VM_STATE" }, projections = { "ROOTS", "RESUME" } }
add { name = "edge.jump_indirect", ring = 0, family = "edge", status = "catalog", effects = { "MAY_BRANCH" }, relocs = { "edge_target_load" } }
add { name = "edge.jump_label", ring = 0, family = "edge", status = "catalog", effects = { "MAY_BRANCH" }, relocs = { "branch_label" } }
add { name = "edge.resolve_miss", ring = 0, family = "edge", status = "catalog", effects = { "MAY_BRANCH" }, projections = { "TARGET" } }
add { name = "project.slot.bits_int_to_slot", ring = 0, family = "projection", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "project.slot.value_regs_to_slot", ring = 0, family = "projection", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "project.live_slots.bundle", ring = 0, family = "projection", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "project.frame.pc_top", ring = 0, family = "projection", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "RESUME" } }
add { name = "project.thread.top", ring = 0, family = "projection", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }
add { name = "boundary.call_helper", ring = 0, family = "boundary", status = "catalog", effects = { "MAY_CALL_HELPER" }, projections = { "ROOTS", "RESUME" } }
add { name = "boundary.return_to_vm_loop", ring = 0, family = "boundary", status = "catalog", effects = { "MATERIALIZE_VM_STATE" }, projections = { "INTERPRETER" } }

-- Ring 1: generic roots with semantic executors for the first baseline subset.
add {
    name = "value.move.sB_to_sA.fall",
    ring = 1,
    family = "value.move",
    effects = { "PURE" },
    holes = { "a", "b" },
    config_axes = { "src=slot", "dst=slot", "cont=fall" },
    pattern = pat("move_slot", "value.move", {
        StateOp("ReadSlot", { slot = "b" }),
        StateOp("WriteSlot", { slot = "a" }),
    }, { "PURE" }),
    execute = function(state, h)
        write_slot(state, h.a, read_slot(state, h.b))
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "value.load_i64.imm_to_sA.fall",
    ring = 1,
    family = "value.write",
    effects = { "PURE" },
    holes = { "a", "imm" },
    config_axes = { "dst=slot", "imm=i64", "cont=fall" },
    pattern = pat("load_i64", "value.write", {
        StateOp("ConstInt", { value = "imm" }),
        StateOp("WriteSlot", { slot = "a" }),
    }, { "PURE" }),
    execute = function(state, h)
        write_slot(state, h.a, v_int(h.imm or 0))
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "value.load_f64_bits.imm_to_sA.fall",
    ring = 1,
    family = "value.write",
    effects = { "PURE" },
    holes = { "a", "num" },
    config_axes = { "dst=slot", "imm=f64", "cont=fall" },
    execute = function(state, h)
        write_slot(state, h.a, v_num(h.num or 0))
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "value.load_k.kB_to_sA.fall",
    ring = 1,
    family = "value.write",
    effects = { "PURE" },
    holes = { "a", "bx" },
    config_axes = { "src=constant", "dst=slot", "cont=fall" },
    execute = function(state, h)
        write_slot(state, h.a, state.constants[h.bx] or v_nil())
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "value.load_bool.tag_to_sA.fall",
    ring = 1,
    family = "value.write",
    effects = { "PURE" },
    holes = { "a", "tag", "skip" },
    config_axes = { "dst=slot", "value=bool", "cont=fall" },
    execute = function(state, h)
        write_slot(state, h.a, h.tag == Tag.TRUE and v_true() or v_false())
        state.pc = (state.pc or 0) + (h.skip and 2 or 1)
        return "fall"
    end,
}

add {
    name = "value.load_nil.sA_count.fall",
    ring = 1,
    family = "value.write",
    effects = { "PURE" },
    holes = { "a", "count" },
    config_axes = { "dst=slot_range", "value=nil", "cont=fall" },
    execute = function(state, h)
        for i = h.a, h.a + (h.count or 0) do write_slot(state, i, v_nil()) end
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "value.getupval.generic.sU_to_sA.fall",
    ring = 1,
    family = "value.upvalue",
    effects = { "PURE" },
    holes = { "a", "b" },
    config_axes = { "src=upvalue", "dst=slot", "cont=fall" },
    execute = function(state, h)
        local uv = assert(state.upvalues and state.upvalues[h.b], "missing upvalue " .. tostring(h.b))
        write_slot(state, h.a, uv)
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "arith.add.generic.sB_sC_to_sA.next_or_mm",
    ring = 1,
    family = "arith.generic",
    effects = { "MAY_BRANCH", "MAY_CALL_METAMETHOD" },
    holes = { "a", "b", "c" },
    exits = { "METAMETHOD" },
    execute = function(state, h)
        local lhs, rhs = read_slot(state, h.b), read_slot(state, h.c)
        if lhs.tag == Tag.INTEGER and rhs.tag == Tag.INTEGER then
            write_slot(state, h.a, v_int(lhs.bits + rhs.bits))
            state.pc = (state.pc or 0) + 2
            return "fall"
        end
        if lhs.tag == Tag.NUM and rhs.tag == Tag.NUM then
            write_slot(state, h.a, v_num(lhs.bits + rhs.bits))
            state.pc = (state.pc or 0) + 2
            return "fall"
        end
        state.pc = (state.pc or 0) + 1
        state.side_exit = "metamethod_binary"
        return "side_exit"
    end,
}

add {
    name = "arith.addi.generic.sB_imm_to_sA.next_or_mm",
    ring = 1,
    family = "arith.generic",
    effects = { "MAY_BRANCH", "MAY_CALL_METAMETHOD" },
    holes = { "a", "b", "imm" },
    exits = { "METAMETHOD" },
    execute = function(state, h)
        local lhs = read_slot(state, h.b)
        if lhs.tag == Tag.INTEGER then
            write_slot(state, h.a, v_int(lhs.bits + (h.imm or 0)))
            state.pc = (state.pc or 0) + 2
            return "fall"
        end
        if lhs.tag == Tag.NUM then
            write_slot(state, h.a, v_num(lhs.bits + (h.imm or 0)))
            state.pc = (state.pc or 0) + 2
            return "fall"
        end
        state.pc = (state.pc or 0) + 1
        state.side_exit = "metamethod_binary"
        return "side_exit"
    end,
}

add {
    name = "branch.jmp.target",
    ring = 1,
    family = "branch",
    effects = { "MAY_BRANCH" },
    holes = { "target" },
    relocs = { "branch_label" },
    execute = function(state, h)
        state.pc = h.target
        return "branch"
    end,
}

add {
    name = "branch.test.sA.true_or_false",
    ring = 1,
    family = "branch",
    effects = { "MAY_BRANCH" },
    holes = { "a", "c" },
    execute = function(state, h)
        local is_true = truthy(read_slot(state, h.a))
        if is_true ~= ((h.c or 0) == 0) then
            state.pc = (state.pc or 0) + 2
            return "skip"
        end
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "cmp.lt.generic.sA_sB.true_or_false_or_mm",
    ring = 1,
    family = "compare",
    effects = { "MAY_BRANCH", "MAY_CALL_METAMETHOD" },
    holes = { "a", "b", "c" },
    exits = { "METAMETHOD" },
    execute = function(state, h)
        local lhs, rhs = read_slot(state, h.b), read_slot(state, h.c)
        local ok, result = false, false
        if lhs.tag == Tag.INTEGER and rhs.tag == Tag.INTEGER then ok, result = true, lhs.bits < rhs.bits end
        if lhs.tag == Tag.NUM and rhs.tag == Tag.NUM then ok, result = true, lhs.bits < rhs.bits end
        if not ok then state.side_exit = "compare_metamethod"; return "side_exit" end
        state.pc = (state.pc or 0) + ((result == ((h.a or 0) ~= 0)) and 2 or 1)
        return "branch"
    end,
}

add {
    name = "cmp.eq.generic.sA_sB.true_or_false_or_mm",
    ring = 1,
    family = "compare",
    effects = { "MAY_BRANCH", "MAY_CALL_METAMETHOD" },
    holes = { "a", "b", "c" },
    execute = function(state, h)
        local result = same_value(read_slot(state, h.b), read_slot(state, h.c))
        state.pc = (state.pc or 0) + ((result == ((h.a or 0) ~= 0)) and 2 or 1)
        return "branch"
    end,
}

add {
    name = "loop.forloop_i64.sA_Bx.loop_or_exit",
    ring = 2,
    family = "loop.specialized",
    effects = { "MAY_BRANCH" },
    holes = { "a", "sbx" },
    exits = { "SIDE_EXIT" },
    execute = function(state, h)
        local idx = read_slot(state, h.a)
        local limit = read_slot(state, h.a + 1)
        local step = read_slot(state, h.a + 2)
        if idx.tag ~= Tag.INTEGER or limit.tag ~= Tag.INTEGER or step.tag ~= Tag.INTEGER then
            state.side_exit = "forloop_type"
            return "side_exit"
        end
        local next_idx = idx.bits + step.bits
        write_slot(state, h.a, v_int(next_idx))
        if (step.bits >= 0 and next_idx <= limit.bits) or (step.bits < 0 and next_idx >= limit.bits) then
            write_slot(state, h.a + 3, v_int(next_idx))
            state.pc = (state.pc or 0) + (h.sbx or 0)
            return "loop"
        end
        state.pc = (state.pc or 0) + 1
        return "fall"
    end,
}

add {
    name = "return.one.sA",
    ring = 1,
    family = "return",
    effects = { "MATERIALIZE_VM_STATE" },
    holes = { "a" },
    projections = { "INTERPRETER" },
    execute = function(state, h)
        state.outcome = "return1"
        state.return_value = clone_value(read_slot(state, h.a))
        return "return"
    end,
}

add {
    name = "return.zero",
    ring = 1,
    family = "return",
    effects = { "MATERIALIZE_VM_STATE" },
    holes = {},
    projections = { "INTERPRETER" },
    execute = function(state)
        state.outcome = "return0"
        return "return"
    end,
}

-- Ring 2 specialized variants.
add {
    name = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
    ring = 2,
    family = "arith.guarded",
    effects = { "MAY_BRANCH" },
    holes = { "a", "b", "c" },
    exits = { "SIDE_EXIT" },
    execute = function(state, h)
        local lhs, rhs = read_slot(state, h.b), read_slot(state, h.c)
        if lhs.tag ~= Tag.INTEGER or rhs.tag ~= Tag.INTEGER then
            state.side_exit = "guard_int_pair"
            return "side_exit"
        end
        write_slot(state, h.a, v_int(lhs.bits + rhs.bits))
        state.pc = (state.pc or 0) + 2
        return "fall"
    end,
}

add {
    name = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
    ring = 2,
    family = "arith.guarded",
    effects = { "MAY_BRANCH" },
    holes = { "a", "b", "imm" },
    exits = { "SIDE_EXIT" },
    execute = function(state, h)
        local lhs = read_slot(state, h.b)
        if lhs.tag ~= Tag.INTEGER then
            state.side_exit = "guard_int"
            return "side_exit"
        end
        write_slot(state, h.a, v_int(lhs.bits + (h.imm or 0)))
        state.pc = (state.pc or 0) + 2
        return "fall"
    end,
}

add {
    name = "branch.truthy.sA.true_or_false",
    ring = 2,
    family = "branch.specialized",
    effects = { "MAY_BRANCH" },
    holes = { "a", "true_pc", "false_pc" },
    execute = function(state, h)
        state.pc = truthy(read_slot(state, h.a)) and h.true_pc or h.false_pc
        return "branch"
    end,
}

-- AWFY-priority catalog entries that need table/call IC products before execution.
for _, name in ipairs {
    "table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow",
    "table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier",
    "table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow",
    "table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier",
    "table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow",
    "call.generic.sF_args.boundary",
    "call.known_lclosure.sF_args.enter_lua",
    "call.known_cclosure.sF_args.enter_native",
    "super.method_self_move_call.ic1",
    "super.field_field_test_branch.ic1",
    "super.field_field_add_setfield.ic1",
    "super.array_get_test_forloop.ic1",
    "super.array_set_forloop.ic1",
    "super.while_table_update_i64.ic1",
    "super.newtable_setfield_bundle.small",
    "super.i64_loop_add_mul_accum",
} do
    add { name = name, ring = name:match("^super%.") and 3 or 2, family = name:match("^([^%.]+%.[^%.]+)") or "unknown", status = "catalog", effects = { "MAY_BRANCH" } }
end

M.library = library
M.entries = library.entries
M.by_name = library.by_name

function M.get(name)
    return assert(library.by_name[name], "unknown stencil " .. tostring(name))
end

function M.semantic_entries()
    local out = {}
    for _, e in ipairs(library.entries) do if e.execute then out[#out + 1] = e end end
    return out
end

function M.catalog_entries()
    local out = {}
    for _, e in ipairs(library.entries) do if not e.execute then out[#out + 1] = e end end
    return out
end

function M.execute(name, state, holes)
    local e = M.get(name)
    assert(e.execute, "stencil has no semantic executor yet: " .. name)
    return e.execute(state, holes or {})
end

-- Lua 5.5 instruction helpers for reference interpreter comparison.
local function enc_ABC(op, a, b, c)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end

local function enc_ABx(op, a, bx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(bx or 0, 15))
end

local function enc_AsBx(op, a, sbx)
    return enc_ABx(op, a, (sbx or 0) + 65535)
end

M.encode = { ABC = enc_ABC, ABx = enc_ABx, AsBx = enc_AsBx }

local function decode(word)
    return {
        op = bit.band(word, 127),
        a = bit.band(bit.rshift(word, 7), 255),
        b = bit.band(bit.rshift(word, 16), 255),
        c = bit.band(bit.rshift(word, 24), 255),
        bx = bit.band(bit.rshift(word, 15), 131071),
        sbx = bit.band(bit.rshift(word, 15), 131071) - 65535,
    }
end
M.decode = decode

function M.reference_step(state, word)
    local d = decode(word)
    local op = d.op
    if op == Op.MOVE then
        write_slot(state, d.a, read_slot(state, d.b))
        state.pc = (state.pc or 0) + 1
    elseif op == Op.LOADI then
        write_slot(state, d.a, v_int(d.sbx))
        state.pc = (state.pc or 0) + 1
    elseif op == Op.LOADF then
        write_slot(state, d.a, v_num(d.sbx))
        state.pc = (state.pc or 0) + 1
    elseif op == Op.LOADK then
        write_slot(state, d.a, state.constants[d.bx] or v_nil())
        state.pc = (state.pc or 0) + 1
    elseif op == Op.LOADFALSE or op == Op.LFALSESKIP then
        write_slot(state, d.a, v_false())
        state.pc = (state.pc or 0) + (op == Op.LFALSESKIP and 2 or 1)
    elseif op == Op.LOADTRUE then
        write_slot(state, d.a, v_true())
        state.pc = (state.pc or 0) + 1
    elseif op == Op.LOADNIL then
        for i = d.a, d.a + d.b do write_slot(state, i, v_nil()) end
        state.pc = (state.pc or 0) + 1
    elseif op == Op.GETUPVAL then
        local uv = assert(state.upvalues and state.upvalues[d.b], "missing upvalue " .. tostring(d.b))
        write_slot(state, d.a, uv)
        state.pc = (state.pc or 0) + 1
    elseif op == Op.ADD then
        local lhs, rhs = read_slot(state, d.b), read_slot(state, d.c)
        if lhs.tag == Tag.INTEGER and rhs.tag == Tag.INTEGER then
            write_slot(state, d.a, v_int(lhs.bits + rhs.bits))
            state.pc = (state.pc or 0) + 2
        elseif lhs.tag == Tag.NUM and rhs.tag == Tag.NUM then
            write_slot(state, d.a, v_num(lhs.bits + rhs.bits))
            state.pc = (state.pc or 0) + 2
        else
            state.pc = (state.pc or 0) + 1
            state.side_exit = "metamethod_binary"
        end
    elseif op == Op.ADDI then
        local lhs = read_slot(state, d.b)
        if lhs.tag == Tag.INTEGER then
            write_slot(state, d.a, v_int(lhs.bits + d.c))
            state.pc = (state.pc or 0) + 2
        elseif lhs.tag == Tag.NUM then
            write_slot(state, d.a, v_num(lhs.bits + d.c))
            state.pc = (state.pc or 0) + 2
        else
            state.pc = (state.pc or 0) + 1
            state.side_exit = "metamethod_binary"
        end
    elseif op == Op.JMP then
        state.pc = (state.pc or 0) + d.sbx
    elseif op == Op.TEST then
        local is_true = truthy(read_slot(state, d.a))
        state.pc = (state.pc or 0) + ((is_true ~= (d.c == 0)) and 2 or 1)
    elseif op == Op.LT then
        local lhs, rhs = read_slot(state, d.b), read_slot(state, d.c)
        local ok, result = false, false
        if lhs.tag == Tag.INTEGER and rhs.tag == Tag.INTEGER then ok, result = true, lhs.bits < rhs.bits end
        if lhs.tag == Tag.NUM and rhs.tag == Tag.NUM then ok, result = true, lhs.bits < rhs.bits end
        if ok then
            state.pc = (state.pc or 0) + ((result == (d.a ~= 0)) and 2 or 1)
        else
            state.side_exit = "compare_metamethod"
        end
    elseif op == Op.EQ then
        local result = same_value(read_slot(state, d.b), read_slot(state, d.c))
        state.pc = (state.pc or 0) + ((result == (d.a ~= 0)) and 2 or 1)
    elseif op == Op.FORLOOP then
        local idx = read_slot(state, d.a)
        local limit = read_slot(state, d.a + 1)
        local step = read_slot(state, d.a + 2)
        if idx.tag ~= Tag.INTEGER or limit.tag ~= Tag.INTEGER or step.tag ~= Tag.INTEGER then
            state.side_exit = "forloop_type"
        else
            local next_idx = idx.bits + step.bits
            write_slot(state, d.a, v_int(next_idx))
            if (step.bits >= 0 and next_idx <= limit.bits) or (step.bits < 0 and next_idx >= limit.bits) then
                write_slot(state, d.a + 3, v_int(next_idx))
                state.pc = (state.pc or 0) + d.sbx
            else
                state.pc = (state.pc or 0) + 1
            end
        end
    elseif op == Op.RETURN1 then
        state.outcome = "return1"
        state.return_value = clone_value(read_slot(state, d.a))
    elseif op == Op.RETURN0 then
        state.outcome = "return0"
    else
        error("reference_step unsupported opcode " .. tostring(op))
    end
    return state
end

return M
