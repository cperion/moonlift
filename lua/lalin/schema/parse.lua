local S = require("lalin.schema.dsl")
S.use()

return schema. LalinParse {
  product. ParseIssue { interned, message [str], offset [number], line [number], col [number], },
  sum. ParseResult {
    ParseResult {
      variant_unique,
      field. module [LalinTree.Module],
      issues [many [LalinParse.ParseIssue]],
    },
  },
}
