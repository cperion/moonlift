package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Opt
  (Some v)
  (None)
)

(term classify (x))
(rule classify 10
  (x)
  (expr (match x
    ((Some v) v)
    (None 0)
    ((default -1))
  )))
]]

-- Normalize default arm syntax to supported form (default expr)
spec = [[
(type Opt
  (Some v)
  (None)
)

(term classify (x))
(rule classify 10
  (x)
  (expr (match x
    ((Some v) v)
    (None 0)
    (default -1)
  )))
]]

local mod = Lisle.load(spec, "test_lisle_match")

assert(mod.classify({}, { kind = "Some", v = 8 }) == 8)
assert(mod.classify({}, { kind = "None" }) == 0)
assert(mod.classify({}, 99) == -1)

print("lisle match: ok")
