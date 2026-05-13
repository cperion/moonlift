package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local spec = [[
(type K (A x))
(term pick (k))
(rule pick 10
  ((A x))
  (expr x))
(rule pick 10
  ((A y))
  (expr y))
]]

local ok, err = pcall(function()
    Lisle.load(spec, "test_lisle_ambiguity")
end)

assert(not ok)
assert(tostring(err):find("ambiguous equal%-priority overlap", 1, false), tostring(err))

print("lisle ambiguity: ok")
