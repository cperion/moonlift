package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")

local T = pvm.context(); A.Define(T)
local P = Parse.Define(T)

local src = [[
local add = func(
    a: i32,
    b: i32,
): 
    i32
    return a +
           b
end

local scan = region(
    p: ptr(u8),
    n: i32,
    pos: i32;
    ok: cont(
        next: i32,
        value: i32,
    ),
    err: cont(
        pos: i32,
        code: i32,
    ),
)
entry start()
    jump err(pos = pos, code = 1_000)
end
end
]]

local scan = Parse.scan_document(src)
assert(#scan.islands == 2, "expected two islands, got " .. #scan.islands)

local f = P.parse_island(scan, 1)
assert(#f.issues == 0, f.issues[1] and f.issues[1].message)
assert(f.kind == "func")
assert(#f.value.params == 2)

local r = P.parse_island(scan, 2)
assert(#r.issues == 0, r.issues[1] and r.issues[1].message)
assert(r.kind == "region")
assert(#r.value.params == 3)
assert(#r.value.conts == 2)

-- Lexical errors are reported as parse issues on the owning island only.
local bad = Parse.scan_document([[local good = func() end
local bad = func(): i32
    return @
end]])
local good = P.parse_island(bad, 1)
local bad_island = P.parse_island(bad, 2)
assert(#good.issues == 0, "lex issue leaked into previous island")
assert(#bad_island.issues >= 1)
assert(bad_island.issues[1].message:find("invalid character", 1, true) ~= nil)

local contract_scan = Parse.scan_document([[
func contracty(xs: view(i32), n: index, start: index, m: index)
requires window_bounds(
    xs,
    n,
    start,
    m,
)
end]])
local contracty = P.parse_island(contract_scan, 1)
assert(#contracty.issues == 0, contracty.issues[1] and contracty.issues[1].message)
assert(#contracty.value.contracts == 1)

print("moonlift parser multiline ok")
