package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local mom_init = require("moonlift.mom.init")
local scope, rt = mom_init.load()
local ok, result = pcall(mom_init.compile, scope, { runtime = rt, name = "test" })
if ok then
  print("All files compile OK")
else
  print("COMPILE FAIL: " .. tostring(result))
end
