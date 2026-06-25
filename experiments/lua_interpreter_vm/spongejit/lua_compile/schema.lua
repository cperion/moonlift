-- lua_compile/schema.lua -- ASDL bootstrap for the SpongeJIT LuaCompile rewrite.
--
-- This module is intentionally the only place that loads the textual ASDL
-- schema.  All other LuaCompile modules consume the ASDL context/constructors
-- exposed here.

local pvm = require("lalin.pvm")

local M = {}

local SCHEMA_PATH = "experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl"
local cached = nil

local function module_dir()
  local src = debug.getinfo(1, "S").source or ""
  if src:sub(1, 1) == "@" then return src:sub(2):match("^(.*)/lua_compile/schema%.lua$") end
  return nil
end

local function candidate_paths()
  local dir = module_dir()
  local out = { SCHEMA_PATH }
  if dir then out[#out + 1] = dir .. "/ssa_asdl/spongejit_lua_ssa.asdl" end
  out[#out + 1] = "ssa_asdl/spongejit_lua_ssa.asdl"
  return out
end

local function read_file(path)
  local last_err
  for _, p in ipairs(candidate_paths()) do
    if p then
      local f, err = io.open(p, "r")
      if f then local text = f:read("*a"); f:close(); return text end
      last_err = err
    end
  end
  error("LuaCompile schema: cannot open " .. tostring(path) .. ": " .. tostring(last_err), 2)
end

local function strip_lua_line_comments(text)
  -- lalin.asdl_parser accepts # comments, while this project schema is
  -- documented with Lua-style -- comments. Keep comment stripping here rather
  -- than weakening the canonical ASDL lexer globally.
  return (text or ""):gsub("%-%-[^\n]*", "")
end

function M.schema_path()
  return SCHEMA_PATH
end

function M.source()
  return read_file(SCHEMA_PATH)
end

function M.parser_source()
  return strip_lua_line_comments(M.source())
end

function M.new_context(opts)
  local T = pvm.context(opts)
  T:Define(M.parser_source())
  return T
end

function M.get(opts)
  if opts and opts.fresh then return M.new_context(opts) end
  if cached == nil then cached = M.new_context(opts) end
  return cached
end

function M.builders(opts)
  return M.get(opts):Builders(opts and opts.trusted)
end

function M.classof(node)
  return pvm.classof(node)
end

return M
