local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonGraph {
  product. GraphBlockId {
    interned,
    func [MoonCode.CodeFuncId],
    block [MoonCode.CodeBlockId],
  },
  product. GraphInstRef {
    interned,
    func [MoonCode.CodeFuncId],
    block [MoonCode.CodeBlockId],
    inst [MoonCode.CodeInstId],
  },
  product. GraphEdge {
    interned,
    from [MoonGraph.GraphBlockId],
    to [MoonGraph.GraphBlockId],
    kind [str],
  },
  product. GraphUse {
    interned,
    field. value [MoonCode.CodeValueId],
    inst [optional [MoonGraph.GraphInstRef]],
    term_block [optional [MoonGraph.GraphBlockId]],
    role [str],
  },
  product. GraphDef {
    interned,
    field. value [MoonCode.CodeValueId],
    inst [optional [MoonGraph.GraphInstRef]],
    param [optional [MoonCode.CodeValueId]],
  },
  product. GraphLoopId { interned, text [str], },
  product. GraphLoop {
    interned,
    field. id [MoonGraph.GraphLoopId],
    func [MoonCode.CodeFuncId],
    header [MoonGraph.GraphBlockId],
    body [many [MoonGraph.GraphBlockId]],
    latches [many [MoonGraph.GraphEdge]],
    exits [many [MoonGraph.GraphEdge]],
  },
  product. CodeFuncGraph {
    interned,
    func [MoonCode.CodeFuncId],
    edges [many [MoonGraph.GraphEdge]],
    defs [many [MoonGraph.GraphDef]],
    uses [many [MoonGraph.GraphUse]],
    loops [many [MoonGraph.GraphLoop]],
  },
  product. CodeGraph {
    interned,
    field. module [MoonCode.CodeModuleId],
    funcs [many [MoonGraph.CodeFuncGraph]],
  },
}
