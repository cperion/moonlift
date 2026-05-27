#!/usr/bin/env luajit
-- test_ssa_to_c.lua — Test the SSA-to-C code generator
--
-- Exercises the full pipeline: opcodes → lift → optimize → generate C
-- and displays the generated C code.

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local SSA = require("src.ssa")
local SSAtoC = require("src.ssa_to_c")

local function banner(title)
    print("")
    print("═" .. string.rep("═", #title + 2) .. "═")
    print("  " .. title)
    print("═" .. string.rep("═", #title + 2) .. "═")
    print("")
end

local function show_c(ssa_result, label)
    print("── Generated C code: " .. (label or ssa_result.normal_form_hash or "?") .. " ──")
    local result = SSAtoC.generate(ssa_result)
    print(result.c_code)
    print("── Stats: " .. string.format("%d nodes, %d exits, holes: %s ──",
        result.node_count, result.exit_count,
        table.concat(result.holes, ", ")))
    print("")
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 1: Simple i64 add with return
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 1: ADD i64 + RETURN1")

local r1 = SSA.compile(
    {{op="ADD", a=2, b=0, c=1}, {op="RETURN1", a=2}},
    {"lhs_i64", "rhs_i64", "returns_prev"}
)
if r1.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r1.normal_form, "|"), table.concat(r1.active_ops, " ")))
    print(string.format("  Checked facts: %s  Deps: %s", table.concat(r1.checked_facts, ","), table.concat(r1.deps, ",")))
    show_c(r1, "add_return1_i64")
else
    print("  FAILED: " .. table.concat(r1.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 2: ADDI (add immediate 1) + RETURN1
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 2: ADDI 1 + RETURN1")

local r2 = SSA.compile(
    {{op="ADDI", a=1, b=1, c=1}, {op="RETURN1", a=1}},
    {"lhs_i64", "returns_prev"}
)
if r2.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r2.normal_form, "|"), table.concat(r2.active_ops, " ")))
    show_c(r2, "addi_return1_i64")
else
    print("  FAILED: " .. table.concat(r2.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 3: GETFIELD (shape-guarded) + ADDI + SETFIELD (field increment)
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 3: FIELD_ADDI_UPDATE (GETFIELD, ADDI, SETFIELD)")

local r3 = SSA.compile(
    {{op="GETFIELD", a=1, b=0, c=2}, {op="ADDI", a=1, b=1, c=1}, {op="SETFIELD", a=0, b=2, c=1}},
    {"table", "shape_known", "metatable_absent", "key_const", "lhs_i64", "barrier_clean"}
)
if r3.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r3.normal_form, "|"), table.concat(r3.active_ops, " ")))
    print(string.format("  Checked facts: %s", table.concat(r3.checked_facts, ",")))
    show_c(r3, "field_addi_update")
else
    print("  FAILED: " .. table.concat(r3.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 4: GETTABLE array hit + ADD + RETURN1
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 4: GETTABLE array + ADD + RETURN1")

local r4 = SSA.compile(
    {{op="GETTABLE", a=2, b=0, c=1}, {op="ADD", a=3, b=2, c=4}, {op="RETURN1", a=3}},
    {"table", "array_hit", "metatable_absent", "key_i64", "lhs_i64", "rhs_i64", "returns_prev"}
)
if r4.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r4.normal_form, "|"), table.concat(r4.active_ops, " ")))
    show_c(r4, "gettable_array_add_return1")
else
    print("  FAILED: " .. table.concat(r4.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 5: CALL with known target
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 5: CALL with known target")

local r5 = SSA.compile(
    {{op="CALL", a=0, b=1, c=2}},
    {"known_call_target"}
)
if r5.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r5.normal_form, "|"), table.concat(r5.active_ops, " ")))
    show_c(r5, "call_known_target")
else
    print("  FAILED: " .. table.concat(r5.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 6: LOADI + ADD (const + var) + RETURN1
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 6: LOADI + ADD + RETURN1 (constant + variable add)")

local r6 = SSA.compile(
    {{op="LOADI", a=0, sbx=7}, {op="ADD", a=2, b=0, c=1}, {op="RETURN1", a=2}},
    {"lhs_i64", "rhs_i64", "returns_prev"}
)
if r6.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r6.normal_form, "|"), table.concat(r6.active_ops, " ")))
    show_c(r6, "loadi_add_return1")
else
    print("  FAILED: " .. table.concat(r6.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 7: Two consecutive arithmetic ops (stress test)
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 7: MUL + ADD + RETURN1 (two arithmetic ops)")

local r7 = SSA.compile(
    {{op="MUL", a=2, b=0, c=1}, {op="ADD", a=3, b=2, c=4}, {op="RETURN1", a=3}},
    {"lhs_i64", "rhs_i64", "returns_prev"}
)
if r7.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r7.normal_form, "|"), table.concat(r7.active_ops, " ")))
    show_c(r7, "mul_add_return1")
else
    print("  FAILED: " .. table.concat(r7.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 8: What does NOT absorb look like? (no facts)
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 8: ADD without facts (should residualize)")

local r8 = SSA.compile(
    {{op="ADD", a=2, b=0, c=1}, {op="RETURN1", a=2}},
    {}  -- NO facts
)
if r8.ok then
    print(string.format("  NF: %s  ops: %s", table.concat(r8.normal_form, "|"), table.concat(r8.active_ops, " ")))
    show_c(r8, "add_no_facts")
else
    print("  FAILED: " .. table.concat(r8.errors or {}, "; "))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Test 9: Compile to actual .c file
-- ═══════════════════════════════════════════════════════════════════════
banner("Test 9: Write to file")

local out_dir = spongejit .. "/build/ssa_to_c_tests"
os.execute("mkdir -p " .. out_dir)

for i, r in ipairs({r1, r2, r3, r4, r5, r6, r7}) do
    if r and r.ok then
        local name = string.format("region_%02d_%s.c", i, table.concat(r.normal_form, "_"))
        local path = out_dir .. "/" .. name
        local ok, err = SSAtoC.compile_to_file(r, path)
        if ok then
            print(string.format("  Wrote: %s (%d bytes)", path, #ok.c_code))
        else
            print(string.format("  FAILED: %s — %s", path, err))
        end
    end
end

print("")
print("══════════════════════════════════════════")
print("  All tests complete.")
print("  Generated C files in: " .. out_dir)
print("══════════════════════════════════════════")
