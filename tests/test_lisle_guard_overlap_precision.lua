package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Pair
  (P a b)
)

(term pick_num (x))
(rule pick_num 10
  (x)
  (when (= x 0))
  (expr 1))
(rule pick_num 10
  (x)
  (when (~= x 0))
  (expr 2))

(term pick_pair (p))
(rule pick_pair 10
  ((P a b))
  (when (= a b))
  (expr 10))
(rule pick_pair 10
  ((P a b))
  (when (~= a b))
  (expr 20))
]]

local mod = Lisle.load(spec, "test_lisle_guard_overlap_precision")
assert(mod.pick_num({}, 0) == 1)
assert(mod.pick_num({}, 5) == 2)
assert(mod.pick_pair({}, { kind = "P", a = 7, b = 7 }) == 10)
assert(mod.pick_pair({}, { kind = "P", a = 7, b = 8 }) == 20)

print("lisle guard overlap precision: ok")
