package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(extern ext_pick (x y))

(term wrap (x y))
(rule wrap 10
  (x y)
  (expr (ext_pick x y)))
]]

local mod = Lisle.load(spec, "test_lisle_extern")

local ctx = {
  extern = {
    ext_pick = function(_, x, y)
      return x + y
    end,
  },
}

assert(mod.wrap(ctx, 3, 9) == 12)

print("lisle extern: ok")
