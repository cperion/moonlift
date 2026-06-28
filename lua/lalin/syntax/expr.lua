-- lalin.syntax.expr

local Pratt = require("llbl.syntax.pratt")
local Ast = require("lalin.syntax.ast")
local Type = require("lalin.syntax.type")

local Expr = {}

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

local parser

local function binop(name)
  return function(op, left, right, ctx)
    return Ast.node("BinOp", { op = name or op.value, left = left, right = right }, Ast.origin(ctx.lex, op, ctx.lex.last, "parsed:binop"))
  end
end

local function cmpop(name)
  return function(op, left, right, ctx)
    return Ast.node("Cmp", { op = name or op.value, left = left, right = right }, Ast.origin(ctx.lex, op, ctx.lex.last, "parsed:cmp"))
  end
end

local function unop(name)
  return function(op, rhs, ctx)
    return Ast.node("UnOp", { op = name or op.value, value = rhs }, Ast.origin(ctx.lex, op, ctx.lex.last, "parsed:unop"))
  end
end

local function parse_expr_list(lex, ctx, close)
  local items = {}
  if lex:next_if(close) then return items end
  repeat
    items[#items + 1] = Expr.parse(lex, ctx)
  until not lex:next_if(",")
  lex:expect(close)
  return items
end

local function parse_record(lex, ctx)
  local start = lex:expect("{")
  local fields = {}
  if not lex:next_if("}") then
    repeat
      local key
      local mark = lex:mark()
      if lex:peek().kind == "name" and lex:peek(1).value == "=" then
        key = lex:next().value
        lex:expect("=")
      else
        lex:restore(mark)
      end
      fields[#fields + 1] = { key = key, value = Expr.parse(lex, ctx) }
    until not lex:next_if(",")
    lex:expect("}")
  end
  return Ast.node("Record", { fields = fields }, Ast.origin(lex, start, lex.last, "parsed:record"))
end

local function atom(lex, ctx)
  ctx.lex = lex
  local t = lex:peek()
  if t.kind == "number" then
    lex:next()
    return Ast.node("Literal", { kind = "number", source = t.raw, value = tonumber(t.raw) }, Ast.origin(lex, t, t, "parsed:literal"))
  elseif t.kind == "string" then
    lex:next()
    return Ast.node("Literal", { kind = "string", source = t.raw }, Ast.origin(lex, t, t, "parsed:literal"))
  elseif t.kind == "name" then
    lex:next()
    if t.value == "true" or t.value == "false" then
      return Ast.node("Literal", { kind = "boolean", value = (t.value == "true") }, Ast.origin(lex, t, t, "parsed:literal"))
    elseif t.value == "nil" then
      return Ast.node("Literal", { kind = "nil" }, Ast.origin(lex, t, t, "parsed:literal"))
    elseif t.value == "as" then
      -- as [type] (expr)  — type conversion
      local ty_node = Type.parse(lex, ctx)
      lex:expect("(")
      local value = Expr.parse(lex, ctx)
      lex:expect(")")
      return Ast.node("Cast", { ty = ty_node, value = value, cast = "surface" }, Ast.origin(lex, t, lex.last, "parsed:cast"))
    elseif t.value == "sizeof" then
      -- sizeof [type]  — type size query
      local ty_node = Type.parse(lex, ctx)
      return Ast.node("SizeOf", { ty = ty_node }, Ast.origin(lex, t, lex.last, "parsed:sizeof"))
    elseif t.value == "_" then
      -- LLBL-owned sentinel.  Lookahead decides form:
      -- _(expr)  → spread
      -- _        → hole
      if lex:peek().value == "(" then
        lex:next() -- consume (
        local fragment = Expr.parse(lex, ctx)
        lex:expect(")")
        return Ast.node("Spread", { fragment = fragment }, Ast.origin(lex, t, lex.last, "parsed:spread"))
      end
      return Ast.node("Hole", {}, Ast.origin(lex, t, t, "parsed:hole"))
    end
    return Ast.node("Name", { name = t.value }, Ast.origin(lex, t, t, "parsed:name"))
  elseif t.value == "(" then
    local start = lex:next()
    local e = Expr.parse(lex, ctx)
    lex:expect(")")
    return Ast.node("Paren", { value = e }, Ast.origin(lex, start, lex.last, "parsed:expr"))
  elseif t.value == "[" then
    local raw, open, close = lex:consume_balanced_from_open("[", "]")
    for _, r in ipairs(extract_refs(raw)) do if ctx.add_ref then ctx:add_ref(r) end end
    return Ast.node("HostEscape", { source = raw, refs = extract_refs(raw) }, Ast.origin(lex, open, close, "parsed:escape"))
  elseif t.value == "{" then
    return parse_record(lex, ctx)
  else
    lex:error_at(t, "expected expression atom, got `" .. tostring(t.value) .. "`")
  end
end

parser = Pratt.new {
  atom = atom,
  prefix = {
    ["-"] = { bp = 80, emit = unop("neg") },
    ["not"] = { bp = 80, emit = unop("not") },
    ["#"] = { bp = 80, emit = unop("len") },
    ["&"] = { bp = 80, emit = unop("addr") },
    ["*"] = { bp = 80, emit = unop("deref") },
  },
  postfix = {
    ["("] = { bp = 100, emit = function(op, left, lex, ctx)
      local args = parse_expr_list(lex, ctx, ")")
      return Ast.node("Call", { callee = left, args = args }, Ast.origin(lex, op, lex.last, "parsed:call"))
    end },
    ["["] = { bp = 100, emit = function(op, left, lex, ctx)
      local index = Expr.parse(lex, ctx)
      lex:expect("]")
      return Ast.node("Index", { base = left, index = index }, Ast.origin(lex, op, lex.last, "parsed:index"))
    end },
    ["."] = { bp = 100, emit = function(op, left, lex, ctx)
      local name = lex:expect_name("field name")
      return Ast.node("Field", { base = left, name = name.value }, Ast.origin(lex, op, name, "parsed:field"))
    end },
  },
  infix = {
    ["or"]  = { bp = 10, emit = binop("or") },
    ["and"] = { bp = 20, emit = binop("and") },
    ["=="] = { bp = 30, emit = cmpop("eq") },
    ["~="] = { bp = 30, emit = cmpop("ne") },
    ["<"]  = { bp = 30, emit = cmpop("lt") },
    ["<="] = { bp = 30, emit = cmpop("le") },
    [">"]  = { bp = 30, emit = cmpop("gt") },
    [">="] = { bp = 30, emit = cmpop("ge") },
    ["|"] = { bp = 35, emit = binop("bor") },
    ["~"] = { bp = 36, emit = binop("bxor") },
    ["&"] = { bp = 37, emit = binop("band") },
    ["<<"] = { bp = 40, emit = binop("shl") },
    [">>"] = { bp = 40, emit = binop("shr") },
    ["+"] = { bp = 50, emit = binop("add") },
    ["-"] = { bp = 50, emit = binop("sub") },
    ["*"] = { bp = 60, emit = binop("mul") },
    ["/"] = { bp = 60, emit = binop("div") },
    ["//"] = { bp = 60, emit = binop("idiv") },
    ["%"] = { bp = 60, emit = binop("mod") },
    ["^"] = { bp = 90, right_assoc = true, emit = binop("pow") },
  }
}

function Expr.parse(lex, ctx, min_bp)
  ctx = ctx or {}
  ctx.lex = lex
  return parser:parse(lex, ctx, min_bp or 0)
end

function Expr.parse_list(lex, ctx, close)
  return parse_expr_list(lex, ctx, close)
end

return Expr
