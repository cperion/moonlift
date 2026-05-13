package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compile = require("moonlift.lisle.compile")

local spec = [[
(type C
  (A x)
  (B y)
)

(term f (c))
(rule f 10
  ((A x))
  (expr x))
(rule f 9
  ((B y))
  (expr y))
]]

local code = select(1, Compile.compile_source(spec, "test_lisle_codegen_split_dedup"))

local a_checks = 0
for _ in code:gmatch('kind == "A"') do a_checks = a_checks + 1 end
local b_checks = 0
for _ in code:gmatch('kind == "B"') do b_checks = b_checks + 1 end

assert(a_checks == 1, "expected exactly one A kind check, got " .. tostring(a_checks))
assert(b_checks == 1, "expected exactly one B kind check, got " .. tostring(b_checks))

print("lisle codegen split dedup: ok")
