local S = require("lalin.schema.dsl")
S.use()

return schema. LalinExec {
  product. ExecFragmentId { interned, text [str], },
  product. ExecProjectionId { interned, text [str], },

  sum. ExecRuntime {
    ExecRuntimeC,
    ExecRuntimeLuaJIT,
    ExecRuntimeResidual,
    ExecRuntimeNamed {
      variant_unique,
      field. name [str],
    },
  },

  sum. ExecProjection {
    ExecProjectInline,
    ExecProjectFunctionCall,
    ExecProjectNativePointerCall,
    ExecProjectRuntimeBlock,
    ExecProjectObjectCode,
  },

  product. ExecArg {
    interned,
    field. name [str],
    field. ty [LalinCode.CodeType],
    field. value [LalinCode.CodeValueId],
  },

  sum. ExecResult {
    ExecResultVoid,
    ExecResultValue {
      variant_unique,
      field. ty [LalinCode.CodeType],
      field. value [LalinCode.CodeValueId],
    },
    ExecResultValues {
      variant_unique,
      values [many [LalinCode.CodeValueId]],
    },
  },

  sum. ExecFragmentKind {
    ExecFragmentStencil {
      variant_unique,
      artifact [LalinStencil.StencilArtifact],
      args [many [LalinExec.ExecArg]],
      result [LalinExec.ExecResult],
    },
    ExecFragmentScalarBlocks {
      variant_unique,
      blocks [many [LalinCode.CodeBlockId]],
    },
    ExecFragmentControlBlocks {
      variant_unique,
      blocks [many [LalinCode.CodeBlockId]],
    },
    ExecFragmentCall {
      variant_unique,
      callee [LalinCode.CodeFuncId],
      args [many [LalinExec.ExecArg]],
      result [LalinExec.ExecResult],
    },
    ExecFragmentReturn {
      variant_unique,
      result [LalinExec.ExecResult],
    },
    ExecFragmentTrap {
      variant_unique,
      reason [str],
    },
  },

  product. ExecFragment {
    interned,
    field. id [LalinExec.ExecFragmentId],
    source_func [LalinCode.CodeFuncId],
    source_blocks [many [LalinCode.CodeBlockId]],
    kind [LalinExec.ExecFragmentKind],
  },

  sum. ExecStencilDecision {
    ExecMaterializeStencil {
      variant_unique,
      fragment [LalinExec.ExecFragment],
      reason [str],
    },
    ExecSkipStencil {
      variant_unique,
      reason [str],
    },
  },

  product. ExecStencilInput {
    interned,
    artifact [optional [LalinStencil.StencilArtifact]],
    func [optional [LalinCode.CodeFuncId]],
    selected_reason [str],
    unselected_reason [str],
    missing_artifact_reason [str],
    missing_func_reason [str],
  },

  sum. ExecStencilSelection {
    ExecSelectStencil { variant_unique, reason [str], },
    ExecSelectSkip { variant_unique, reason [str], },
  },

  product. ExecPlanEntry {
    interned,
    kernel [LalinKernel.KernelId],
    decision [LalinExec.ExecStencilDecision],
  },

  product. ExecFuncPlan {
    interned,
    func [LalinCode.CodeFuncId],
    fragments [many [LalinExec.ExecFragment]],
  },

  product. ExecModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    stencil [LalinStencil.StencilModulePlan],
    entries [many [LalinExec.ExecPlanEntry]],
    funcs [many [LalinExec.ExecFuncPlan]],
  },
}
