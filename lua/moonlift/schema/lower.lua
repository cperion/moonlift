local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonLower {
  product. LowerFragmentId { interned, text [str], },
  sum. LowerTarget { LowerTargetBack, LowerTargetC, },
  sum. LowerCover {
    LowerCoverFunction { variant_unique, func [MoonCode.CodeFuncId], },
    LowerCoverLoop { variant_unique, loop [MoonGraph.GraphLoopId], },
    LowerCoverBlock {
      variant_unique,
      func [MoonCode.CodeFuncId],
      block [MoonCode.CodeBlockId],
    },
    LowerCoverBlockRange {
      variant_unique,
      func [MoonCode.CodeFuncId],
      entry [MoonCode.CodeBlockId],
      exit [MoonCode.CodeBlockId],
    },
  },
  sum. LowerStrategy {
    LowerStrategyCode { variant_unique, reason [str], },
    LowerStrategyKernel {
      variant_unique,
      kernel [MoonKernel.KernelId],
      schedule [MoonSchedule.ScheduleId],
    },
    LowerStrategyClosedForm {
      variant_unique,
      kernel [MoonKernel.KernelId],
      fact [MoonValue.ClosedFormFact],
    },
  },
  sum. LowerProof {
    LowerProofCoverage { variant_unique, reason [str], },
    LowerProofKernel { variant_unique, kernel [MoonKernel.KernelId], reason [str], },
    LowerProofSchedule { variant_unique, schedule [MoonSchedule.ScheduleId], reason [str], },
    LowerProofFallback { variant_unique, reason [str], },
  },
  sum. LowerIssue {
    LowerIssueOverlap {
      variant_unique,
      a [MoonLower.LowerFragmentId],
      b [MoonLower.LowerFragmentId],
    },
    LowerIssueGap { variant_unique, func [MoonCode.CodeFuncId], reason [str], },
    LowerIssueFallback { variant_unique, cover [MoonLower.LowerCover], reason [str], },
  },
  product. LowerFragment {
    interned,
    field. id [MoonLower.LowerFragmentId],
    cover [MoonLower.LowerCover],
    strategy [MoonLower.LowerStrategy],
    proofs [many [MoonLower.LowerProof]],
    issues [many [MoonLower.LowerIssue]],
  },
  product. LowerFuncPlan {
    interned,
    func [MoonCode.CodeFuncId],
    fragments [many [MoonLower.LowerFragment]],
  },
  product. LowerModule {
    interned,
    field. module [MoonCode.CodeModuleId],
    target [MoonLower.LowerTarget],
    kernels [MoonKernel.KernelModulePlan],
    schedules [MoonSchedule.ScheduleModulePlan],
    funcs [many [MoonLower.LowerFuncPlan]],
    issues [many [MoonLower.LowerIssue]],
  },
  product. LowerValidationReport { interned, issues [many [MoonLower.LowerIssue]], },
}
