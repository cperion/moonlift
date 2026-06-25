local S = require("lalin.schema.dsl")
S.use()

return schema. LalinGraph {
  product. GraphBlockId {
    interned,
    func [LalinCode.CodeFuncId],
    block [LalinCode.CodeBlockId],
  },
  product. GraphInstRef {
    interned,
    func [LalinCode.CodeFuncId],
    block [LalinCode.CodeBlockId],
    inst [LalinCode.CodeInstId],
  },
  product. GraphEdge {
    interned,
    from [LalinGraph.GraphBlockId],
    to [LalinGraph.GraphBlockId],
    kind [str],
  },
  product. GraphUse {
    interned,
    field. value [LalinCode.CodeValueId],
    inst [optional [LalinGraph.GraphInstRef]],
    term_block [optional [LalinGraph.GraphBlockId]],
    role [str],
  },
  product. GraphDef {
    interned,
    field. value [LalinCode.CodeValueId],
    inst [optional [LalinGraph.GraphInstRef]],
    param [optional [LalinCode.CodeValueId]],
  },
  product. GraphLoopId { interned, text [str], },
  product. GraphLoop {
    interned,
    field. id [LalinGraph.GraphLoopId],
    func [LalinCode.CodeFuncId],
    header [LalinGraph.GraphBlockId],
    body [many [LalinGraph.GraphBlockId]],
    latches [many [LalinGraph.GraphEdge]],
    exits [many [LalinGraph.GraphEdge]],
  },
  product. CodeFuncGraph {
    interned,
    func [LalinCode.CodeFuncId],
    edges [many [LalinGraph.GraphEdge]],
    defs [many [LalinGraph.GraphDef]],
    uses [many [LalinGraph.GraphUse]],
    loops [many [LalinGraph.GraphLoop]],
  },
  product. CodeGraph {
    interned,
    field. module [LalinCode.CodeModuleId],
    funcs [many [LalinGraph.CodeFuncGraph]],
  },
}
