-- VM region composition test
-- Workaround: pass frames/stack as direct params (field access bug in emit)

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- Region: takes frames+stack directly, not through L.frames/L.stack
local vm_run = moon.region [[
region vm_run(stack: ptr(Value), code: ptr(Instr), consts: ptr(Value);
              ok(nres: i32) | err(code: i32))
entry start()
    let word: u32 = code[0].word
    let op: u16 = as(u16, word & 127)
    let dst: u16 = as(u16, (word >> 7) & 255)
    let kidx: u32 = (word >> 15) & 131071
    switch op do
    case 3 then  -- LOADK
        stack[as(index, dst)] = consts[kidx]
        jump ok(nres = 1)
    case 70 then  -- RETURN
        jump ok(nres = 1)
    default then
        jump err(code = 6)
    end
end
end
]]

-- Callable func that passes thread fields to the region
local run_fn = moon.func { vm_run = vm_run } [[
run(stack: ptr(Value), code: ptr(Instr), consts: ptr(Value)): i32
    return region: i32
    entry start()
        emit @{vm_run}(stack, code, consts; ok = fin, err = err_exit)
    end
    block fin(nres: i32) return nres end
    block err_exit(code: i32) return -200 - code end
    end
end
]]

-- Compile
local ok, compiled = pcall(function() return run_fn:compile() end)
if ok then
    print("PASS: region compiles with direct pointer params")
    compiled:free()
    os.exit(0)
else
    print("FAIL:", compiled)
    os.exit(1)
end
