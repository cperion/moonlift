local S = require("lalin.schema.dsl")
S.use()

return schema. LalinLower {
  product. LowerFragmentId { interned, text [str], },
  sum. LowerTarget { LowerTargetBack, LowerTargetC, },
  sum. LowerCover {
    LowerCoverFunction { variant_unique, func [LalinCode.CodeFuncId], },
    LowerCoverLoop { variant_unique, loop [LalinGraph.GraphLoopId], },
    LowerCoverBlock {
      variant_unique,
      func [LalinCode.CodeFuncId],
      block [LalinCode.CodeBlockId],
    },
    LowerCoverBlockRange {
      variant_unique,
      func [LalinCode.CodeFuncId],
      entry [LalinCode.CodeBlockId],
      exit [LalinCode.CodeBlockId],
    },
  },
  sum. LowerStrategy {
    LowerStrategyCode { variant_unique, reason [str], },
    LowerStrategyKernel {
      variant_unique,
      kernel [LalinKernel.KernelId],
      schedule [LalinSchedule.ScheduleId],
    },
    LowerStrategyClosedForm {
      variant_unique,
      kernel [LalinKernel.KernelId],
      fact [LalinValue.ClosedFormFact],
    },
  },
  sum. LowerProof {
    LowerProofCoverage { variant_unique, reason [str], },
    LowerProofKernel { variant_unique, kernel [LalinKernel.KernelId], reason [str], },
    LowerProofSchedule { variant_unique, schedule [LalinSchedule.ScheduleId], reason [str], },
    LowerProofFallback { variant_unique, reason [str], },
  },
  sum. LowerIssue {
    LowerIssueOverlap {
      variant_unique,
      a [LalinLower.LowerFragmentId],
      b [LalinLower.LowerFragmentId],
    },
    LowerIssueGap { variant_unique, func [LalinCode.CodeFuncId], reason [str], },
    LowerIssueFallback { variant_unique, cover [LalinLower.LowerCover], reason [str], },
  },
  product. LowerFragment {
    interned,
    field. id [LalinLower.LowerFragmentId],
    cover [LalinLower.LowerCover],
    strategy [LalinLower.LowerStrategy],
    proofs [many [LalinLower.LowerProof]],
    issues [many [LalinLower.LowerIssue]],
  },
  product. LowerFuncPlan {
    interned,
    func [LalinCode.CodeFuncId],
    fragments [many [LalinLower.LowerFragment]],
  },
  product. LowerModule {
    interned,
    field. module [LalinCode.CodeModuleId],
    target [LalinLower.LowerTarget],
    kernels [LalinKernel.KernelModulePlan],
    schedules [LalinSchedule.ScheduleModulePlan],
    funcs [many [LalinLower.LowerFuncPlan]],
    issues [many [LalinLower.LowerIssue]],
  },
  product. LowerValidationReport { interned, issues [many [LalinLower.LowerIssue]], },
}
