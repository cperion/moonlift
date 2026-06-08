package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")

local mom = require("moonlift.host_mom")
local Host = require("moonlift.mlua_run")

local MOM_SRC = [[ func f(x: i32, y: i32): i32 return x + y end ]]
local MLUA = [[ local f = func(x: i32, y: i32): i32 return x + y end return f ]]

-- verify
local c = mom(MOM_SRC)
assert(ffi.cast("int32_t (*)(int32_t, int32_t)", c:get("f"))(20,22) == 42)
c:free()

local chunk = Host.loadstring(MLUA, "t.mlua")
local lc = chunk():compile()
assert(ffi.cast("int32_t (*)(int32_t, int32_t)", lc.fn)(20,22) == 42)
lc:free()

local W, T = 5, 50

for i = 1, W do
  mom(MOM_SRC):free()
  chunk = Host.loadstring(MLUA, "t.mlua")
  chunk():compile():free()
end
collectgarbage()

local t0 = os.clock()
for i = 1, T do mom(MOM_SRC):free() end
local tm = (os.clock() - t0) / T * 1000
collectgarbage()

local t0 = os.clock()
for i = 1, T do
  chunk = Host.loadstring(MLUA, "t.mlua")
  chunk():compile():free()
end
local tl = (os.clock() - t0) / T * 1000
collectgarbage()

print(string.format("MOM:           %.3f ms  (%d trials)", tm, T))
print(string.format("Lua frontend:  %.3f ms  (%d trials)", tl, T))
print(string.format("MOM is %.1fx faster", tl / tm))
