package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")

local mom = require("moonlift.host_mom")
local Host = require("moonlift.mlua_run")

-- Pick a MOM module to compile through both frontends.
-- For MOM: extract the moonlift func/region defs from the .mlua file
-- For Lua: load the full .mlua through Host.dofile

local function extract_moonlift(filepath)
  local f = assert(io.open(filepath, "r"))
  local src = f:read("*a")
  f:close()
  -- Strip Lua carrier lines, keep only func/region/extern/struct/union declarations
  local lines = {}
  local in_lua_block = 0
  for line in src:gmatch("[^\n]+") do
    if line:match("^local%s+(.-)=") then
      -- Lua carrier line, but the rest might have moonlift
      local rest = line:gsub("^local%s+.-=", "")
      if rest:match("%s*func%s") or rest:match("%s*region%s") or rest:match("%s*extern%s") or rest:match("%s*struct%s") or rest:match("%s*expr%s") then
        lines[#lines+1] = rest
      end
    elseif line:match("^%s*func%s") or line:match("^%s*region%s") or line:match("^%s*extern%s") or line:match("^%s*struct%s") or line:match("^%s*union%s") or line:match("^%s*expr%s") then
      lines[#lines+1] = line
    elseif line:match("^%s*end%s*$") then
      lines[#lines+1] = line
    elseif line:match("^%s*return%s") or line:match("^%s*jump%s") or line:match("^%s*yield%s") or line:match("^%s*if%s") or line:match("^%s*else") or line:match("^%s*elseif%s") or line:match("^%s*switch%s") or line:match("^%s*case%s") or line:match("^%s*default%s") or line:match("^%s*let%s") or line:match("^%s*var%s") or line:match("^%s*block%s") or line:match("^%s*entry%s") or line:match("^%s*do%s") or line:match("^%s*then%s") or line:match("^%s*emit%s") or line:match("^%s*local%s") or line:match("^%s*moon%.") or line:match("^%s*--") or line:match("^%s*$") then
      lines[#lines+1] = line
    elseif line:match("M:add_func") or line:match("return M") then
      -- skip
    end
  end
  return table.concat(lines, "\n")
end

local filepath = "lua/moonlift/mom/driver/lower_wire.mlua"
local moonlift_src = extract_moonlift(filepath)
local src_lines = {}
for line in moonlift_src:gmatch("[^\n]+") do src_lines[#src_lines+1] = line end

print(string.format("File: %s", filepath))
print(string.format("Moonlift source: %d lines, %d bytes", #src_lines, #moonlift_src))

-- Verify Lua path works
print("Verifying Lua frontend path...")
local mod = Host.dofile(filepath)
local compiled = mod:compile()
compiled:free()

-- Verify MOM path works
print("Verifying MOM path...")
local c = mom(moonlift_src)
c:free()

local W, T = 3, 15

print("Warming up...")
for i = 1, W do
  mod = Host.dofile(filepath)
  mod:compile():free()
  mom(moonlift_src):free()
end
collectgarbage()

print(string.format("Benchmark: %d trials each\n", T))

local t0 = os.clock()
for i = 1, T do
  c = mom(moonlift_src)
  c:free()
end
local tm = (os.clock() - t0) / T * 1000

collectgarbage()

local t0 = os.clock()
for i = 1, T do
  mod = Host.dofile(filepath)
  mod:compile():free()
end
local tl = (os.clock() - t0) / T * 1000

collectgarbage()

print(string.format("%-16s %8s %12s %10s", "Frontend", "Trials", "ms/trial", "comp/s"))
print(string.rep("-", 50))
print(string.format("%-16s %8d %12.3f %10d", "MOM", T, tm, math.floor(1000/tm)))
print(string.format("%-16s %8d %12.3f %10d", "Lua frontend", T, tl, math.floor(1000/tl)))
print(string.rep("-", 50))
print(string.format("MOM is %.1fx faster", tl / tm))
