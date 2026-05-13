package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(term gen (x) multi)
(rule gen 10
  (x)
  (expr x))
(rule gen 9
  (x)
  (expr (+ x 1)))

(term gen_none (x) multi)
(rule gen_none 10
  (x)
  (when false)
  (expr x))

(term calc (x y))
(rule calc 10
  (x y)
  (expr (let ((z (+ x y)))
            (if (> z 5) z (* z 2)))))

(term firstv (x))
(rule firstv 10
  (x)
  (expr (first (gen x) -1)))

(term anyv (x))
(rule anyv 10
  (x)
  (expr (any (gen x))))

(term anynone (x))
(rule anynone 10
  (x)
  (expr (any (gen_none x))))
]]

local mod = Lisle.load(spec, "test_lisle_let_ops_first_any")

assert(mod.calc({}, 1, 2) == 6)  -- z=3 => z*2
assert(mod.calc({}, 4, 3) == 7)  -- z=7 => z
assert(mod.firstv({}, 10) == 10)
assert(mod.anyv({}, 10) == true)
assert(mod.anynone({}, 10) == false)

print("lisle let/ops/first/any: ok")
