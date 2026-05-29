#!/usr/bin/env luajit
-- bench_sponbank_puc.lua — build/run the current PUC↔SponBank benchmark.
--
-- This replaces the old patched-VM cache benchmark. It runs the vendored PUC
-- Lua runtime normally, extracts that program's real PUC 5.5 opcodes, and
-- measures current libsponbank selector + copy/patch materialization over those
-- opcode streams.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/bench_sponbank_puc%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo = spongejit:sub(1, 1) == "/" and spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "") or "."

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
  io.stderr:write("[bench-puc-bank] ", cmd, "\n")
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local opts = {
  build = false,
  program = spongejit .. "/bench/programs/int_loop.lua",
  narg = "50000000",
  region_ops = "4096",
  select_iters = "200000",
  mat_iters = "20000",
  lua_reps = "5",
}

local positional = {}
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--build" then opts.build = true
  elseif a == "--region-ops" then opts.region_ops = arg[i + 1]; i = i + 1
  elseif a == "--select-iters" then opts.select_iters = arg[i + 1]; i = i + 1
  elseif a == "--mat-iters" then opts.mat_iters = arg[i + 1]; i = i + 1
  elseif a == "--lua-reps" then opts.lua_reps = arg[i + 1]; i = i + 1
  elseif a == "--" then
    for j = i + 1, #arg do positional[#positional + 1] = arg[j] end
    break
  else
    positional[#positional + 1] = a
  end
  i = i + 1
end
if positional[1] then opts.program = positional[1] end
if positional[2] then opts.narg = positional[2] end

local out = spongejit .. "/build/bench_sponbank_puc"
local exe = out .. "/bench_sponbank_puc"
local c = spongejit .. "/puc/bench_sponbank_puc.c"
local vendor = repo .. "/.vendor/Lua"
local bank_so = spongejit .. "/build/cp_lib/libsponbank.so"

if not exists(bank_so) then
  error("missing current bank: " .. bank_so .. "\nrun: cd " .. spongejit .. " && N=16 ./build_bank.sh")
end

if opts.build or not exists(exe) then
  run("mkdir -p " .. q(out))
  run(table.concat({
    "gcc -O2 -DNDEBUG",
    "-I" .. q(vendor),
    "-I" .. q(spongejit .. "/include"),
    q(c),
    q(vendor .. "/liblua.a"),
    "-L" .. q(spongejit .. "/build/cp_lib"),
    "-Wl,-rpath," .. q(spongejit .. "/build/cp_lib"),
    "-lsponbank -lm -ldl",
    "-o " .. q(exe),
  }, " "))
end

local cmd = table.concat({
  "LD_LIBRARY_PATH=" .. q(spongejit .. "/build/cp_lib"),
  q(exe),
  q(opts.program),
  q(opts.narg),
  q(opts.region_ops),
  q(opts.select_iters),
  q(opts.mat_iters),
  q(opts.lua_reps),
}, " ")
run(cmd)
