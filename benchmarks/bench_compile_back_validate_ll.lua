package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")

local SRC = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end
]]

local function now() return os.clock() end
local function ms(x) return x * 1000.0 end

local function build_case()
    local T = pvm.context()
    A.Define(T)
    local P = Parse.Define(T)
    local TC = Typecheck.Define(T)
    local L = Lower.Define(T)
    local V = Validate.Define(T)
    local parsed = P.parse_module(SRC)
    assert(#parsed.issues == 0)
    local checked = TC.check_module(parsed.module)
    assert(#checked.issues == 0)
    local program = L.module(checked.module)
    return { V = V, program = program }
end

local rounds = tonumber(arg[1]) or 30
local cases = {}
for i = 1, rounds do cases[i] = build_case() end
local cmds = #cases[1].program.cmds
collectgarbage("collect")

local verbose = arg[1] == "verbose" or arg[2] == "verbose"
local rounds = tonumber(arg[1]) or 30
if verbose then rounds = tonumber(arg[2]) or 10 end

local t0 = now()
for i = 1, rounds do assert(#cases[i].V.validate_pvm_cold(cases[i].program).issues == 0) end
local lua_dt = now() - t0
collectgarbage("collect")
local t1 = now()
for i = 1, rounds do assert(#cases[i].V.validate_ll(cases[i].program).issues == 0) end
local ll_dt = now() - t1
collectgarbage("collect")
local t2 = now()
for i = 1, rounds do cases[i].V.validate_verify(cases[i].program) end
local verify_dt = now() - t2

print(string.format("program_cmds %d", cmds))
print(string.format("fresh_programs %d", rounds))
print(string.format("%-24s %9.3f ms total %8.3f ms/program", "pvm_triplet_cold", ms(lua_dt), ms(lua_dt) / rounds))
print(string.format("%-24s %9.3f ms total %8.3f ms/program", "flat", ms(ll_dt), ms(ll_dt) / rounds))
print(string.format("%-24s %9.3f ms total %8.3f ms/program", "verify", ms(verify_dt), ms(verify_dt) / rounds))
print(string.format("speedup(flat/cold) %.2fx", lua_dt / ll_dt))
if verbose then
    local ref = cases[1].V.validate_pvm_cold(cases[1].program)
    local fast = cases[1].V.validate_ll(cases[1].program)
    print(string.format("  ref_issues=%d fast_issues=%d match=%s", #ref.issues, #fast.issues, #ref.issues == #fast.issues and "yes" or "no"))
end
