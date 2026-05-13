package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Opt
  (Some v)
  (None)
)

(term unwrap_or (x d))
(rule unwrap_or 10
  (x d)
  (expr (if-let ((Some v) x) v d)))
]]

local mod = Lisle.load(spec, "test_lisle_iflet")

assert(mod.unwrap_or({}, { kind = "Some", v = 7 }, 2) == 7)
assert(mod.unwrap_or({}, { kind = "None" }, 2) == 2)

print("lisle if-let: ok")
