local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonParse {
  product. ParseIssue { interned, message [str], offset [number], line [number], col [number], },
  sum. ParseResult {
    ParseResult {
      variant_unique,
      field. module [MoonTree.Module],
      issues [many [MoonParse.ParseIssue]],
    },
  },
}
