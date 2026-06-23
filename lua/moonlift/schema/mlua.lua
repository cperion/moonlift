local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonMlua {
  sum. IslandKind {
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
    kind [MoonMlua.IslandKind],
    field. name [MoonMlua.IslandName],
    source [MoonSource.SourceSlice],
  },
  sum. Segment {
    LuaOpaque { occurrence [MoonSource.SourceOccurrence], },
    HostedIsland { island [MoonMlua.IslandText], range [MoonSource.SourceRange], },
    MalformedIsland {
      kind [MoonMlua.IslandKind],
      occurrence [MoonSource.SourceOccurrence],
      reason [str],
    },
  },
  product. DocumentParts {
    document [MoonSource.DocumentSnapshot],
    segments [many [MoonMlua.Segment]],
    anchors [MoonSource.AnchorSet],
  },
  product. IslandParse {
    island [MoonMlua.IslandText],
    field. decls [MoonHost.HostDeclSet],
    field. module [MoonTree.Module],
    region_frags [many [MoonOpen.RegionFrag]],
    expr_frags [many [MoonOpen.ExprFrag]],
    issues [many [MoonParse.ParseIssue]],
    anchors [MoonSource.AnchorSet],
  },
  product. DocumentParse {
    parts [MoonMlua.DocumentParts],
    combined [MoonHost.MluaParseResult],
    islands [many [MoonMlua.IslandParse]],
    anchors [MoonSource.AnchorSet],
  },
  product. DocumentAnalysis {
    parse [MoonMlua.DocumentParse],
    host [MoonHost.MluaHostPipelineResult],
    open_report [MoonOpen.ValidationReport],
    type_issues [many [MoonTree.TypeIssue]],
    control_facts [many [MoonTree.ControlFact]],
    back_report [MoonBack.BackValidationReport],
    anchors [MoonSource.AnchorSet],
  },
}
