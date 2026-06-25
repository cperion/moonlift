-- lalin_cfg_emit.lua -- LalinCFG emission facade.
--
-- Emit.emit is intentionally preserved as compatibility/debug source
-- serialization.  New semantic execution must go through the quote-first
-- LalinCFG -> lalin.* typed quoted-fragment path exposed by build/compile/run.
-- Do not add hand-concatenated semantic Lalin code here.

local pvm = require("lalin.pvm")
local SourceCompat = require("lua_compile.lalin_cfg_emit_source_compat")

local M = {}

local phase = pvm.phase("spongejit_lalin_cfg_emit", function(kernel, name)
  return SourceCompat.emit_uncached(kernel, { name = name ~= "" and name or nil })
end, { args_cache = "last" })

function M.emit(kernel, opts)
  opts = opts or {}
  return pvm.one(phase(kernel, tostring(opts.name or "")))
end

M.phase = phase
M.emit_uncached = SourceCompat.emit_uncached
M.source_compat = SourceCompat

local function quote_emit()
  return require("lua_compile.lalin_cfg_quote_emit")
end

function M.build(kernel, opts)
  return quote_emit().build(kernel, opts or {})
end

function M.build_func(kernel, opts)
  return quote_emit().build_func(kernel, opts or {})
end

function M.build_bundle(kernel, opts)
  return quote_emit().build_bundle(kernel, opts or {})
end

function M.compile(kernel, opts)
  return quote_emit().compile(kernel, opts or {})
end

function M.run(kernel, opts, ...)
  return quote_emit().run(kernel, opts or {}, ...)
end

return M
