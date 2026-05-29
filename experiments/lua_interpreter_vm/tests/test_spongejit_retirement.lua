#!/usr/bin/env luajit
-- Maintained SpongeJIT source must not retain the old C-function tile ABI.

local roots = {
  "experiments/lua_interpreter_vm/spongejit",
  "experiments/lua_interpreter_vm/tests",
}

local source_ext = {
  ["lua"] = true, ["c"] = true, ["h"] = true, ["sh"] = true, ["mk"] = true,
}

local needles = {
  "SponTileId",
  "SponTileDesc",
  "SponHoleReloc",
  "SPON_HOLE_EXIT",
  "SPON_HOLE_FAIL",
  "src.stencil_to_c",
  "grammar_c_code",
  "grammar_holes",
  "spon_get_tile",
  "spon_tile_data",
  "spon_tile_holes",
}

local allow = {
  ["experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua"] = true,
}

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'"
end

local function should_scan(path)
  if allow[path] then return false end
  if path:find("/build/", 1, true) then return false end
  if path:find("/.pi/", 1, true) then return false end
  if path:match("Makefile$") then return true end
  local ext = path:match("%.([^.]+)$")
  return ext and source_ext[ext] or false
end

local paths = {}
for _, root in ipairs(roots) do
  local p = io.popen("find " .. shell_quote(root) .. " -type f 2>/dev/null", "r")
  if p then
    for line in p:lines() do if should_scan(line) then paths[#paths + 1] = line end end
    p:close()
  end
end

local failures = {}
for _, path in ipairs(paths) do
  local f = io.open(path, "rb")
  local s = f and f:read("*a") or ""
  if f then f:close() end
  for _, needle in ipairs(needles) do
    if s:find(needle, 1, true) then failures[#failures + 1] = path .. ": stale legacy token " .. needle end
  end
end

if #failures > 0 then error("legacy C-function tile ABI tokens remain:\n" .. table.concat(failures, "\n"), 0) end

print("ok - SpongeJIT legacy tile ABI retired from maintained source")
