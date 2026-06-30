-- lalin.syntax
-- Terra-like parsed-channel frontend for Lalin, registered as a generic LLBL
-- syntax language.  The parser returns first-class Lalin parsed AST values;
-- repository integration should lower these nodes to LalinTree ASDL or call the
-- existing DSL heads in one place.

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Ast = require("lalin.syntax.ast")
local Decl = require("lalin.syntax.decl")
local Expr = require("lalin.syntax.expr")
local Stmt = require("lalin.syntax.stmt")

local LalinSyntax = {}

local function wrap_ast(ast, ctx, opts)
  opts = opts or {}
  local refs = {}
  for _, r in ipairs(ctx.refs or {}) do refs[#refs + 1] = r end
  local outputs = {}
  if ast.name and (ast.tag == "DeclFunc" or ast.tag == "DeclStruct" or ast.tag == "DeclUnion" or ast.tag == "DeclRegion") then
    outputs[1] = { name = ast.name }
  end
  local lua_binding = ctx.lua_binding
  return Constructor.new {
    owner = "lalin",
    kind = ast.tag,
    role = opts.role or "decl",
    channel = opts.channel or "parsed:lalin",
    refs = refs,
    outputs = outputs,
    lua_binding = lua_binding,
    origin = ast.origin,
    ast = ast,
    build = function(env)
      -- Resolve explicit host escapes at construction/evaluation time.  This is
      -- the exact point where Lua lexical values become Lalin constants,
      -- fragments, types, or diagnostics in a full Lalin adapter.
      local copy = ast -- AST is intentionally shared; callsites normally build once.
      if copy.name == nil and copy.tag == "DeclFunc" and lua_binding and lua_binding.name then
        copy.name = lua_binding.name
        copy.public_name = copy.public_name or lua_binding.name
        copy.debug_name = copy.debug_name or lua_binding.name
      end
      Ast.resolve_host_escapes(copy, env)
      return copy
    end,
  }
end

function LalinSyntax.parse_entry(lex, entry, ctx)
  local ast
  if entry == "fn" then
    ast = Decl.parse_fn(lex, ctx, ctx.entry_token)
  elseif entry == "struct" then
    ast = Decl.parse_struct(lex, ctx, ctx.entry_token)
  elseif entry == "union" then
    ast = Decl.parse_union(lex, ctx, ctx.entry_token)
  elseif entry == "region" then
    ast = Decl.parse_region(lex, ctx, ctx.entry_token)
  elseif entry == "expr" then
    ast = Decl.parse_expr_fragment(lex, ctx)
  elseif entry == "stmt" or entry == "quote" then
    ast = Decl.parse_stmt_fragment(lex, ctx)
  elseif entry == "lalin" then
    lex:error_at(ctx.entry_token, "bare `lalin` entrypoint requires a following entry token")
  else
    lex:error_at(ctx.entry_token, "unsupported Lalin syntax entrypoint `" .. tostring(entry) .. "`")
  end
  return wrap_ast(ast, ctx, { role = ast.tag })
end

function LalinSyntax.parse_expression(lex, ctx)
  local ast = Expr.parse(lex, ctx)
  return wrap_ast(ast, ctx, { role = "expr", channel = "parsed:expr" })
end

function LalinSyntax.parse_statement(lex, ctx)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  local ast = Ast.node("StmtFragment", { body = body }, ctx:origin(lex, ctx.entry_token, lex.last, "parsed:stmt"))
  return wrap_ast(ast, ctx, { role = "stmt", channel = "parsed:stmt" })
end

function LalinSyntax.register()
  local spec = {
    name = "lalin",
    owner = "lalin",
    entrypoints = { "fn", "struct", "union", "region", "quote", "expr", "stmt" },
    direct_entrypoints = nil, -- callers choose whether to activate bare entrypoints.
    keywords = {
      "fn", "region", "struct", "union", "requires", "ensures",
      "do", "end", "if", "then", "elseif", "else", "loop", "in",
      "grid", "tiled", "window", "return", "jump", "emit", "entry", "block",
      "let", "var", "fold", "scan", "by", "over", "step", "into",
    },
    parse_entry = LalinSyntax.parse_entry,
    expression = LalinSyntax.parse_expression,
    statement = LalinSyntax.parse_statement,
  }
  LalinSyntax.language_spec = spec
  LalinSyntax.language_name = spec.name
  return llbl_syntax.register(spec)
end

-- ── Convert parsed AST to LalinTree for the compiler pipeline ──────────

function LalinSyntax.to_module(parsed_decls, name, T)
  -- Use the caller's schema context, or create one at this public boundary.
  local asdl = require("lalin.asdl")
  T = T or asdl.context()
  if not T.LalinTree then
    require("lalin.schema_projection")(T)
  end
  local to_tree = require("lalin.syntax.to_tree")(T)
  local TypeValue = require("lalin.syntax.type_value")(T)
  local Tr, C, B = T.LalinTree, T.LalinCore, T.LalinBind

  name = name or "parsed"
  local decls = {}
  local anon_id = 0

  local function sanitize_ident(s)
    s = tostring(s or ""):gsub("[^%w_]", "_")
    if s == "" then return nil end
    if s:match("^%d") then s = "_" .. s end
    return s
  end

  local function compiler_name(parsed)
    if parsed.name ~= nil and parsed.name ~= "" then return parsed.name end
    local public = sanitize_ident(parsed.public_name or parsed.debug_name)
    anon_id = anon_id + 1
    if public ~= nil then return "__lln_" .. public .. "_" .. tostring(anon_id) end
    return "__lln_fn_" .. tostring(anon_id)
  end

  -- Convert parsed type escapes (`[i32]`, `[ptr [i32]]`, `[some_lua_type]`)
  -- to LalinType.Type values in the active compiler context.
  local function parsed_type(ptype)
    if not ptype then return T.LalinType.TScalar(C.ScalarVoid) end
    local cls = asdl.classof(ptype)
    if cls then return ptype end
    if ptype.tag == "HostEscape" then
      if not ptype.resolved then error("parsed_to_module: unresolved type host escape", 2) end
      local value = ptype.value
      local projected = TypeValue.type(value)
      if projected ~= nil then return projected end
      if type(value) == "table" and value.tag then
        return parsed_type(value)
      end
      error("parsed_to_module: type host escape produced unsupported value " .. tostring(value), 2)
    end
    error("parsed_to_module: unsupported parsed type tag " .. tostring(ptype.tag) .. "; type positions use `[ ... ]`", 2)
  end

  -- Helper: convert a single parsed decl to a Tr.Item for the module.
  -- The tree ASDL uses Tr.ItemFunc(FuncLocal/FuncExport) for functions,
  -- Tr.ItemType(TypeDeclStruct/TypeDeclTaggedUnionSugar) for structs/unions.
  local function call_name(expr)
    if expr and expr.tag == "Name" then return expr.name end
    return nil
  end

  local function contract_from_expr(expr)
    if not expr or expr.tag ~= "Call" then
      error("parsed requires expects contract calls such as bounds(ptr)(n), readonly(ptr), or disjoint(a)(b)", 2)
    end
    local name = call_name(expr.callee)
    if name == "readonly" then
      if #(expr.args or {}) ~= 1 then error("readonly contract expects one argument", 2) end
      return Tr.ContractReadonly(to_tree.expr(expr.args[1]))
    elseif name == "writeonly" then
      if #(expr.args or {}) ~= 1 then error("writeonly contract expects one argument", 2) end
      return Tr.ContractWriteonly(to_tree.expr(expr.args[1]))
    elseif name == "noalias" then
      if #(expr.args or {}) ~= 1 then error("noalias contract expects one argument", 2) end
      return Tr.ContractNoAlias(to_tree.expr(expr.args[1]))
    elseif name == "invalidate" then
      if #(expr.args or {}) ~= 1 then error("invalidate contract expects one argument", 2) end
      return Tr.ContractInvalidate(to_tree.expr(expr.args[1]))
    elseif name == "preserve" then
      if #(expr.args or {}) ~= 1 then error("preserve contract expects one argument", 2) end
      return Tr.ContractPreserve(to_tree.expr(expr.args[1]))
    end

    local callee = expr.callee
    if callee and callee.tag == "Call" then
      local outer_args = expr.args or {}
      local inner_args = callee.args or {}
      local inner_name = call_name(callee.callee)
      if inner_name == "bounds" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("bounds contract expects bounds(base)(len)", 2) end
        return Tr.ContractBounds(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      elseif inner_name == "disjoint" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("disjoint contract expects disjoint(a)(b)", 2) end
        return Tr.ContractDisjoint(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      elseif inner_name == "same_len" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("same_len contract expects same_len(a)(b)", 2) end
        return Tr.ContractSameLen(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      end
    end

    error("parsed requires: unsupported contract expression", 2)
  end

  local function decl_to_item(parsed)
    if not parsed then return nil end
    if parsed.tag == "DeclFunc" then
      local fname = compiler_name(parsed)
      local params = {}
      for i, p in ipairs(parsed.params or {}) do
        params[i] = T.LalinType.Param(p.name, parsed_type(p.type))
      end
      local result_ty = parsed_type(parsed.result)
      local body_src, contracts = {}, {}
      for _, stmt in ipairs(parsed.body or {}) do
        if stmt.tag == "StmtRequires" then
          for _, expr in ipairs(stmt.exprs or {}) do
            contracts[#contracts + 1] = contract_from_expr(expr)
          end
        else
          body_src[#body_src + 1] = stmt
        end
      end
      local body = to_tree.stmts(body_src)
      if #body == 0 then
        body = { Tr.StmtReturnVoid(Tr.StmtSurface) }
      end
      local func_spec = #contracts > 0
        and Tr.FuncLocalContract(fname, params, result_ty, contracts, body)
        or Tr.FuncLocal(fname, params, result_ty, body)
      return Tr.ItemFunc(func_spec)
    elseif parsed.tag == "DeclStruct" then
      local fields = {}
      for i, f in ipairs(parsed.fields or {}) do
        fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
      end
      return Tr.ItemType(Tr.TypeDeclStruct(parsed.name, fields))
    elseif parsed.tag == "DeclUnion" then
      local variants = {}
      for _, v in ipairs(parsed.variants or {}) do
        local fields = {}
        for i, f in ipairs(v.fields or {}) do
          fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
        end
        variants[#variants + 1] = Tr.VariantDecl(v.name, fields)
      end
      return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(parsed.name, variants))
    end
    error("parsed_to_module: unsupported decl tag " .. tostring(parsed.tag), 2)
  end

  local function is_parsed_decl(value)
    return type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") ~= nil
  end

  local function collect_parsed_decls(value)
    if is_parsed_decl(value) then return { value } end
    if type(value) ~= "table" then return {} end
    local out = {}
    for i = 1, #value do
      if not is_parsed_decl(value[i]) then
        error("parsed_to_module: positional entries must be parsed declarations", 2)
      end
      out[#out + 1] = value[i]
    end
    for k, v in pairs(value) do
      if type(k) ~= "number" and is_parsed_decl(v) then
        if type(k) == "string" and v.name == nil then
          v.public_name = v.public_name or k
          v.debug_name = v.debug_name or k
          v.name = k
        end
        out[#out + 1] = v
      end
    end
    return out
  end

  for _, d in ipairs(collect_parsed_decls(parsed_decls)) do
    decls[#decls + 1] = decl_to_item(d)
  end

  return Tr.Module(Tr.ModuleSurface, decls)
end

-- Register on require.
LalinSyntax.register()

return LalinSyntax
