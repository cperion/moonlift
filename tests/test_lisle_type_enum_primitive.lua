package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Flag
  (enum
    On
    (Off code)
  )
)

(type I32
  (primitive i32)
)

(term code_or_zero (f))
(rule code_or_zero 10
  ((Off c))
  (expr c))
(rule code_or_zero 9
  ((On))
  (expr 0))
]]

local mod = Lisle.load(spec, "test_lisle_type_enum_primitive")
assert(mod.code_or_zero({}, { kind = "Off", code = 12 }) == 12)
assert(mod.code_or_zero({}, { kind = "On" }) == 0)

print("lisle type enum/primitive: ok")
