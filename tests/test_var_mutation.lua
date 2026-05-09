-- tests/test_var_mutation.lua  — var mutation in if branches
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local Run = require("moonlift.mlua_run")
local function compile(src)
    local path = "/tmp/_var_test.mlua"
    io.open(path, "w"):write(src):close()
    return Run.dofile(path):compile()
end
local passed, failed = 0, 0
local function check(name, expected, actual)
    if expected == actual then
        passed = passed + 1
        io.write(string.format("  OK   %-40s = %s\n", name, tostring(actual)))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-40s expected %s, got %s\n", name, tostring(expected), tostring(actual)))
    end
end

-- Basic: var mutated in then branch
local c1 = compile([[local m = module T
export func f(x: i32) -> i32
    var y: i32 = 0
    if x > 0 then
        y = x
    end
    return y
end
end
return m]])
check("var assigned in then (true)",  5, c1:get("f")(5))
check("var assigned in then (false)", 0, c1:get("f")(-1))
c1:free()

-- Both branches assign
local c2 = compile([[local m = module T
export func g(a: i32, cond: i32) -> i32
    var r: i32 = 99
    if cond == 1 then
        r = a
    else
        r = a + 1
    end
    return r
end
end
return m]])
check("both branches: cond=1",    7,  c2:get("g")(7, 1))
check("both branches: cond=0",    8,  c2:get("g")(7, 0))
c2:free()

-- Sequential reassignment without if
local c3 = compile([[local m = module T
export func h(a: i32, b: i32) -> i32
    var x: i32 = a
    x = b
    x = x + 1
    return x
end
end
return m]])
check("sequential reassign",  11, c3:get("h")(5, 10))
c3:free()

-- Multiple vars, only one mutated
local c4 = compile([[local m = module T
export func multi(flag: i32, a: i32, b: i32) -> i32
    var x: i32 = a
    var y: i32 = b
    if flag ~= 0 then
        x = a + b
    end
    return x + y
end
end
return m]])
check("multi var: flag=1", 17, c4:get("multi")(1, 3, 7))  -- x=10,y=7 → 17
check("multi var: flag=0", 10, c4:get("multi")(0, 3, 7))  -- x=3,y=7  → 10
c4:free()

-- Nested ifs
local c5 = compile([[local m = module T
export func nested(a: i32, b: i32) -> i32
    var acc: i32 = 0
    if a > 0 then
        acc = a
        if b > 0 then
            acc = acc + b
        end
    end
    return acc
end
end
return m]])
check("nested: a>0 b>0",  8,  c5:get("nested")(3, 5))
check("nested: a>0 b<=0", 3,  c5:get("nested")(3, -1))
check("nested: a<=0",     0,  c5:get("nested")(-1, 5))
c5:free()

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("var mutation tests passed")
