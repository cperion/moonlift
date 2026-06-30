local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCompiler {
  sum. CodeResultIssue {
    CodeResultIssueUnexpectedValue {
      variant_unique,
      expected [str],
      actual [str],
    },
    CodeResultIssueInvalidField {
      variant_unique,
      field. name [str],
      expected [str],
      actual [str],
    },
    CodeResultIssueInvalidCode {
      variant_unique,
      issue [LalinCode.CodeIssue],
    },
  },

  product. CodeResultReport {
    interned,
    issues [many [LalinCompiler.CodeResultIssue]],
  },

  product. CodeResult {
    interned,
    field. module [LalinCode.CodeModule],
    contracts [many [LalinCode.CodeFuncContractFact]],
    layout_env [LalinSem.LayoutEnv],
  },

  sum. FlatlineImageIssue {
    FlatlineImageIssueUnexpectedValue {
      variant_unique,
      expected [str],
      actual [str],
    },
    FlatlineImageIssueBadHeader {
      variant_unique,
      reason [str],
    },
    FlatlineImageIssueBadMagic {
      variant_unique,
      actual [number],
    },
    FlatlineImageIssueBadVersion {
      variant_unique,
      expected [number],
      actual [number],
    },
    FlatlineImageIssueBadSection {
      variant_unique,
      field. name [str],
      reason [str],
    },
  },

  product. FlatlineImageReport {
    interned,
    issues [many [LalinCompiler.FlatlineImageIssue]],
  },

  product. FlatlineImage {
    interned,
    format [str],
    version [number],
    bytes [str],
  },
}
