#!/usr/bin/env luajit
-- Real SponJIT fact + SSA invariants.

package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;" .. package.path

local Facts = require("src.facts")
local SSA = require("src.ssa")
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
    assert_true(has(r.active_ops, "guard_shape"), "shape guard missing")
    assert_true(has(r.deps, "shape_epoch"), "shape dep missing")
    assert_true((r.projection.exit_obligations or 0) >= 3, "guards must project exits")
end

-- Frame store/load forwarding is slot-identity based and visible through compile_nodes.
do
    local r = SSA.compile_nodes({ "load_const", "store_slot", "load_slot", "return1" }, {})
    assert_true(r.ok, table.concat(r.errors or {}, "\n"))
    assert_true(not has(r.active_ops, "load_slot"), "load after store should be forwarded")
end

-- Barrier elimination requires a real GC fact.
do
    local no_fact = SSA.compile({ "GETFIELD", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const" })
    local with_fact = SSA.compile({ "GETFIELD", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const", "barrier_clean" })
    assert_true(has(no_fact.active_ops, "barrier_check"), "barrier should remain without fact")
    assert_true(not has(with_fact.active_ops, "barrier_check"), "barrier_clean should remove barrier")
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
    assert_eq(table.concat(r.normal_form, "|"), "FIELD_ADDI_UPDATE", "operand-specific field update should fuse semantically")
    assert_true(has(r.checked_facts, "shape_known"), "slot-specific shape fact should be guarded")
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
    assert_eq(table.concat(reopened.normal_form, "|"), table.concat(r.normal_form, "|"), "atom reopen must preserve semantic NF")
    assert_eq(table.concat(reopened.active_ops, " "), table.concat(r.active_ops, " "), "atom reopen must preserve codegen ops before cross-boundary optimization")
end

print("ok - real SponJIT fact + SSA invariants")
