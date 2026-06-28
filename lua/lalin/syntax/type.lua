-- lalin.syntax.type

local Ast = require("lalin.syntax.ast")

local Type = {}

local lua_keywords = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
  ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
  ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
  ["while"] = true,
}

local function extract_refs(src)
  local refs, seen = {}, {}
  for name in tostring(src):gmatch("[%a_][%w_]*") do
    if not lua_keywords[name] and not seen[name] then
      seen[name] = true
      refs[#refs + 1] = name
    end
  end
  return refs
end

function Type.parse(lex, ctx)
  local start = lex:peek()
  if start.value == "[" then
    local raw, open, close = lex:consume_balanced_from_open("[", "]")
    local refs = extract_refs(raw)
    for _, r in ipairs(refs) do if ctx and ctx.add_ref then ctx:add_ref(r) end end
    return Ast.node("HostEscape", { source = raw, refs = refs, kind = "type" }, Ast.origin(lex, open, close, "parsed:type_escape"))
  end
  lex:error_at(start, "type positions evaluate Lua type values with `[ ... ]`")
end

function Type.parse_field(lex, ctx)
  local t = lex:peek()
  local name, anonymous
  if t.kind == "name" and t.value == "_" then
    lex:next()
    name = "_"
    anonymous = true
  else
    local start = lex:expect_name("field name")
    name = start.value
    anonymous = false
  end
  local ty = Type.parse(lex, ctx)
  return Ast.node("Field", { name = name, type = ty, anonymous = anonymous }, Ast.origin(lex, t, lex.last, "parsed:field"))
end

function Type.parse_anonymous_field(lex, ctx)
  local start = lex:peek()
  return Ast.node("Field", { name = "", type = Type.parse(lex, ctx), anonymous = true }, Ast.origin(lex, start, lex.last, "parsed:field"))
end

function Type.parse_params(lex, ctx)
  local params = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      params[#params + 1] = Type.parse_field(lex, ctx)
    until not lex:next_if(",")
    lex:expect(")")
  end
  return params
end

function Type.parse_field_block(lex, ctx, stop_value)
  local fields = {}
  while not lex:at_eof() and lex:peek().value ~= (stop_value or "end") do
    fields[#fields + 1] = Type.parse_field(lex, ctx)
    lex:skip_separators()
  end
  return fields
end

return Type
