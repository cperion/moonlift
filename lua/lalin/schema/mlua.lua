local S = require("lalin.schema.dsl")
S.use()

return schema. LalinMlua {
  sum. IslandRole {
    IslandStruct,
    IslandExpose,
    IslandFunc,
    IslandExtern,
    IslandRegion,
    IslandExpr,
    IslandType,
    IslandConst,
    IslandStatic,
  },
  sum. IslandName {
    IslandNamed { variant_unique, field. name [str], },
    IslandAnonymous,
    IslandMalformedName { variant_unique, text [str], },
  },
  product. IslandText {
    role [LalinMlua.IslandRole],
    field. name [LalinMlua.IslandName],
    source [LalinSource.SourceSlice],
  },
  sum. Segment {
    LuaOpaque { occurrence [LalinSource.SourceOccurrence], },
    HostedIsland { island [LalinMlua.IslandText], range [LalinSource.SourceRange], },
    MalformedIsland {
      role [LalinMlua.IslandRole],
      occurrence [LalinSource.SourceOccurrence],
      reason [str],
    },
  },
  product. DocumentParts {
    document [LalinSource.DocumentSnapshot],
    segments [many [LalinMlua.Segment]],
    anchors [LalinSource.AnchorSet],
  },
  product. IslandParse {
    island [LalinMlua.IslandText],
    field. decls [LalinHost.HostDeclSet],
    field. module [LalinTree.Module],
    issues [many [LalinParse.ParseIssue]],
    anchors [LalinSource.AnchorSet],
  },
  product. DocumentParse {
    parts [LalinMlua.DocumentParts],
    combined [LalinHost.MluaParseResult],
    islands [many [LalinMlua.IslandParse]],
    anchors [LalinSource.AnchorSet],
  },
  product. DocumentAnalysis {
    parse [LalinMlua.DocumentParse],
    host [LalinHost.MluaHostPipelineResult],
    type_issues [many [LalinTree.TypeIssue]],
    control_facts [many [LalinTree.ControlFact]],
    back_report [LalinBack.BackValidationReport],
    anchors [LalinSource.AnchorSet],
  },
}
