package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type K
  (A x)
  (B y z)
  (C)
)

(term pick (k v))

(rule pick 100
  ((A x) v)
  (when "x == 1")
  (lua "return 'a1:' .. tostring(v)"))

(rule pick 90
  ((B y z) v)
  (when "y == z")
  (lua "return 'beq'"))

(rule pick 80
  ((C) v)
  (lua "return 'c'"))

(default pick
  (lua "return 'd'"))
]]

local mod = Lisle.load(spec, "test_lisle_basic")

assert(mod.pick({}, { kind = "A", x = 1 }, 9) == "a1:9")
assert(mod.pick({}, { kind = "B", y = 7, z = 7 }, 0) == "beq")
assert(mod.pick({}, { kind = "C" }, 0) == "c")
assert(mod.pick({}, { kind = "A", x = 2 }, 0) == "d")

print("lisle basic: ok")
