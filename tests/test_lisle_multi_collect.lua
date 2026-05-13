package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type K
  (A x)
  (B y)
)

(term gen (k) multi)
(rule gen 10
  ((A x))
  (expr x))
(rule gen 9
  ((B y))
  (expr y))

(term to_list (k))
(rule to_list 10
  (k)
  (expr (collect (gen k))))
]]

local mod = Lisle.load(spec, "test_lisle_multi_collect")

local a = mod.to_list({}, { kind = "A", x = 7 })
assert(type(a) == "table" and #a == 1 and a[1] == 7)

local b = mod.to_list({}, { kind = "B", y = 9 })
assert(type(b) == "table" and #b == 1 and b[1] == 9)

print("lisle multi collect: ok")
