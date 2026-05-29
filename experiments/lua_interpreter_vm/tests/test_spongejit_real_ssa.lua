#!/usr/bin/env luajit
-- Real SponJIT fact + SSA invariants.

package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path

local Facts = require("src.facts")
local SSA = require("src.ssa")
local Contract = require("src.ssa_contract")
local Enum = require("src.enumerate")

local function assert_eq(a, b, msg)
    if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

local function assert_true(x, msg)
    if not x then error(msg or "assert_true failed", 2) end
end

local function has(xs, x)
    for _, v in ipairs(xs or {}) do if v == x then return true end end
    return false
end

-- Fact closure: shape_known implies table.
do
    local fs = Facts.new({ "shape_known" })
    assert_true(fs:implies("shape_known", Facts.value("table")), "shape_known absent")
    assert_true(fs:implies("is_table", Facts.value("table")), "shape_known must imply table")
    assert_true(has(fs:deps(), "shape_epoch"), "shape fact must carry shape_epoch dependency")
end

-- Fact contradiction: one subject cannot have two concrete incompatible types.
do
    local fs = Facts.new({
        Facts.fact("type", Facts.value("x"), "is_i64"),
        Facts.fact("type", Facts.value("x"), "is_table"),
    })
    assert_true(not fs:ok(), "conflicting type facts must be rejected")
end

-- Guards are facts with exits and deps.
do
    local r = SSA.compile({ "GETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const" })
    assert_true(r.ok, table.concat(r.errors or {}, "\n"))
    assert_true(has(r.stencil_ops, "guard_shape"), "shape guard missing")
    assert_true(has(r.deps, "shape_epoch"), "shape dep missing")
    assert_true((r.projection.exit_obligations or 0) >= 3, "guards must project exits")
end

-- compile_nodes reopens typed semantic node specs; raw codegen-op reopening was removed.
do
    local base = SSA.compile({ { op = "ADDI", a = 1, b = 1, c = 1 } }, { Facts.fact("type", Facts.slot("R1"), "is_i64", true) })
    local saw_mem = false
    local saw_residency = false
    local saw_exit = false
    for _, spec in ipairs(base.active_node_specs or {}) do
        if spec.source ~= nil then assert_true(type(spec.source) == "number", "source must serialize as number") end
        if spec.mem_in and spec.mem_in.frame then saw_mem = true end
        for _, rloc in ipairs(spec.output_residencies or {}) do
            if rloc == "gpr0" then saw_residency = true end
        end
        if spec.exit and spec.exit.reason then saw_exit = true end
    end
    assert_true(saw_mem, "active_node_specs must preserve memory input tokens")
    assert_true(saw_residency, "active_node_specs must preserve value residency")
    assert_true(saw_exit, "active_node_specs must preserve exit objects")

    local r = SSA.compile_nodes(base.active_node_specs, {})
    assert_true(r.ok, table.concat(r.errors or {}, "\n"))
    assert_true(has(r.stencil_ops, "store_i64_slot"), "typed node reopening should preserve lowered integer store")
    local saw_reopened_residency = false
    local saw_reopened_mem_in = false
    local saw_reopened_mem_out = false
    local saw_reopened_exit = false
    for _, spec in ipairs(r.active_node_specs or {}) do
        if spec.mem_in and spec.mem_in.frame then saw_reopened_mem_in = true end
        if spec.mem_out and spec.mem_out.frame then saw_reopened_mem_out = true end
        if spec.exit and spec.exit.reason then saw_reopened_exit = true end
        for _, rloc in ipairs(spec.output_residencies or {}) do
            if rloc == "gpr0" then saw_reopened_residency = true end
        end
    end
    assert_true(saw_reopened_residency, "compile_nodes must round-trip residency")
    assert_true(saw_reopened_mem_in, "compile_nodes must round-trip memory input tokens")
    assert_true(saw_reopened_mem_out, "compile_nodes must round-trip memory output tokens")
    assert_true(saw_reopened_exit, "compile_nodes must round-trip exit objects")
end

-- Barrier elimination requires a real GC fact.
do
    local no_fact = SSA.compile({ "GETFIELD", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const" })
    local with_fact = SSA.compile({ "GETFIELD", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const", "barrier_clean" })
    assert_true(has(no_fact.stencil_ops, "barrier_check"), "barrier should remain without fact")
    assert_true(not has(with_fact.stencil_ops, "barrier_check"), "barrier_clean should remove barrier")
end

-- Operand-specific facts attach to real PUC slots and drive the same optimization.
do
    local ops = {
        { op = "GETFIELD", a = 1, b = 0, c = 2 },
        { op = "ADDI", a = 1, b = 1, c = 1 },
        { op = "SETFIELD", a = 0, b = 2, c = 1 },
    }
    local facts = {
        Facts.fact("type", Facts.slot("R0"), "is_table"),
        Facts.fact("shape", Facts.slot("R0"), "shape_known", true),
        Facts.fact("metatable", Facts.slot("R0"), "metatable_absent", true),
        Facts.fact("constant", Facts.value("K2"), "key_const", true),
        Facts.fact("type", Facts.slot("R1"), "is_i64"),
        Facts.fact("gc", Facts.global_subject(), "barrier_clean", true),
    }
    local r = SSA.compile(ops, facts)
    assert_true(r.ok, table.concat(r.errors or {}, "\n"))
    assert_eq(table.concat(r.stencil_form, "|"), "FIELD_ADDI_UPDATE", "operand-specific field update should fuse semantically")
    assert_true(has(r.checked_facts, "shape_known"), "slot-specific shape fact should be guarded")
end

-- SSA contracts carry real fact lifetime: selector facts checked by tile guards
-- become success-edge facts, writes kill prior slot leases, and stores produce
-- fresh slot facts only when the SSA proves the stored value.
do
    local facts = { Facts.fact("type", Facts.slot("R1"), "is_i64", true) }
    local r = SSA.compile({ { op = "ADDI", a = 1, b = 1, c = 1 } }, facts)
    local c = Contract.from_result(r, facts)
    assert_eq(c.selector_sig.literal, "0x0000000000000001ULL", "selector should include observed canonical S0:i64")
    assert_eq(c.required_sig.literal, "0x0000000000000000ULL", "guarded i64 is checked, not blindly required")
    assert_eq(c.checked_sig.literal, "0x0000000000000001ULL", "ADDI guard establishes canonical S0:i64 on success")
    assert_eq(c.produced_sig.literal, "0x0000000000000001ULL", "ADDI store produces fresh canonical S0:i64")
    assert_true(c.killed_sig.literal ~= "0x0000000000000000ULL", "ADDI store must kill previous R1 leases")
end

-- Enumerator derives typed fact axes from instruction operands.
do
    local axes = Enum.fact_axes_for_ops({ { op = "ADDI", a = 3, b = 2, c = 1 } })
    local found = false
    for _, f in ipairs(axes) do
        if type(f) == "table" and f.predicate == "is_i64" and Facts.subject_key(f.subject) == "slot:R2" then found = true end
    end
    assert_true(found, "ADDI operand B must produce slot:R2 is_i64 fact axis")
end

-- Atoms reopen as typed semantic node specs, preserving graph-derived NF.
do
    local r = SSA.compile({ "GETFIELD", "ADDI", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const", "lhs_i64", "barrier_clean" })
    local reopened = SSA.compile_nodes(r.active_node_specs, {})
    assert_true(reopened.ok, table.concat(reopened.errors or {}, "\n"))
    assert_true(has(reopened.stencil_ops, "store_i64_slot"), "atom reopen must preserve lowered store shape")
    assert_true(has(reopened.stencil_ops, "table_field_load"), "atom reopen must preserve field load shape")
end

print("ok - real SponJIT fact + SSA invariants")
