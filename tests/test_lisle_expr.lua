package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type Flag
  (T)
  (F)
)

(type Pair
  (P a b)
)

(term is_t (x))
(rule is_t 10
  ((T))
  (expr true))
(default is_t
  (expr false))

(term choose (x y f))
(rule choose 10
  (x y f)
  (expr (if (is_t f) y x)))

(term make_pair (a b))
(rule make_pair 10
  (a b)
  (expr (P a b)))
]]

local mod = Lisle.load(spec, "test_lisle_expr")

assert(mod.is_t({}, { kind = "T" }) == true)
assert(mod.is_t({}, { kind = "F" }) == false)
assert(mod.choose({}, 10, 99, { kind = "T" }) == 99)
assert(mod.choose({}, 10, 99, { kind = "F" }) == 10)

local p = mod.make_pair({}, 3, 4)
assert(type(p) == "table" and p.kind == "P" and p.a == 3 and p.b == 4)

print("lisle expr: ok")
