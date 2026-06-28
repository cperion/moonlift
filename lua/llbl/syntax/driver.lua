-- llbl.syntax.driver
-- Mixed Lua + parsed-channel source driver.  It scans normal Lua source and
-- replaces registered syntax islands with constructor invocations.  Dialect
-- parsers consume only their islands; normal Lua text is copied unchanged.

local Lexer = require("llbl.syntax.lexer")
local registry = require("llbl.syntax.registry")
local Constructor = require("llbl.syntax.constructor")

local Driver = {}

local function q(s) return string.format("%q", tostring(s)) end

local function valid_ident(s)
  return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function unquote_lua_string(raw)
  local loader = loadstring or load
  local f, err = loader("return " .. raw, "=(llbl syntax import)")
  if not f then error(err, 0) end
  return f()
end

local function unique_refs(refs)
  local out, seen = {}, {}
  for _, r in ipairs(refs or {}) do
    if type(r) == "string" and valid_ident(r) and not seen[r] then
      seen[r] = true
      out[#out + 1] = r
    end
  end
  return out
end

local function previous_significant(source, start_i)
  local i = start_i - 1
  while i >= 1 do
    local c = source:sub(i, i)
    if not c:match("%s") then return c, i end
    i = i - 1
  end
  return nil, nil
end

local function previous_word(source, start_i)
  local i = start_i - 1
  while i >= 1 and source:sub(i, i):match("%s") do i = i - 1 end
  local finish = i
  while i >= 1 and source:sub(i, i):match("[A-Za-z0-9_]") do i = i - 1 end
  if finish >= i + 1 then return source:sub(i + 1, finish) end
  return nil
end

local function separated_by_statement_boundary(source, left_finish, right_start)
  if not left_finish or not right_start then return true end
  local gap = source:sub(left_finish + 1, right_start - 1)
  return gap:match("[\n\r;]") ~= nil
end

local function infer_lua_binding(lex, source)
  local pos = lex.pos
  local eq = lex.tokens[pos - 1]
  if not eq or eq.value ~= "=" then return nil end

  local lhs = lex.tokens[pos - 2]
  if not lhs or lhs.kind ~= "name" or not valid_ident(lhs.value) then return nil end

  local before = lex.tokens[pos - 3]
  local function in_table_field()
    local depth = 0
    for i = pos - 3, 1, -1 do
      local t = lex.tokens[i]
      if t.value == "}" then
        depth = depth + 1
      elseif t.value == "{" then
        if depth == 0 then return true end
        depth = depth - 1
      elseif depth == 0 and t.value == ";" then
        return false
      end
    end
    return false
  end

  if before and before.value == "local" then
    return { name = lhs.value, kind = "local" }
  end

  if before then
    if before.value == "{" or before.value == "," then
      if in_table_field() then
        return { name = lhs.value, kind = "table_field" }
      end
      return nil
    end
    if before.value == "." or before.value == "[" then
      return nil
    end
    local keyword_boundary = before.kind == "name" and (before.value == "then" or before.value == "do" or before.value == "else" or before.value == "repeat")
    if not keyword_boundary and not separated_by_statement_boundary(source, before.finish, lhs.start) then
      return nil
    end
  end

  return { name = lhs.value, kind = "assignment" }
end

local function is_expression_context(source, start_i)
  local c = previous_significant(source, start_i)
  if not c then return false end
  if c == "=" or c == "(" or c == "{" or c == "[" or c == "," or c == ":" then return true end
  local w = previous_word(source, start_i)
  if w == "return" or w == "then" or w == "do" then return true end
  return false
end

local function make_ctx(chunkname, source, start_tok, entry_tok)
  local ctx = {
    chunkname = chunkname,
    source = source,
    start_token = start_tok,
    entry_token = entry_tok,
    refs = {},
    ref_seen = {},
  }
  function ctx:add_ref(name)
    if valid_ident(name) and not self.ref_seen[name] then
      self.ref_seen[name] = true
      self.refs[#self.refs + 1] = name
    end
  end
  function ctx:origin(lex, start_t, end_t, channel)
    local o = lex:span(start_t or start_tok, end_t or lex.last or entry_tok)
    o.channel = channel
    return o
  end
  return ctx
end

local function descriptor_from(spec, entry, lex, ctx)
  if spec.parse_entry then
    return spec.parse_entry(lex, entry, ctx)
  end
  if entry == "expr" and spec.expression then return spec.expression(lex, ctx) end
  if (entry == "stmt" or entry == "quote") and spec.statement then return spec.statement(lex, ctx) end
  lex:error_at(ctx.entry_token, "syntax language `" .. tostring(spec.name) .. "` has no parser for `" .. tostring(entry) .. "`")
end

local function find_import_spec(modname, mod)
  if type(mod) == "table" then
    if mod.language_spec then return mod.language_spec end
    if mod.language_name then return registry.language(mod.language_name) end
    if mod.name then return registry.language(mod.name) end
  end
  local base = modname:match("([^%.]+)%.syntax$")
  if base then return registry.language(base) end
  return nil
end

function Driver.compile(source, chunkname, opts)
  opts = opts or {}
  chunkname = chunkname or "=(llbl syntax chunk)"
  local lex = Lexer.new(source, chunkname, opts)
  local constructors = {}
  local pieces = { "local __llbl_syntax = require(\"llbl.syntax\")\n" }
  local active_direct = {}

  local function activate(spec)
    if not spec then return end
    for _, e in ipairs(spec.direct_entrypoints or spec.entrypoints or {}) do
      active_direct[e] = spec
    end
  end

  for _, lang in ipairs(opts.active_languages or {}) do
    activate(registry.language(lang) or registry.namespace(lang))
  end

  local cursor = 1
  local chunk_id = opts.chunk_id or (chunkname .. "#" .. tostring({}):gsub("table: ", ""))

  while not lex:at_eof() do
    local t = lex:peek()

    -- Parse-time syntax import for the mixed-source driver.  .lln value chunks
    -- disable this path and use Lua require for modules.
    if t.kind == "name" and t.value == "import" and lex:peek(1).kind == "string" then
      local import_tok = lex:next()
      local module_tok = lex:next()
      if opts.allow_import == false then
        lex:error_at(import_tok, "`import` is not part of .lln value chunks; use Lua `require(...)` for modules")
      end
      local modname = unquote_lua_string(module_tok.raw)
      local ok, mod = pcall(require, modname)
      if not ok then lex:error_at(module_tok, "failed to import syntax module `" .. modname .. "`: " .. tostring(mod)) end
      activate(find_import_spec(modname, mod))
      pieces[#pieces + 1] = source:sub(cursor, import_tok.start - 1)
      pieces[#pieces + 1] = "require(" .. q(modname) .. ")"
      cursor = module_tok.finish + 1

    else
      local spec, entry, namespaced
      if t.kind == "name" then
        local t2 = lex:peek(1)
        spec, entry = registry.resolve_namespaced(t.value, t2 and t2.value)
        if spec then
          namespaced = true
        elseif active_direct[t.value] then
          spec, entry = active_direct[t.value], t.value
        elseif opts.direct_entrypoints then
          spec, entry = registry.resolve_direct(t.value)
        end
      end

      if spec then
        local island_start = t
        local lua_binding = infer_lua_binding(lex, source)
        local entry_tok
        if namespaced then
          lex:next() -- namespace token
          entry_tok = lex:next() -- entry token
        else
          entry_tok = lex:next()
        end

        pieces[#pieces + 1] = source:sub(cursor, island_start.start - 1)
        local ctx = make_ctx(chunkname, source, island_start, entry_tok)
        ctx.lua_binding = lua_binding
        local desc = descriptor_from(spec, entry, lex, ctx)
        desc.refs = unique_refs(desc.refs or ctx.refs)
        desc.owner = desc.owner or spec.owner or spec.name
        desc.entry = desc.entry or entry
        desc.lua_binding = desc.lua_binding or ctx.lua_binding
        desc.origin = desc.origin or ctx:origin(lex, island_start, lex.last, "parsed:" .. tostring(entry))

        local ctor = Constructor.new(desc)
        constructors[#constructors + 1] = ctor
        local id = #constructors
        local invoke = string.format("__llbl_syntax.invoke(%s,%d,%s)", q(chunk_id), id, Constructor.env_source(ctor.refs))

        local output = ctor.outputs and ctor.outputs[1]
        local in_expr = is_expression_context(source, island_start.start)
        if output and output.name and valid_ident(output.name) and not in_expr then
          if output.local_decl then
            pieces[#pieces + 1] = "local " .. output.name .. " = " .. invoke
          else
            pieces[#pieces + 1] = output.name .. " = " .. invoke
          end
        else
          pieces[#pieces + 1] = invoke
        end

        local last = lex.last or island_start
        cursor = last.finish + 1
      else
        lex:next()
      end
    end
  end

  pieces[#pieces + 1] = source:sub(cursor)
  local lua_source = table.concat(pieces)
  return {
    lua = lua_source,
    constructors = constructors,
    chunk_id = chunk_id,
    chunkname = chunkname,
  }
end

function Driver.loadstring(source, chunkname, opts)
  local compiled = Driver.compile(source, chunkname, opts)
  Constructor.install_chunk(compiled.chunk_id, compiled.constructors)
  local loader = loadstring or load
  local chunk, err = loader(compiled.lua, chunkname or compiled.chunkname)
  if not chunk then return nil, err, compiled end
  if opts and opts.env and setfenv then setfenv(chunk, opts.env) end
  return chunk, compiled
end

function Driver.loadfile(path, opts)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local src = f:read("*a")
  f:close()
  return Driver.loadstring(src, "@" .. path, opts)
end

function Driver.dofile(path, opts)
  local chunk, compiled_or_err = Driver.loadfile(path, opts)
  if not chunk then error(compiled_or_err, 0) end
  return chunk()
end

return Driver
