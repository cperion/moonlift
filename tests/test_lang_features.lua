package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local Run = require("moonlift.mlua_run")
local ffi = require("ffi")

local function compile(src)
    local p = "/tmp/_lf.mlua"
    local f = assert(io.open(p, "w")); f:write(src); f:close()
    local values = Run.dofile(p)
    if values and values.kind == "func" then values = { [values.name] = values } end
    local compiled = {}
    for name, value in pairs(values or {}) do
        if type(value) == "table" and value.kind == "func" then compiled[name] = value:compile() end
    end
    return {
        get = function(_, name) return assert(compiled[name], "missing compiled function: " .. tostring(name)) end,
        free = function() for _, c in pairs(compiled) do c:free() end end,
    }
end

local pass, fail = 0, 0
local function check(n, exp, got)
    local e, g = tonumber(exp), tonumber(got)
    if e == g then pass=pass+1; io.write(string.format("  OK   %-40s = %s\n", n, g))
    else fail=fail+1; io.write(string.format("  FAIL %-40s expected %s got %s\n", n, e, g)) end
end

print("--- let/var type inference ---")
local c1 = compile([[local f = func(x: i32) -> i32
    let y = x + 1
    let z = y * 2
    return z
end
return { f = f }]])
check("let infer: f(5)=12",  12, c1:get("f")(5))
check("let infer: f(10)=22", 22, c1:get("f")(10))
c1:free()

local c2 = compile([[local h = func(x: i32) -> i32
    var acc = 0
    if x > 0 then acc = x * 2 end
    return acc
end
return { h = h }]])
check("var infer + mut: h(5)=10", 10, c2:get("h")(5))
check("var infer + mut: h(-1)=0",  0, c2:get("h")(-1))
c2:free()

print("\n--- pointer arithmetic ---")
local c3 = compile([[local ptr_next = func(p: ptr(u32), n: i32) -> ptr(u32)
    return p + n
end
local ptr_prev = func(p: ptr(u32), n: i32) -> ptr(u32)
    return p - n
end
local load_at = func(p: ptr(u32), n: i32) -> u32
    let q = p + n
    return q[0]
end
return { ptr_next = ptr_next, ptr_prev = ptr_prev, load_at = load_at }]])
local buf = ffi.new("uint32_t[8]"); for i=0,7 do buf[i]=i*10 end
local vp = ffi.cast("void*", buf)
check("ptr+3 → buf[3]=30", 30, ffi.cast("uint32_t*", c3:get("ptr_next")(vp,3))[0])
check("ptr-1 → buf[0]=0",   0, ffi.cast("uint32_t*", c3:get("ptr_prev")(ffi.cast("void*",ffi.cast("uint32_t*",buf)+1),1))[0])
check("load_at(p,4)=40",   40, c3:get("load_at")(vp, 4))
c3:free()

print("\n--- named constants via Lua splices ---")
local c4 = compile([[local decode = func(op: i32) -> i32
    return block b(v: i32 = 0) -> i32
        switch op do
        case 41 then yield 1
        case 10 then yield 2
        case 76 then yield 3
        default then yield 0
        end
    end
end
return { decode = decode }]])
check("BC_KSHORT=41→1", 1, c4:get("decode")(41))
check("BC_ADDVV=10→2",  2, c4:get("decode")(10))
check("BC_RET=76→3",    3, c4:get("decode")(76))
check("unknown=99→0",   0, c4:get("decode")(99))
c4:free()

local c4b = compile([[local classify = func(op: i32) -> i32
    return switch op do
    case 11 then 100
    case 12 then
        let x = 20
        x + 2
    default then
        let y = 3
        y
    end
end
return { classify = classify }]])
check("switch expr const arm", 100, c4b:get("classify")(11))
check("switch expr stmt arm", 22, c4b:get("classify")(12))
check("switch expr default body", 3, c4b:get("classify")(99))
c4b:free()

local c5 = compile([[local load_u64 = func(base: ptr(u64), idx: i32) -> u64
    let p = base + idx
    return p[0]
end
return { load_u64 = load_u64 }]])
local buf64 = ffi.new("uint64_t[4]"); buf64[0]=100; buf64[1]=200; buf64[2]=300; buf64[3]=400
check("ptr+idx u64 elem", 300, c5:get("load_u64")(ffi.cast("void*",buf64), 2))
c5:free()

local c6 = compile([[local sum4 = func(p: ptr(i32)) -> i32
    let a = p[0]
    let b = p[1]
    let c = p[2]
    let d = p[3]
    return a + b + c + d
end
return { sum4 = sum4 }]])
local arr = ffi.new("int32_t[4]"); arr[0]=1; arr[1]=2; arr[2]=3; arr[3]=4
check("let infer array read sum=10", 10, c6:get("sum4")(ffi.cast("void*",arr)))
c6:free()

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
print("All language-fix tests passed")
