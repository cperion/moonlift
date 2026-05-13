package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compile = require("moonlift.lisle.compile")
local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(term sel (a b))
(rule sel 10
  (a b)
  (when (= a b))
  (expr 1))
(rule sel 9
  (a b)
  (when (~= a b))
  (expr 2))
]]

local code = select(1, Compile.compile_source(spec, "test_lisle_decision_equal_split"))
assert(code:match("if a == b then"), "expected equality split in generated code")

local mod = Lisle.load(spec, "test_lisle_decision_equal_split_run")
assert(mod.sel({}, 4, 4) == 1)
assert(mod.sel({}, 4, 7) == 2)

print("lisle decision equal split: ok")
