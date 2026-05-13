package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type K
  (C x)
)

(extern constructor C mkC)

(decl extern ext_pick (a b) I32)
(extern extractor ext_pick ext_pick_impl)

(term make (x))
(rule make 10
  (x)
  (expr (C x)))

(term use_ext (x y))
(rule use_ext 10
  (x y)
  (expr (ext_pick x y)))
]]

local calls = { ctor = 0, ext = 0 }
local ctx = {
  ctor = {
    mkC = function(v)
      calls.ctor = calls.ctor + 1
      return { kind = "C", x = v, tagged = true }
    end,
  },
  extern = {
    ext_pick_impl = function(_, a, b)
      calls.ext = calls.ext + 1
      return a + b
    end,
  },
}

local mod = Lisle.load(spec, "test_lisle_extern_aliases")
local c = mod.make(ctx, 5)
assert(c.kind == "C" and c.x == 5 and c.tagged == true)
assert(mod.use_ext(ctx, 4, 7) == 11)
assert(calls.ctor == 1 and calls.ext == 1)

print("lisle extern aliases: ok")
