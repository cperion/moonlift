-- VM region composition test
-- Workaround: pass frames/stack as direct params (field access bug in emit)

local moon = require("moonlift")

-- Region: takes frames+stack directly, not through L.frames/L.stack
local vm_run = moon.region [[
region vm_run(stack: ptr(Value), code: ptr(Instr), consts: ptr(Value);
              ok: cont(nres: i32), err: cont(code: i32))
entry start()
    let inst: Instr = code[0]
    let op: u16 = inst.op
    let dst: u16 = inst.a
    let kidx: u32 = inst.bx
    switch op do
    case 1 then  -- LOADK
        stack[as(index, dst)] = consts[kidx]
        jump ok(nres = 1)
    case 30 then  -- RETURN
        jump ok(nres = 1)
    default then
        jump err(code = 6)
    end
end
end
]]

-- Callable func that passes thread fields to the region
local run_fn = moon.func { vm_run = vm_run } [[
run(stack: ptr(Value), code: ptr(Instr), consts: ptr(Value)) -> i32
    return region -> i32
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
