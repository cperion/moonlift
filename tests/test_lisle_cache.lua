package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compile = require("moonlift.lisle.compile")

local spec = [[
(term add1 (x))
(rule add1 10
  (x)
  (expr (+ x 1)))
]]

local modname = "test_lisle_cache_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))

local m1, code1, spec1, info1 = Compile.load_source(spec, modname, nil, { cache = true })
assert(type(m1.add1) == "function")
assert(m1.add1({}, 41) == 42)
assert(info1 and info1.cached == false)
assert(type(code1) == "string" and spec1 ~= nil)

local m2, code2, spec2, info2 = Compile.load_source(spec, modname, nil, { cache = true })
assert(type(m2.add1) == "function")
assert(m2.add1({}, 99) == 100)
assert(info2 and info2.cached == true)
assert(type(code2) == "string")
assert(spec2 == nil)

print("lisle cache: ok")
