package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local bad1 = [[
(extern extractor missing_term ext_impl)
]]

local ok1, err1 = pcall(function()
  Lisle.load(bad1, "test_lisle_contracts_bad1")
end)
assert(ok1 == false)
assert(tostring(err1):match("extern extractor references unknown term"))

local bad2 = [[
(term no_rules (x))
]]

local ok2, err2 = pcall(function()
  Lisle.load(bad2, "test_lisle_contracts_bad2")
end)
assert(ok2 == false)
assert(tostring(err2):match("non%-partial term 'no_rules' has no rules/default"))

local good = [[
(decl extern ext_ok (I32) I32)
(extern extractor ext_ok ext_ok_impl)
(term use_ext (x))
(rule use_ext 10
  (x)
  (expr (ext_ok x)))
]]

local mod = Lisle.load(good, "test_lisle_contracts_good")
local ctx = { extern = { ext_ok_impl = function(_, x) return x + 3 end } }
assert(mod.use_ext(ctx, 7) == 10)

print("lisle contracts: ok")
