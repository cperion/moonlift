-- Coverage math smoke test.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("experiments.lua_interpreter_vm.src.jit.coverage")

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. (detail and (" -- " .. detail) or "")) end
end

local rows = {
    { name = "MOVE", count = 10 },
    { name = "GETFIELD", count = 30 },
    { name = "ADDI", count = 10 },
    { name = "GETUPVAL", count = 20 },
    { name = "FORLOOP", count = 30 },
}
local cur = C.coverage(rows, C.sets.current)
check("current count", cur.covered == 70, tostring(cur.covered))
check("current percent", math.abs(cur.percent - 70) < 0.001, tostring(cur.percent))
check("unsupported sorted by input", cur.unsupported[1].name == "FORLOOP")

local d = C.delta(rows, C.sets.current, C.sets.control_loop)
check("delta gained", d.gained == 30, tostring(d.gained))
check("delta op", d.ops[1].name == "FORLOOP")

local pairs = {
    { name1 = "MOVE", name2 = "ADDI", count = 7 },
    { name1 = "MOVE", name2 = "FORLOOP", count = 11 },
    { name1 = "FORLOOP", name2 = "TAILCALL", count = 13 },
}
local pc = C.pair_coverage(pairs, C.sets.current)
check("pair both", pc.both == 7, tostring(pc.both))
check("pair one", pc.one == 11, tostring(pc.one))
check("pair none", pc.none == 13, tostring(pc.none))

print(string.format("JIT coverage: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
