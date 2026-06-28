-- lalin.syntax.stmt

local Ast = require("lalin.syntax.ast")
local Expr = require("lalin.syntax.expr")
local Type = require("lalin.syntax.type")

local Stmt = {}

local function stop_set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

local function parse_expr_list_until_no_comma(lex, ctx)
  local items = {}
  items[#items + 1] = Expr.parse(lex, ctx)
  while lex:next_if(",") do
    items[#items + 1] = Expr.parse(lex, ctx)
  end
  return items
end

local function parse_named_payload(lex, ctx)
  local fields = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      local mark = lex:mark()
      local key
      if lex:peek().kind == "name" and lex:peek(1).value == "=" then
        key = lex:next().value
        lex:expect("=")
      else
        lex:restore(mark)
      end
      fields[#fields + 1] = { key = key, value = Expr.parse(lex, ctx) }
    until not lex:next_if(",")
    lex:expect(")")
  end
  return fields
end

local function synthetic_record(fields, origin)
  return Ast.node("Record", { fields = fields }, origin)
end

local function positional(value)
  return { value = value }
end

local function keyed(key, value)
  return { key = key, value = value }
end

local function number_lit(value)
  return Ast.node("Literal", { kind = "number", value = value, source = tostring(value) }, nil)
end

local function string_lit(value)
  local raw = string.format("%q", tostring(value))
  return Ast.node("Literal", { kind = "string", source = raw }, nil)
end

local function parse_range_domain(lex, ctx)
  local start = Expr.parse(lex, ctx)
  lex:expect("..")
  local stop = Expr.parse(lex, ctx)
  local step = nil
  if lex:next_if("..") then
    step = Expr.parse(lex, ctx)
  end
  local fields = { positional(start), positional(stop) }
  if step ~= nil then fields[#fields + 1] = positional(step) end
  return synthetic_record(fields, nil)
end

local function parse_range_domain_list(lex, ctx)
  local items = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      items[#items + 1] = positional(parse_range_domain(lex, ctx))
    until not lex:next_if(",")
    lex:expect(")")
  end
  return synthetic_record(items, nil)
end

local function parse_boundary_value(lex)
  if lex:peek().kind == "string" then
    return Expr.parse(lex, {})
  end
  return string_lit(lex:expect_name("window boundary").value)
end

local function parse_window_domain(lex, ctx)
  local axes = {}
  local before = number_lit(0)
  local after = number_lit(0)
  local boundary = string_lit("reject")
  lex:expect("(")
  axes[#axes + 1] = positional(parse_range_domain(lex, ctx))
  while lex:next_if(",") do
    local key = lex:expect_name("window option").value
    lex:expect("=")
    if key == "before" then
      before = Expr.parse(lex, ctx)
    elseif key == "after" then
      after = Expr.parse(lex, ctx)
    elseif key == "boundary" then
      boundary = parse_boundary_value(lex)
    else
      lex:error_at(lex.last, "unknown window option `" .. tostring(key) .. "`")
    end
  end
  lex:expect(")")
  local window = synthetic_record({ positional(before), positional(after), keyed("boundary", boundary) }, nil)
  return synthetic_record({
    keyed("axes", synthetic_record(axes, nil)),
    keyed("windows", synthetic_record({ positional(window) }, nil)),
  }, nil)
end

local function parse_loop_domain(lex, ctx)
  if lex:next_if("tiled") then
    lex:expect("grid")
    local axes = parse_range_domain_list(lex, ctx)
    lex:expect("by")
    local tiles = {}
    repeat
      tiles[#tiles + 1] = Expr.parse(lex, ctx)
    until not lex:next_if(",")
    return "tiled_nd", { synthetic_record({
      keyed("axes", axes),
      keyed("tiles", synthetic_record((function()
        local out = {}
        for i, tile in ipairs(tiles) do out[i] = positional(tile) end
        return out
      end)(), nil)),
    }, nil) }
  elseif lex:next_if("grid") then
    return "range_nd", { synthetic_record({ keyed("axes", parse_range_domain_list(lex, ctx)) }, nil) }
  elseif lex:next_if("window") then
    return "window_nd", { parse_window_domain(lex, ctx) }
  end
  return "range", { parse_range_domain(lex, ctx) }
end

function Stmt.parse_block(lex, ctx, stops)
  stops = stop_set(stops or { "end" })
  local items = {}
  lex:skip_separators()
  while not lex:at_eof() and not stops[lex:peek().value] do
    items[#items + 1] = Stmt.parse(lex, ctx)
    lex:skip_separators()
  end
  return items
end

function Stmt.parse(lex, ctx)
  ctx.lex = lex
  local t = lex:peek()

  if t.value == "requires" then
    local start = lex:next()
    local exprs = parse_expr_list_until_no_comma(lex, ctx)
    return Ast.node("StmtRequires", { exprs = exprs }, Ast.origin(lex, start, lex.last, "parsed:requires"))

  elseif t.value == "return" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    return Ast.node("StmtReturn", { values = values }, Ast.origin(lex, start, lex.last or start, "parsed:return"))

  elseif t.value == "if" then
    local start = lex:next()
    local cond = Expr.parse(lex, ctx)
    lex:expect("then")
    local then_body = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" })
    local elseif_blocks = {}
    while lex:next_if("elseif") do
      local etok = lex.last
      local ec = Expr.parse(lex, ctx)
      lex:expect("then")
      elseif_blocks[#elseif_blocks + 1] = Ast.node("ElseIf", {
        cond = ec,
        body = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" }),
      }, Ast.origin(lex, etok, lex.last, "parsed:elseif"))
    end
    local else_body = nil
    if lex:next_if("else") then
      else_body = Stmt.parse_block(lex, ctx, { "end" })
    end
    lex:expect("end")
    return Ast.node("StmtIf", { cond = cond, then_body = then_body, elseif_blocks = elseif_blocks, else_body = else_body }, Ast.origin(lex, start, lex.last, "parsed:if"))

  elseif t.value == "for" then
    lex:error_at(t, "source loops use `loop`, not `for`")

  elseif t.value == "loop" then
    local start = lex:next()
    local indexes = { lex:expect_name("loop index").value }
    while lex:next_if(",") do
      indexes[#indexes + 1] = lex:expect_name("loop index").value
    end
    local index = indexes[1]
    lex:expect("in")
    local producer, args = parse_loop_domain(lex, ctx)
    lex:expect("do")
    local body = Stmt.parse_block(lex, ctx, { "end" })
    lex:expect("end")
    return Ast.node("StmtForRange", { index = index, indexes = indexes, producer = producer, args = args, result_type = nil, body = body }, Ast.origin(lex, start, lex.last, "parsed:loop"))

  elseif t.value == "fold" then
    local start = lex:next()
    local name = lex:expect_name("fold accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local by = lex:expect_name("fold reducer").value
    lex:expect("step")
    local step = Expr.parse(lex, ctx)
    return Ast.node("StmtFold", { name = name, type = ty, init = init, by = by, step = step }, Ast.origin(lex, start, lex.last, "parsed:fold"))

  elseif t.value == "scan" then
    local start = lex:next()
    local name = lex:expect_name("scan accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local by = lex:expect_name("scan reducer").value
    local axis = nil
    if lex:next_if("axis") then
      lex:error_at(lex.last, "scan axis uses `over`, not `axis`")
    end
    if lex:next_if("over") then
      if lex:peek().kind == "name" then
        axis = lex:next().value
      else
        axis = Expr.parse(lex, ctx)
      end
    end
    lex:expect("step")
    local step = Expr.parse(lex, ctx)
    lex:expect("into")
    local into = Expr.parse(lex, ctx)
    return Ast.node("StmtScan", { name = name, type = ty, init = init, by = by, axis = axis, step = step, into = into }, Ast.origin(lex, start, lex.last, "parsed:scan"))

  elseif t.value == "let" or t.value == "var" then
    local start = lex:next()
    local mutable = start.value == "var"
    local name = lex:expect_name("local name")
    local ty = Type.parse(lex, ctx)
    local init = nil
    if lex:next_if("=") then init = Expr.parse(lex, ctx) end
    return Ast.node(mutable and "StmtVar" or "StmtLet", { name = name.value, type = ty, init = init }, Ast.origin(lex, start, lex.last, "parsed:local"))

  elseif t.value == "jump" then
    local start = lex:next()
    local target = lex:expect_name("jump target").value
    local payload = {}
    if lex:peek().value == "(" then payload = parse_named_payload(lex, ctx) end
    return Ast.node("StmtJump", { target = target, payload = payload }, Ast.origin(lex, start, lex.last, "parsed:jump"))

  elseif t.value == "emit" then
    local start = lex:next()
    local callee = Expr.parse(lex, ctx)
    local handlers = nil
    if lex:peek().value == "{" then handlers = Expr.parse(lex, ctx) end
    return Ast.node("StmtEmit", { callee = callee, handlers = handlers }, Ast.origin(lex, start, lex.last, "parsed:emit"))

  else
    local start = lex:peek()
    local left = Expr.parse(lex, ctx)
    local op = lex:peek().value
    if op == "=" or op == "+=" or op == "-=" or op == "*=" or op == "/=" then
      local optok = lex:next()
      local value = Expr.parse(lex, ctx)
      return Ast.node("StmtAssign", { op = op, place = left, value = value }, Ast.origin(lex, start, lex.last, "parsed:assign"))
    end
    return Ast.node("StmtExpr", { expr = left }, Ast.origin(lex, start, lex.last or start, "parsed:stmt"))
  end
end

return Stmt
