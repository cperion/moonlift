package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local mom = require("moonlift.host_mom")

local SRC = [[
func ret7(): i32 return 7 end
func add(x: i32, y: i32): i32 return x + y end
func mul_add(a: i32, b: i32, c: i32): i32 return a * b + c end
func neg(x: i32): i32 return -x end
func lt(a: i32, b: i32): bool return a < b end
func eq(a: i32, b: i32): bool return a == b end
func ge(a: i32, b: i32): bool return a >= b end
]]

local WARMUP = 200
local TRIALS = 2000

-- Warmup
for i = 1, WARMUP do
    local c = mom(SRC)
    c:free()
end
collectgarbage()

local t0 = os.clock()
for i = 1, TRIALS do
    local c = mom(SRC)
    c:free()
end
local elapsed = os.clock() - t0

local per_ms = elapsed / TRIALS * 1000

print(string.rep("=", 60))
print("MOM Compilation Speed (in-process)")
print(string.rep("=", 60))
print(string.format("  Source size:     %d bytes", #SRC))
print(string.format("  Trials:          %d", TRIALS))
print(string.format("  Total time:      %.3f s", elapsed))
print(string.format("  Per trial:       %.3f ms", per_ms))
print(string.format("  Compiles/sec:    %.0f", TRIALS / elapsed))
print(string.rep("=", 60))
