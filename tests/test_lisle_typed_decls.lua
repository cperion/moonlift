package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Pair
  (P (a I32) (b I32))
)

(term mk (((x I32)) ((y I32))))
(rule mk 10
  (x y)
  (expr (P x y)))

(term fst ((p Pair)))
(rule fst 10
  ((P a b))
  (expr a))
]]

-- Normalize weird nested arg forms into simple lists is not supported;
-- use strict (name type) entries.
spec = [[
(type Pair
  (P (a I32) (b I32))
)

(term mk ((x I32) (y I32)))
(rule mk 10
  (x y)
  (expr (P x y)))

(term fst ((p Pair)))
(rule fst 10
  ((P a b))
  (expr a))
]]

local mod = Lisle.load(spec, "test_lisle_typed_decls")
local p = mod.mk({}, 3, 4)
assert(p.kind == "P" and p.a == 3 and p.b == 4)
assert(mod.fst({}, p) == 3)

local bad = [[
(term t ((x I32)))
(term t ((x I64)))
]]
local ok, err = pcall(function() Lisle.load(bad, "test_lisle_typed_decls_bad") end)
assert(not ok)
assert(tostring(err):find("arg type mismatch", 1, true), tostring(err))

print("lisle typed decls: ok")
