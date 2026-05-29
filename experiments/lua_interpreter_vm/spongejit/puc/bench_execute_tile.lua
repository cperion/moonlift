#!/usr/bin/env luajit
-- Build/run the minimal real semantic tile execution benchmark.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/bench_execute_tile%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo = spongejit:sub(1, 1) == "/" and spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "") or "."

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
  io.stderr:write("[bench-exec-tile] ", cmd, "\n")
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local build = false
local iters = "100000000"
local pattern = "UNM,BNOT,MUL,ADDI"
local positional = {}
local i = 1
while i <= #arg do
  if arg[i] == "--build" then build = true else positional[#positional + 1] = arg[i] end
  i = i + 1
end
if positional[1] then iters = positional[1] end
if positional[2] then pattern = positional[2] end

local out = spongejit .. "/build/bench_execute_tile"
local exe = out .. "/bench_execute_tile"
local c = spongejit .. "/puc/bench_execute_tile.c"
local vendor = repo .. "/.vendor/Lua"
local bank_dir = spongejit .. "/build/cp_lib"
local bank_so = bank_dir .. "/libsponbank.so"
if not exists(bank_so) then error("missing current bank: " .. bank_so) end

if build or not exists(exe) then
  run("mkdir -p " .. q(out))
  run(table.concat({
    "gcc -O2 -DNDEBUG",
    "-I" .. q(vendor),
    "-I" .. q(spongejit .. "/include"),
    q(c),
    q(vendor .. "/liblua.a"),
    "-L" .. q(bank_dir),
    "-Wl,-rpath," .. q(bank_dir),
    "-lsponbank -lm -ldl",
    "-o " .. q(exe),
  }, " "))
end

run("LD_LIBRARY_PATH=" .. q(bank_dir) .. " " .. q(exe) .. " " .. q(iters) .. " " .. q(pattern))
