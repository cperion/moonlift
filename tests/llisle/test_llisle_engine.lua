package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local llb = require("llb")
local llisle = require("llisle")

local env = lalin.family.env { scope = "env", base = {} }
llisle.use { scope = "env", target = env, base = env, global = false }
local chunk = assert(loadstring([[
return llisle {
  relation. lower_expr {
    input { expr [ml.i32], ctx [LowerCtx] },
    output { value [BackValue] },
    effects { cmd [BackCmd] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  predicate. has_type [has_type_impl] { input { value [Any], ty [Any] }, pure },
  predicate. fits_imm32 [fits_imm32_impl] { input { value [Any] }, pure },

  constructor. add_i32_imm [add_i32_imm_impl],
  constructor. add_i32 [add_i32_impl],
  constructor. load_class [load_class_impl],
  constructor. map_class [map_class_impl],

  rule. add_i32 {
    llisle.lower_expr {
      expr = P. expr,
      ctx = P. ctx,
    },

    when {
      (P. expr.kind :eq (add))
        * (P. expr.lhs.ty :eq (ml.i32))
        * (P. expr.rhs.ty :eq (ml.i32)),
    },

    choose {
      alt. imm {
        when { (P. expr.rhs :fits_imm32 ()) + (P. expr.rhs :is_const ()) },
        cost (1),
        run {
          emit. cmd { add_i32_imm { dst = V. out, lhs = P. expr.lhs, imm = P. expr.rhs } },
          ret { value = V. out },
        },
      },

      alt. reg {
        cost (2),
        run {
          emit. cmd { add_i32 { dst = V. out, lhs = P. expr.lhs, rhs = P. expr.rhs } },
          ret { value = V. out },
        },
      },
    },
  },

  relation. classify_expr {
    input { expr [ExprFact] },
    output { class [ClassFact] },
    strategy { select. best_cost },
  },

  rule. classify_load {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (load) },
    run {
      ret { class = load_class { lane = P. expr.lane, index = P. expr.index } },
    },
  },

  rule. classify_unary_map {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (unary) },
    bind. inner {
      llisle.classify_expr { expr = P. expr.value },
    },
    when { V. inner.class.kind :eq (load_class) },
    run {
      ret {
        class = map_class {
          op = P. expr.op,
          lane = V. inner.class.lane,
          index = V. inner.class.index,
        },
      },
    },
  },
}
]], "llisle_engine.lua"))

local i32 = env.ml.i32
local S = {
  kind = llb.symbol("kind"),
  ty = llb.symbol("ty"),
  lhs = llb.symbol("lhs"),
  rhs = llb.symbol("rhs"),
  value = llb.symbol("value"),
  name = llb.symbol("name"),
}
local function rec(fields)
  local out = {}
  for k, v in pairs(fields) do out[S[k] or k] = v end
  return out
end
local function const_i32(v) return rec { kind = "const", ty = i32, value = v } end
local function value_i32(name) return rec { kind = "value", ty = i32, name = name } end
env.has_type_impl = function(value, ty) return type(value) == "table" and value[S.ty] == ty end
env.fits_imm32_impl = function(v)
  local kind, value = v[S.kind], v[S.value]
  return type(v) == "table" and kind == "const" and value >= -2147483648 and value <= 2147483647
end
env.add_i32_imm_impl = function(fields)
  return { op = "add_i32_imm", dst = fields.dst, lhs = fields.lhs, imm = fields.imm }
end
env.add_i32_impl = function(fields)
  return { op = "add_i32", dst = fields.dst, lhs = fields.lhs, rhs = fields.rhs }
end
env.load_class_impl = function(fields)
  fields.kind = "load_class"
  return fields
end
env.map_class_impl = function(fields)
  fields.kind = "map_class"
  return fields
end
setfenv(chunk, env)
local zone = chunk()

local engine = llisle.compile(zone, {
  fresh = function(name, id) return { kind = "tmp", name = name, id = id } end,
  symbols = S,
})

local imm_result = assert(engine:run("lower_expr", {
  expr = rec { kind = "add", ty = i32, lhs = value_i32("x"), rhs = const_i32(7) },
  ctx = {},
}))
assert(imm_result.rule == "add_i32", "engine records selected rule")
assert(imm_result.alt == "imm", "best-cost choose selects immediate alternative")
assert(imm_result.cost == 1, "immediate alternative carries cost")
assert(imm_result.output.value.name == "out", "ret record payload is preserved")
assert(#imm_result.effects == 1 and imm_result.effects[1].channel == "cmd", "emit records command effect")
assert(imm_result.effects[1].value.op == "add_i32_imm", "emit payload is built through host builder")
assert(imm_result.effects[1].value.dst == imm_result.output.value, "V binders are stable inside a rule")

local reg_result = assert(engine:run("lower_expr", {
  expr = rec { kind = "add", ty = i32, lhs = value_i32("x"), rhs = value_i32("y") },
  ctx = {},
}))
assert(reg_result.alt == "reg", "failed immediate guard falls back to register alternative")
assert(reg_result.cost == 2, "register alternative carries cost")
assert(reg_result.effects[1].value.op == "add_i32", "register alternative emits register command")

local miss, err = engine:run("lower_expr", {
  expr = rec { kind = "sub", ty = i32, lhs = value_i32("x"), rhs = value_i32("y") },
  ctx = {},
})
assert(miss == nil and err.code == "E_LLISLE_NO_MATCH", "engine reports no-match as structured failure")

local classified = assert(engine:run("classify_expr", {
  expr = rec {
    kind = "unary",
    op = "neg",
    value = rec { kind = "load", lane = "xs", index = "i" },
  },
}))
assert(classified.output.class.kind == "map_class", "bind before guard enables recursive Llisle classification")
assert(classified.output.class.lane == "xs" and classified.output.class.index == "i", "classifier preserves child output fields")

local formatted = lalin.family.format(zone, { width = 100 })
assert(formatted:match("ret%s*{") and formatted:match("value%s*="), "formatter preserves ret record payload")

io.write("llisle engine ok\n")
