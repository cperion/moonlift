package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ll = require("llpvm")
local moon = require("moonlift")

assert(ll.T and ll.B, "llpvm exposes ASDL context and FastBuilders")
assert(ll.vm == nil, "legacy mutation VM API is not public")
assert(ll.node == nil, "global erased node type is not public")
assert(ll.i64 == nil and ll.u32 == nil and ll.struct == nil and ll.ptr == nil, "llpvm does not expose a parallel type API")

local ok_dep, dep_err = pcall(function()
    local env = {}
    ll.use { scope = "env", target = env }
end)
assert(not ok_dep and tostring(dep_err):match("moonlift%.types"), "llpvm.use reports missing moonlift.types scope")

local env = {}
local moon_session = moon.use { scope = "env", target = env, global = false, searcher = false }
local ll_session = ll.use { scope = "env", target = env, global = false }
assert(ll_session:describe().provides[1] == "llpvm.dsl", "llpvm session reports provided capability")
assert(moon_session:describe().provides[1] == "moonlift.types", "moonlift session reports type capability")

local src = [[
return language. Demo {
  type. Node {
    op. Int { value [i64] },
    op. Add { left [Node], right [Node] },
  },

  lang. Back {
    type. Value {
      op. ConstI64 { value [i64] },
      op. AddI64 {},
    },
  },

  world. raw,
  world. lowered [Back],

  phase. lower_expr {
    from. raw,
    to. lowered,
    entry. ll_lower_expr,
    cache. full,
  },
} {
  raw. input {
    Int. one { value = 1 },
    Int. two { value = 2 },
    Add. sum { left = one, right = two },
  },

  root {
    input,
    sum,
    lower_expr (input),
  },
}
]]

local spec = ll.load(src, "llpvm-lua-api")
assert(getmetatable(spec) == ll.ProgramSpec, "load returns an LLPVM ProgramSpec")
assert(getmetatable(spec.language) == ll.MachineLanguage, "ProgramSpec keeps its machine language")

local program = spec:lower()
assert(getmetatable(program) == ll.ProgramImage, "ProgramSpec lowers to ProgramImage")
assert(#program.root_ids == 3, "root captures stream, value, and phase-map stream")
assert(#program.root_ops == 3, "first root records authored values for hot native imports")

local lowering = program.lowering
assert(lowering.languages.Demo, "primary language declared")
assert(lowering.languages.Back, "secondary language declared")
assert(lowering.worlds.raw and lowering.worlds.lowered, "worlds declared")
assert(lowering.phases.lower_expr, "phase declared")
assert(lowering.values.one.kind == "Int", "named value preserves constructor kind")
assert(lowering.values.sum.qualified_kind == "Node.Add", "constructor path lowers to op kind")

local bytes = program:bytecode()
assert(bytes:sub(1, 4) == "LLPV", "bytecode image has LLPV magic")
assert(bytes == ll.bytecode(spec), "facade bytecode helper accepts ProgramSpec")
assert(bytes == ll.bytecode(program), "facade bytecode helper accepts ProgramImage")

local desc = ll.describe(spec.language)
assert(desc and desc.tag == "LLPVMMachineLanguage" and desc.name == "Demo", "machine language describes itself")
local head = ll.describe_head("stream")
assert(head and head.slots[2].channels[1] == "index:value", "internal stream world slot is explicit index:value")
local role = ll.describe_role("fields")
assert(role and role.has_normalize, "field role owns normalization")

local ok_missing = pcall(function()
    return ll.load([[return language. Bad {
      type. Node { op. Add { left [Node], right [Node] }, },
      world. raw,
    } {
      raw. input { Add. bad { left = missing }, },
      root { input },
    }]], "missing") :bytecode()
end)
assert(not ok_missing, "constructor payload validation rejects missing fields")

local ok_wrong_world = pcall(function()
    return ll.load([[return language. BadWorld {
      type. Node { op. Int { value [i64] }, },
      lang. B { type. Node { op. Use { other [BadWorld.Node] }, }, },
      world. a,
      world. b [B],
    } {
      a. sa { Int. one { value = 1 }, },
      b. sb { Use. bad { other = one }, },
      root { sb },
    }]], "wrong-world") :bytecode()
end)
assert(not ok_wrong_world, "constructor payload validation rejects values from another world")

local direct = ll.B.LlPvm.Symbol { value = "direct-literal" }
assert(direct ~= nil, "ASDL layer remains available for tools")

print("llpvm lua dsl api ok")

local spec = ll.load(src, "llpvm-lua-api")
assert(getmetatable(spec) == ll.ProgramSpec, "load returns an LLPVM ProgramSpec")

local program = spec:lower()
assert(getmetatable(program) == ll.ProgramImage, "ProgramSpec lowers to ProgramImage")
assert(#program.root_ids == 2, "root captures explicit stream and phase-map stream")
assert(#program.root_ops == 3, "first root records authored values for hot native imports")

local lowering = program.lowering
assert(lowering.languages.Expr, "language Expr declared")
assert(lowering.languages.Back, "language Back declared")
assert(lowering.worlds.raw and lowering.worlds.lowered, "worlds declared")
assert(lowering.phases.lower_expr, "phase declared")
assert(lowering.values.one.kind == "Int", "named value preserves constructor kind")
assert(lowering.values.sum.qualified_kind == "Node.Add", "constructor path lowers to op kind")

local bytes = program:bytecode()
assert(bytes:sub(1, 4) == "LLPV", "bytecode image has LLPV magic")
assert(bytes == ll.bytecode(spec), "facade bytecode helper accepts ProgramSpec")
assert(bytes == ll.bytecode(program), "facade bytecode helper accepts ProgramImage")

local head = ll.describe_head("stream")
assert(head and head.slots[2].channels[1] == "index:value", "stream world slot is explicit index:value")
local role = ll.describe_role("fields")
assert(role and role.has_normalize, "field role owns normalization")

local ok_missing = pcall(function()
    return ll.load([[return pvm. Bad {
      lang. Expr { type. Node { op. Add { left [Node], right [Node] }, }, },
      world. raw [Expr],
      stream. input [raw] { value. bad (Node.Add { left = missing }), },
      root { input },
    }]], "missing") :bytecode()
end)
assert(not ok_missing, "constructor payload validation rejects missing fields")

local ok_wrong_world = pcall(function()
    return ll.load([[return pvm. BadWorld {
      lang. A { type. Node { op. Int { value [i64] }, }, },
      lang. B { type. Node { op. Use { other [A.Node] }, }, },
      world. a [A],
      world. b [B],
      stream. sa [a] { value. one (Node.Int { value = 1 }), },
      stream. sb [b] { value. bad (Node.Use { other = one }), },
      root { sb },
    }]], "wrong-world") :bytecode()
end)
assert(not ok_wrong_world, "constructor payload validation rejects values from another world")

local direct = ll.B.LlPvm.Symbol { value = "direct-literal" }
assert(direct ~= nil, "ASDL layer remains available for tools")

print("llpvm lua dsl api ok")
]]
