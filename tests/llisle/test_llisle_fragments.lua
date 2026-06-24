package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local llisle = require("llisle")

local env = moon.family.env { scope = "env", base = {} }
llisle.use { scope = "env", target = env, base = env, global = false }
local chunk = assert(loadstring([[
local scalar_rules = llisle.rules {
  rule. lower_const_i32 {
    llisle.lower_expr { expr = P. expr, ctx = P. ctx },
    when { (P. expr :is_const ()) * (P. expr :has_type (ml.i32)) },
    run { ret { value = V. out } },
  },
}

local arith_rules = llisle.rules {
  rule. lower_add_i32 {
    llisle.lower_expr { expr = add { lhs = P. lhs, rhs = P. rhs } [ml.i32], ctx = P. ctx },
    run { ret { value = V. out } },
  },
}

return llisle {
  relation. lower_expr {
    input { expr [ml.i32], ctx [LowerCtx] },
    output { value [BackValue] },
  },
  _(scalar_rules .. arith_rules),
}
]], "llisle_fragments.lua"))
setfenv(chunk, env)
local zone = chunk()

assert(#zone.items == 3, "llisle rule fragments splice into zones")
assert(getmetatable(zone.items[2]) == llisle.RuleSpec, "first spliced item is a rule")
assert(getmetatable(zone.items[3]) == llisle.RuleSpec, "second spliced item is a rule")
assert(not moon.family.diagnostics(zone):has_errors(), "spliced llisle rules validate")

io.write("llisle fragments ok\n")
