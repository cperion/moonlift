-- lalin.loader
--
-- First-class .lln value loading.  A .lln file is a Lua chunk with Lalin parsed
-- syntax active by default.  It returns ordinary Lua values; Lua require and
-- package.loaded remain the module system.

local Loader = {}

local syntax = require("llbl.syntax")
require("lalin.syntax")

Loader.path = os.getenv("LALIN_PATH") or "./?.lln;./?/init.lln;lua/?.lln;lua/?/init.lln"

local function copy_opts(opts)
  local out = {}
  if opts then for k, v in pairs(opts) do out[k] = v end end
  return out
end

local function readable(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function path_value(path_or_fn)
  if type(path_or_fn) == "function" then return path_or_fn() end
  return path_or_fn or Loader.path
end

local function active_languages(opts)
  local out = { "lalin" }
  local seen = { lalin = true }
  for _, lang in ipairs(opts.active_languages or {}) do
    if type(lang) == "string" and not seen[lang] then
      seen[lang] = true
      out[#out + 1] = lang
    end
  end
  return out
end

local function default_env()
  return require("lalin").dsl.make_env { no_namespaces = true }
end

local function merge_env(user_env)
  local base = default_env()
  if user_env == nil then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(user_env) do out[k] = v end
  return out
end

local function compile_opts(opts)
  opts = copy_opts(opts)
  opts.active_languages = active_languages(opts)
  opts.allow_import = false
  opts.env = merge_env(opts.env)
  return opts
end

function Loader.loadstring(source, chunkname, opts)
  return syntax.loadstring(source, chunkname or "=(lalin .lln)", compile_opts(opts))
end

function Loader.loadfile(path, opts)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local source = f:read("*a") or ""
  f:close()
  return Loader.loadstring(source, "@" .. path, opts)
end

function Loader.dofile(path, opts, ...)
  local chunk, err = Loader.loadfile(path, opts)
  if not chunk then error(err, 2) end
  return chunk(...)
end

local function escape_pattern(s)
  return (tostring(s):gsub("([^%w])", "%%%1"))
end

function Loader.searchpath(name, path, sep, rep)
  path = path_value(path)
  sep = sep or "."
  rep = rep or "/"
  local mod_path = tostring(name):gsub(escape_pattern(sep), rep)
  local tried = {}
  for template in tostring(path or ""):gmatch("[^;]+") do
    if template ~= "" then
      local candidate = template:gsub("%?", mod_path)
      if readable(candidate) then return candidate end
      tried[#tried + 1] = candidate
    end
  end
  return nil, "\n\tno .lln file found (tried: " .. table.concat(tried, ", ") .. ")"
end

function Loader.loadmodule(name, opts)
  opts = opts or {}
  local path, err = Loader.searchpath(name, opts.path or Loader.path, opts.sep, opts.rep)
  if not path then return nil, err end
  local load_opts = opts.load_opts or opts
  local chunk, load_err = Loader.loadfile(path, load_opts)
  if not chunk then return nil, load_err end
  return chunk, path
end

function Loader.require(name, opts)
  if package.loaded[name] then return package.loaded[name] end
  local chunk, path_or_err = Loader.loadmodule(name, opts)
  if not chunk then error("module '" .. tostring(name) .. "' not found:" .. tostring(path_or_err), 2) end

  package.loaded[name] = true
  local ok, result = pcall(chunk, name, path_or_err)
  if not ok then
    package.loaded[name] = nil
    error(result, 0)
  end
  if result ~= nil then package.loaded[name] = result end
  return package.loaded[name]
end

function Loader.searcher(name, opts)
  local chunk, path_or_err = Loader.loadmodule(name, opts)
  if not chunk then return path_or_err end
  return function()
    return chunk(name, path_or_err)
  end, path_or_err
end

function Loader.install_searcher(opts)
  opts = copy_opts(opts)
  local searchers = package.searchers or package.loaders
  if not searchers then return false end
  if Loader._searcher then
    for _, searcher in ipairs(searchers) do
      if searcher == Loader._searcher then return true end
    end
  end
  local function searcher(name)
    return Loader.searcher(name, opts)
  end
  Loader._searcher = searcher
  local index = tonumber(opts.index)
  if index and index >= 1 and index <= #searchers + 1 then
    table.insert(searchers, index, searcher)
  else
    table.insert(searchers, searcher)
  end
  return true
end

function Loader.remove_searcher()
  local searchers = package.searchers or package.loaders
  if not searchers or not Loader._searcher then return false end
  for i = #searchers, 1, -1 do
    if searchers[i] == Loader._searcher then
      table.remove(searchers, i)
      return true
    end
  end
  return false
end

return Loader
