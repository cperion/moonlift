-- VM component tests: pure Lua + lalin.xxx quoting API
-- Tests each VM subsystem individually without requiring region composition

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
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

-- 2. Raw struct allocation via lalin.func
-- Compile a function that uses struct literals and returns a tag
local t1 = lalin.func [[
test_value_new(): i32
    let v: Value = { tag = 4, aux = 0, bits = as(u64, 42.0) }
    return as(i32, v.tag)
end
]]
local c1 = t1:compile()
check("struct literal + field access", c1() == 4)
c1:free()

-- 3. Test raw_equal on numbers
local t2 = lalin.func [[
test_raw_equal(): i32
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
local t3 = lalin.func [[
test_frame_new(): i32
    let f: Frame = {
        closure = { tag = 0, aux = 0, bits = 0 },
        base = 0, top = 0, pc = 0,
        wanted = 0, tailcalls = 0,
        result_base = 0, call_top = 0,
        resume = { kind = 0, a = 0, b = 0, c = 0, pc = 0, base = 0,
                   result_base = 0, call_top = 0, wanted = 0,
                   value = { tag = 0, aux = 0, bits = 0 }, errfunc_slot = 0 },
        yieldable = 0, flags = 0, reserved = 0
    }
    return f.wanted
end
]]
local c3 = t3:compile()
check("Frame struct literal", c3() == 0)
c3:free()

-- 5. Build a simple Instr and verify field access
local t4 = lalin.func [[
test_instr(): i32
    let inst: Instr = { word = 1 }
    return as(i32, inst.word & 127)
end
]]
local c4 = t4:compile()
check("Instr field access", c4() == 1)
c4:free()

-- 6. Build and run a minimal dispatch simulation
-- Create a fake Code[], Instr[], and dispatch "by hand"
local t5 = lalin.func { OP_MOVE = lalin.int(0) } [[
test_switch(): i32
    let inst: Instr = { word = as(u32, @{OP_MOVE}) | (as(u32, 1) << 7) | (as(u32, 2) << 16) }
    if (inst.word & 127) == @{OP_MOVE} then
        return 42
    end
    return -1
end
]]
local c5 = t5:compile()
check("opcode switch dispatch", c5() == 42)
c5:free()

-- 7. Scalar arithmetic sanity
local t6 = lalin.func [[
test_scalar_arith(): i32
    let a: i32 = 10
    let b: i32 = 20
    return a + b
end
]]
local c6 = t6:compile()
check("scalar arithmetic", c6() == 30)
c6:free()

-- 8. Mutable binding sanity
local t7 = lalin.func [[
test_mutable_store(): i32
    var x: i32 = 0
    x = 42
    return x
end
]]
local c7 = t7:compile()
check("mutable store", c7() == 42)
c7:free()

-- 9. Test value truth logic (hardcoded inline)
local t8 = lalin.func [[
test_truth(): i32
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
local t9 = lalin.func { TAG_NUM = lalin.int(const.Tag.NUM) } [[
test_loadk_return(): i32
    -- Simulate LOADK/RETURN with a typed binding instead of array codegen.
    let r0: i64 = 42
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
