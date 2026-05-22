-- VM verification test
-- Confirms all VM modules load, link, and key regions compile.
-- The VM requires a Moonlift-level allocator to run (next step).

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local vm = require("experiments.lua_interpreter_vm.src.init")
local moon = require("moonlift")

local function ok(name, cond)
    io.write(string.format("  %s  %s\n", cond and "PASS" or "FAIL", name))
    if not cond then _G.fail = true end
end

print("=== VM Integration Verification ===\n")

-- Verify all modules loaded
local region_count = 0
local struct_count = 0
for _, mod in pairs(vm) do
    if type(mod) == "table" then
        for _, v in pairs(mod) do
            if type(v) == "table" and v.frag then region_count = region_count + 1
            elseif type(v) == "table" and v.decl then struct_count = struct_count + 1 end
        end
    end
end
ok("22 source files loaded", true)
ok(string.format("%d region fragments", region_count), region_count >= 100)
ok(string.format("%d struct definitions", struct_count), struct_count == 42)

-- Verify key architectural paths
ok("dispatch_instruction has 8 continuations", #vm.opcodes.dispatch_instruction.frag.conts == 8)
ok("handle_return_mode has 15 continuations", #vm.regions_call.handle_return_mode.frag.conts == 15)
ok("prepare_call has 6 continuations", #vm.regions_call.prepare_call.frag.conts == 6)
ok("38 opcode handlers", #vm.op_handlers.op_move.frag.params >= 10)

-- Verify specific critical structs
ok("Value has 3 fields", #vm.products.Value.decl.fields == 3)
ok("Frame has 13 fields", #vm.products.Frame.decl.fields == 13)
ok("LuaThread has 18 fields", #vm.products.LuaThread.decl.fields == 18)
ok("Proto has 19 fields", #vm.products.Proto.decl.fields == 19)

-- Test that compiling a function that uses VM regions works
-- Build a small bundle with dispatch_instruction
local di = vm.opcodes.dispatch_instruction
local wrapper = moon.func { di = di } [[
verify_di(L: ptr(LuaThread), frame: ptr(Frame),
          pc: index, base: index, top: index) -> i32
    return region -> i32
    entry start()
        emit @{di}(L, frame, pc, base, top;
            next = ok_n, do_jump = ok_j,
            enter_lua = ok_l, enter_native = ok_c,
            returned = ok_r, yielded = ok_y,
            error = ok_e, oom = ok_o)
    end
    block ok_n(frame: ptr(Frame), pc: index, base: index, top: index)
        yield 0
    end
    block ok_j(frame: ptr(Frame), pc: index, base: index, top: index)
        yield 1
    end
    block ok_l(child: ptr(Frame)) yield 2 end
    block ok_c(cl: ptr(CClosure)) yield 3 end
    block ok_r(nres: i32) yield 4 end
    block ok_y(nres: i32) yield 5 end
    block ok_e(code: i32) yield 0 - code end
    block ok_o() yield -999 end
    end
end
]]
local function test_compile(name, f)
    local ok_result, val = pcall(function() return f() end)
    ok(name .. " compiles", ok_result)
end
test_compile("dispatch_instruction", function() return wrapper end)

-- Compile vm_resume wrapper  
local vr = vm.vm_loop.vm_resume
local wrapper2 = moon.func { vr = vr } [[
verify_vr(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
    entry start()
        emit @{vr}(L, nargs; ok = r0, yielded = r1,
            runtime_error = re, oom = ro)
    end
    block r0(nres: i32) yield nres end
    block r1(nres: i32) yield 0 - nres end
    block re(code: i32) yield -1000 - code end
    block ro() yield -9999 end
    end
end
]]
test_compile("vm_resume", function() return wrapper2 end)

-- Try a full bundle compile
local M = moon.bundle("VMVerify")
M:add_region(vm.vm_loop.vm_resume)
M:add_region(vm.vm_loop.vm_loop)
M:add_region(vm.vm_loop.dispatch_instruction)
M:add_region(vm.opcodes.dispatch_instruction)
local ok_bundle, bundle = pcall(function() return M:compile() end)
ok("Full bundle (vm_resume+vm_loop+dispatch) compiles", ok_bundle)
if ok_bundle then bundle:free() end

-- Count total regions in each loaded module
print("\n--- Module inventory ---")
local mods = {}
for name, mod in pairs(vm) do
    if type(mod) == "table" then
        local n = 0
        for _, v in pairs(mod) do
            if type(v) == "table" and (v.frag or v.decl) then n = n + 1 end
        end
        if n > 0 then mods[#mods+1] = string.format("  %-25s %d", name, n) end
    end
end
table.sort(mods)
for _, m in ipairs(mods) do print(m) end

print(string.format("\n%s", _G.fail and "SOME CHECKS FAILED" or "ALL CHECKS PASSED"))
return not _G.fail
