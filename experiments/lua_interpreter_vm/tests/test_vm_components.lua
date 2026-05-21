-- VM component tests: pure Lua + moon.xxx quoting API
-- Tests each VM subsystem individually without requiring region composition

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

print("=== VM Component Tests ===\n")

-- 1. Value type dispatch (value_truth)
check("modules load", type(vm.regions_value) == "table")

-- 2. Raw struct allocation via moon.func
-- Compile a function that uses struct literals and returns a tag
local t1 = moon.func [[
test_value_new() -> i32
    let v: Value = { tag = 4, aux = 0, bits = as(u64, 42.0) }
    return as(i32, v.tag)
end
]]
local c1 = t1:compile()
check("struct literal + field access", c1() == 4)
c1:free()

-- 3. Test raw_equal on numbers
local t2 = moon.func [[
test_raw_equal() -> i32
    let a: Value = { tag = 4, aux = 0, bits = as(u64, 42.0) }
    let b: Value = { tag = 4, aux = 0, bits = as(u64, 42.0) }
    let c: Value = { tag = 4, aux = 0, bits = as(u64, 99.0) }
    if a.bits == b.bits and not (a.bits == c.bits) then
        return 1
    end
    return 0
end
]]
local c2 = t2:compile()
check("raw value equality", c2() == 1)
c2:free()

-- 4. Test struct literal construction
local t3 = moon.func [[
test_frame_new() -> i32
    let f: Frame = {
        closure = { tag = 0, aux = 0, bits = 0 },
        base = 0, top = 0, pc = 0,
        wanted = 0, tailcalls = 0,
        resume_mode = 0,
        resume_a = 0, resume_b = 0, resume_c = 0,
        resume_pc = 0, resume_base = 0,
        resume_value = { tag = 0, aux = 0, bits = 0 }
    }
    return f.wanted
end
]]
local c3 = t3:compile()
check("Frame struct literal", c3() == 0)
c3:free()

-- 5. Build a simple Instr and verify field access
local t4 = moon.func [[
test_instr() -> i32
    let inst: Instr = { op = 1, a = 0, b = 0, c = 0, bx = 0, sbx = 0 }
    return as(i32, inst.op)
end
]]
local c4 = t4:compile()
check("Instr field access", c4() == 1)
c4:free()

-- 6. Build and run a minimal dispatch simulation
-- Create a fake Code[], Instr[], and dispatch "by hand"
local t5 = moon.func { OP_MOVE = moon.int(0) } [[
test_switch() -> i32
    let inst: Instr = { op = @{OP_MOVE}, a = 1, b = 2, c = 0, bx = 0, sbx = 0 }
    switch inst.op do
    case @{OP_MOVE} then
        return 42
    default then
        return -1
    end
end
end
]]
local c5 = t5:compile()
check("opcode switch dispatch", c5() == 42)
c5:free()

-- 7. Pointer arithmetic on arrays
local t6 = moon.func [[
test_ptr_arith() -> i32
    let arr: [i32; 4] = [10, 20, 30, 40]
    return arr[2]
end
]]
local c6 = t6:compile()
check("array indexing", c6() == 30)
c6:free()

-- 8. Pointer store via index
local t7 = moon.func [[
test_ptr_store() -> i32
    var xs: [i32; 3] = [0, 0, 0]
    xs[1] = 42
    return xs[1]
end
]]
local c7 = t7:compile()
check("array store", c7() == 42)
c7:free()

-- 9. Test value truth logic (hardcoded inline)
local t8 = moon.func [[
test_truth() -> i32
    let nil_val: Value = { tag = 0, aux = 0, bits = 0 }
    let num_val: Value = { tag = 4, aux = 0, bits = as(u64, 1.0) }
    let false_val: Value = { tag = 1, aux = 0, bits = 0 }
    -- nil and false are falsey, others truthy
    if nil_val.tag == 0 or nil_val.tag == 1 then
        if num_val.tag ~= 0 and num_val.tag ~= 1 then
            if false_val.tag == 0 or false_val.tag == 1 then
                return 1
            end
        end
    end
    return 0
end
]]
local c8 = t8:compile()
check("value truth logic inline", c8() == 1)
c8:free()

-- 10. Test the full LOADK + RETURN logic inline (no region emit)
local t9 = moon.func { TAG_NUM = moon.int(4) } [[
test_loadk_return() -> i32
    -- Simulate LOADK: load constant into register
    let consts: [i64; 1] = [42]
    let r0: i64 = consts[0]
    -- Simulate RETURN: return r0
    return as(i32, r0)
end
]]
local c9 = t9:compile()
check("LOADK+RETURN simulation", c9() == 42)
c9:free()

-- Summary
print(string.format("\n=== %d/%d passed ===\n", pass, pass + fail))
if fail > 0 then
    print(string.format("WARNING: %d failures", fail))
end

return pass > 0 and pass == (pass + fail)
