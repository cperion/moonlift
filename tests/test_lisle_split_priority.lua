package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type K
  (A x)
  (B y)
)

(term pick (k))

(rule pick 100
  ((A x))
  (expr "a"))

(rule pick 90
  (k)
  (expr "any"))

(rule pick 80
  ((B y))
  (expr "b"))
]]

local mod = Lisle.load(spec, "test_lisle_split_priority")

assert(mod.pick({}, { kind = "A", x = 1 }) == "a")
-- wildcard rule at higher priority than B-specific rule must win.
assert(mod.pick({}, { kind = "B", y = 2 }) == "any")

print("lisle split priority: ok")
