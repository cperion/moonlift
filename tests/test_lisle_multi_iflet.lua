package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Opt
  (Some v)
  (None)
)

(term genopt (x) multi)
(rule genopt 10
  (x)
  (expr (Some x)))
(rule genopt 9
  (x)
  (expr None))

(term pick_or (x d))
(rule pick_or 10
  (x d)
  (expr (if-let ((Some v) (genopt x)) v d)))
]]

local mod = Lisle.load(spec, "test_lisle_multi_iflet")

assert(mod.pick_or({}, 11, 2) == 11)

print("lisle multi if-let: ok")
