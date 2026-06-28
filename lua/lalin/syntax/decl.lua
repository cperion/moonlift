-- lalin.syntax.decl

local Ast = require("lalin.syntax.ast")
local Type = require("lalin.syntax.type")
local Stmt = require("lalin.syntax.stmt")
local Expr = require("lalin.syntax.expr")

local Decl = {}

local function optional_do(lex)
  lex:next_if("do")
end

function Decl.parse_fn(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = nil
  if lex:peek().kind == "name" and lex:peek(1).value == "(" then
    name = lex:next().value
  elseif lex:peek().value ~= "(" then
    lex:error_at(lex:peek(), "expected function name or parameter list")
  end
  local params = Type.parse_params(lex, ctx)
  local result = nil
  if lex:peek().value == "[" then result = Type.parse(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node("DeclFunc", {
    name = name,
    params = params,
    result = result,
    body = body,
  }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_struct(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("struct name")
  optional_do(lex)
  local fields = Type.parse_field_block(lex, ctx, "end")
  lex:expect("end")
  return Ast.node("DeclStruct", { name = name.value, fields = fields }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_union(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("union name")
  optional_do(lex)
  local variants = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    local vstart = lex:expect_name("variant name")
    local fields = {}
    if lex:peek().value == "(" then fields = Type.parse_params(lex, ctx) end
    variants[#variants + 1] = Ast.node("Variant", { name = vstart.value, fields = fields }, Ast.origin(lex, vstart, lex.last or vstart, "parsed:variant"))
    lex:skip_separators()
  end
  lex:expect("end")
  return Ast.node("DeclUnion", { name = name.value, variants = variants }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

local function parse_entry_block(lex, ctx)
  local start = lex:next() -- entry or block
  local kind = start.value
  local name = lex:expect_name(kind .. " name")
  local state = {}
  if lex:peek().value == "(" then state = Type.parse_params(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node(kind == "entry" and "RegionEntry" or "RegionBlock", {
    name = name.value,
    state = state,
    body = body,
  }, Ast.origin(lex, start, lex.last, "parsed:region_block"))
end

-- Parse a continuation exit entry:  name(fields)
-- The payload tuple may contain named fields (result [i32]) or bare types ([i32]).
local function parse_one_exit(lex, ctx)
  local name = lex:expect_name("continuation name")
  local fields = {}
  if lex:peek().value == "(" then
    lex:next() -- (
    if not lex:next_if(")") then
      repeat
        local t = lex:peek()
        local t1 = lex:peek(1)
        if t.kind == "name" and t1 and t1.value == "[" then
          fields[#fields + 1] = Type.parse_field(lex, ctx)
        elseif t.value == "[" then
          fields[#fields + 1] = Type.parse_anonymous_field(lex, ctx)
        else
          lex:error_at(t, "expected continuation field `name [type]` or anonymous `[type]`")
        end
      until not lex:next_if(",")
      lex:expect(")")
    end
  end
  return Ast.node("Exit", { name = name.value, fields = fields },
    Ast.origin(lex, name, lex.last or name, "parsed:exit"))
end

function Decl.parse_region(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("region name")

  -- Parse signature: (data_params ; continuation_params)
  -- Data params before `;` form the input product.
  -- Continuation params after `;` form the exit sum.
  -- If no `;`, everything is data params (no continuations).
  local inputs, exits
  lex:expect("(")
  inputs = {}
  exits = {}

  if lex:peek().value == ";" then
    -- No data params, only continuations
    lex:next() -- ;
    if not lex:next_if(")") then
      repeat
        exits[#exits + 1] = parse_one_exit(lex, ctx)
      until not lex:next_if(",")
      lex:expect(")")
    end
  elseif lex:peek().value == ")" then
    -- Empty signature
    lex:next()
  else
    -- Parse data params (product), then optionally ; + continuations
    repeat
      inputs[#inputs + 1] = Type.parse_field(lex, ctx)
    until not lex:next_if(",") or lex:peek().value == ";"
    if lex:next_if(";") then
      if not lex:next_if(")") then
        repeat
          exits[#exits + 1] = parse_one_exit(lex, ctx)
        until not lex:next_if(",")
        lex:expect(")")
      end
    else
      lex:expect(")")
    end
  end

  local blocks = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    if lex:peek().value ~= "entry" and lex:peek().value ~= "block" then
      lex:error_at(lex:peek(), "expected region entry/block or end")
    end
    blocks[#blocks + 1] = parse_entry_block(lex, ctx)
  end
  lex:expect("end")
  return Ast.node("DeclRegion", { name = name.value, inputs = inputs, exits = exits, blocks = blocks }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_expr_fragment(lex, ctx)
  local start = ctx.entry_token
  local expr = Expr.parse(lex, ctx)
  lex:expect("end")
  return Ast.node("ExprFragment", { expr = expr }, Ast.origin(lex, start, lex.last, "parsed:expr"))
end

function Decl.parse_stmt_fragment(lex, ctx)
  local start = ctx.entry_token
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node("StmtFragment", { body = body }, Ast.origin(lex, start, lex.last, "parsed:stmt"))
end

return Decl
