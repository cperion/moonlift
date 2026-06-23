package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local g = llb.grammar

local A = llb.define "FamilyA" {
  -- Creates the A family head.
  g.head. a {
    emit = function() return "a" end,
  },
}

local B = llb.define "FamilyB" {
  g.head. b {
    emit = function() return "b" end,
  },
}

assert(A:family():describe().tag == "Family", "language has singleton family")
assert(#llb.core_family():describe().members == 1, "llb is the smallest singleton family")
assert(llb.core_family():describe().members[1].name == "llb", "llb singleton contains the llb member")
assert(#A:family():describe().members == 2, "language family includes llb plus the language")

local env = A:env()
assert(env.a ~= nil, "language env delegates through singleton family")
assert(env.llb == llb and env.N == llb.N, "language family installs shared llb substrate")
assert(llb.is(env.unknown_name, "Symbol"), "singleton family auto-names are generic symbols")

local a_head = A:describe_head("a")
assert(a_head.documentation == "Creates the A family head.", "head introspection captures leading Lua comments")

llb.source.register("llb_diag_context.lua", "-- Explains the failing value.\nfailing_value()\n")
local diag_origin = { __llb_tag = "Origin", source = "llb_diag_context.lua", file = "llb_diag_context.lua", line = 2 }
diag_origin.leading_comment = llb.source.leading_comment(diag_origin)
local rendered_diag = llb.diagnostic { message = "bad value", primary = diag_origin }:render()
assert(rendered_diag:match("context: Explains the failing value%."), "diagnostic rendering includes leading comment context")

local parent_origin = { __llb_tag = "Origin", source = "llb_diag_context.lua", file = "llb_diag_context.lua", line = 1, leading_comment = "Outer generated context." }
local child_origin = { __llb_tag = "Origin", source = "llb_diag_context.lua", file = "llb_diag_context.lua", line = 2, leading_comment = "Inner generated context.", parent = parent_origin }
local stacked_diag = llb.diagnostic { message = "nested bad value", primary = child_origin }:render()
assert(stacked_diag:match("Outer generated context%."), "diagnostic rendering includes parent origin context")
assert(stacked_diag:match("Inner generated context%."), "diagnostic rendering includes child origin context")

local direct = llb.use(A, { scope = "env" })
assert(direct.family == A:family(), "llb.use(Language) delegates to the language family")
assert(direct.env.llb == llb and direct.env.a ~= nil, "direct language use still installs the family substrate")

local AB = (A:family() .. B:family()).prefer {
  name = "FamilyA",
  type = "FamilyA",
  expr = "FamilyA",
  string = "FamilyA",
  number = "FamilyA",
  boolean = "FamilyA",
  value = "FamilyA",
  identity = "FamilyA",
}

local ab_env = AB.env { scope = "env" }
assert(ab_env.a ~= nil and ab_env.b ~= nil, "family composition merges language exports")

local AOnly = AB - "FamilyB"
local a_env = AOnly.env { scope = "env" }
assert(rawget(a_env, "a") ~= nil and rawget(a_env, "b") == nil, "family subtraction removes member exports")
assert(rawget(a_env, "llb") == llb, "family subtraction preserves llb substrate")

local BOnly = AB.only { "FamilyB" }
local b_env = BOnly.env { scope = "env" }
assert(rawget(b_env, "a") == nil and rawget(b_env, "b") ~= nil, "family projection keeps selected member")
assert(rawget(b_env, "llb") == llb, "family projection preserves llb substrate")

local md = AB.markdown { title = "AB Reference" }
assert(md:match("# AB Reference"), "family markdown uses requested title")
assert(md:match("## LLB Syntax Model"), "family markdown includes shared syntax primer")
assert(md:match("head%. name"), "family markdown explains dot-head syntax")
assert(md:match("## Members"), "family markdown includes member table")
assert(md:match("FamilyA"), "family markdown includes first language")
assert(md:match("FamilyB"), "family markdown includes second language")
assert(md:match("### Heads"), "family markdown includes generic language heads")
assert(md:match("Creates the A family head%."), "family markdown includes captured Lua comments")
assert(md:match("a%s*```"), "family markdown emits syntax-shaped head forms")
assert(md:match("member%. FamilyA"), "family markdown emits syntax-shaped member forms")
assert(not md:match("|%-%-%-"), "family markdown avoids markdown tables")

io.write("llb family_algebra ok\n")
