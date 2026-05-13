package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(decl partial extern rec extn (I32 I32) I32)

(term wrap (x y))
(rule wrap 10
  (x y)
  (expr (extn x y)))
]]

local mod = Lisle.load(spec, "test_lisle_decl_modifiers")
local ctx = {
  extern = {
    extn = function(_, a, b)
      return a * b
    end,
  },
}

assert(mod.wrap(ctx, 6, 7) == 42)

print("lisle decl modifiers: ok")
