package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Lisle = require("moonlift.lisle.runtime")

local bad = [[
(term a (x))
(rule a 10
  (x)
  (expr (b x)))

(term b (x))
(rule b 10
  (x)
  (expr (a x)))
]]

local ok, err = pcall(function()
    Lisle.load(bad, "test_lisle_recursion_bad")
end)
assert(not ok)
assert(tostring(err):find("recursive cycle requires 'rec' attr", 1, true), tostring(err))

local good = [[
(term a (x) rec)
(rule a 10
  (x)
  (expr (b x)))

(term b (x) rec)
(rule b 10
  (x)
  (expr x))
]]

local mod = Lisle.load(good, "test_lisle_recursion_good")
assert(mod.a({}, 11) == 11)

print("lisle recursion: ok")
