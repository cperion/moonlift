local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonExec {
  product. ExecFragmentId { interned, text [str], },
  product. ExecProjectionId { interned, text [str], },

  sum. ExecRuntime {
    ExecRuntimeC,
    ExecRuntimeLuaJIT,
    ExecRuntimeCopyPatch,
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
    field. ty [MoonCode.CodeType],
    field. value [MoonCode.CodeValueId],
  },

  sum. ExecResult {
    ExecResultVoid,
    ExecResultValue {
      variant_unique,
      field. ty [MoonCode.CodeType],
      field. value [MoonCode.CodeValueId],
    },
    ExecResultValues {
      variant_unique,
      values [many [MoonCode.CodeValueId]],
    },
  },

  sum. ExecFragmentKind {
    ExecFragmentStencil {
      variant_unique,
      artifact [MoonStencil.StencilArtifact],
      args [many [MoonExec.ExecArg]],
      result [MoonExec.ExecResult],
    },
    ExecFragmentScalarBlocks {
      variant_unique,
      blocks [many [MoonCode.CodeBlockId]],
    },
    ExecFragmentControlBlocks {
      variant_unique,
      blocks [many [MoonCode.CodeBlockId]],
    },
    ExecFragmentCall {
      variant_unique,
      callee [MoonCode.CodeFuncId],
      args [many [MoonExec.ExecArg]],
      result [MoonExec.ExecResult],
    },
    ExecFragmentReturn {
      variant_unique,
      result [MoonExec.ExecResult],
    },
    ExecFragmentTrap {
      variant_unique,
      reason [str],
    },
  },

  product. ExecFragment {
    interned,
    field. id [MoonExec.ExecFragmentId],
    source_func [MoonCode.CodeFuncId],
    source_blocks [many [MoonCode.CodeBlockId]],
    kind [MoonExec.ExecFragmentKind],
  },

  sum. ExecStencilDecision {
    ExecMaterializeStencil {
      variant_unique,
      fragment [MoonExec.ExecFragment],
      reason [str],
    },
    ExecSkipStencil {
      variant_unique,
      reason [str],
    },
  },

  product. ExecPlanEntry {
    interned,
    kernel [MoonKernel.KernelId],
    decision [MoonExec.ExecStencilDecision],
  },

  product. ExecFuncPlan {
    interned,
    func [MoonCode.CodeFuncId],
    fragments [many [MoonExec.ExecFragment]],
  },

  product. ExecModulePlan {
    interned,
    field. module [MoonCode.CodeModuleId],
    stencil [MoonStencil.StencilModulePlan],
    entries [many [MoonExec.ExecPlanEntry]],
    funcs [many [MoonExec.ExecFuncPlan]],
  },
}
