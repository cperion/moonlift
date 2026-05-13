package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

-- Equal-priority rules that are syntactically close but semantically disjoint
-- due to repeated-variable equality constraints.
local spec = [[
(type P
  (Pair a b)
)

(term pick (p))
(rule pick 10
  ((Pair x x))
  (expr "eq"))
(rule pick 10
  ((Pair 1 2))
  (expr "one-two"))
(default pick
  (expr "other"))
]]

local mod = Lisle.load(spec, "test_lisle_overlap_precision")

assert(mod.pick({}, { kind = "Pair", a = 7, b = 7 }) == "eq")
assert(mod.pick({}, { kind = "Pair", a = 1, b = 2 }) == "one-two")
assert(mod.pick({}, { kind = "Pair", a = 2, b = 1 }) == "other")

print("lisle overlap precision: ok")
