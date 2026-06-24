local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonCompiler {
  sum. CodeResultIssue {
    CodeResultIssueWrongClass {
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
      issue [MoonCode.CodeIssue],
    },
  },

  product. CodeResultReport {
    interned,
    issues [many [MoonCompiler.CodeResultIssue]],
  },

  product. CodeResult {
    interned,
    field. module [MoonCode.CodeModule],
    contracts [many [MoonCode.CodeFuncContractFact]],
    layout_env [MoonSem.LayoutEnv],
  },

  sum. FlatlineImageIssue {
    FlatlineImageIssueWrongClass {
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
    issues [many [MoonCompiler.FlatlineImageIssue]],
  },

  product. FlatlineImage {
    interned,
    format [str],
    version [number],
    bytes [str],
  },
}
