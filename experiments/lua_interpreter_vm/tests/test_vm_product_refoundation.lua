-- Final product-shape checks for the explicit VM refoundation.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local vm = require("experiments.lua_interpreter_vm.src.init")
local p = vm.products
local c = vm.const

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end
local function fields(t)
    local out = {}
    for _, f in ipairs(t.decl.fields) do out[f.field_name] = true end
    return out
end

print("=== VM product refoundation checks ===\n")

check("ResumeState exists", p.ResumeState ~= nil)
check("Frame has resume field", fields(p.Frame).resume == true)
check("Frame has no raw resume_mode", fields(p.Frame).resume_mode ~= true)
check("Frame has no raw resume_a", fields(p.Frame).resume_a ~= true)
check("ProtectedFrame stores ResumeState", fields(p.ProtectedFrame).resume == true)
check("NativeCallContext exists", p.NativeCallContext ~= nil)
check("NativeCallContext stores ResumeState", fields(p.NativeCallContext).resume == true)
check("NativeCallResult exposes stack_needed", fields(p.NativeCallResult).stack_needed == true)
check("Table has weak/finalizer state", fields(p.Table).weak_next == true and fields(p.Table).finalizer_state == true)
check("UserData has payload flags/user values", fields(p.UserData).flags == true and fields(p.UserData).user_values == true)
check("GlobalState has weak/finalizer queues", fields(p.GlobalState).weak_values == true and fields(p.GlobalState).finalizers == true)
check("LuaThread has coroutine state", fields(p.LuaThread).coroutine == true)
check("Resume includes final forms", c.Resume.FINALIZER_CALL == 17 and c.Resume.COROUTINE_YIELD == 19 and c.Resume.N == 20)
check("protocol constants exported", c.TableFlag ~= nil and c.FinalizerState ~= nil and c.UserDataFlag ~= nil and c.CompatFormat ~= nil)

print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
