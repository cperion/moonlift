local S = require("lalin.schema.dsl")
S.use()

return schema. LalinSchedule {
  product. ScheduleId { interned, text [str], },
  product. ScheduleTarget { interned, target [LalinBack.BackTargetModel], },
  sum. LaneShape {
    LaneScalar,
    LaneVector { variant_unique, elem_ty [LalinCode.CodeType], lanes [number], },
  },
  sum. TailPlan { TailNone, TailScalar, TailMasked, TailPeel { variant_unique, elems [number], }, },
  sum. ScheduleForm {
    ScheduleScalarIndex,
    ScheduleScalarPointer,
    ScheduleVector {
      variant_unique,
      lanes [LalinSchedule.LaneShape],
      unroll [number],
      interleave [number],
      tail [LalinSchedule.TailPlan],
    },
    ScheduleClosedForm,
  },
  sum. ScheduleProof {
    ScheduleProofTarget { variant_unique, reason [str], },
    ScheduleProofMemory { variant_unique, proof [LalinMem.MemProof], },
    ScheduleProofAlgebra { variant_unique, proof [LalinValue.AlgebraProof], },
    ScheduleProofProfit { variant_unique, reason [str], },
  },
  sum. ScheduleReject {
    ScheduleRejectTarget { variant_unique, reason [str], },
    ScheduleRejectMemory { variant_unique, reason [str], },
    ScheduleRejectAlgebra { variant_unique, reason [str], },
    ScheduleRejectProfit { variant_unique, reason [str], },
  },
  product. ScheduleEmitterCapability {
    interned,
    kind [str],
    executable [bool],
    reason [str],
    rejects [many [LalinSchedule.ScheduleReject]],
  },
  product. SchedulePlanInput {
    interned,
    vector_form [optional [LalinSchedule.ScheduleForm]],
    vector_capability [optional [LalinSchedule.ScheduleEmitterCapability]],
    scalar_form [LalinSchedule.ScheduleForm],
    scalar_capability [optional [LalinSchedule.ScheduleEmitterCapability]],
  },
  sum. SchedulePlanSelection {
    ScheduleSelectionNoPlan { variant_unique, rejects [many [LalinSchedule.ScheduleReject]], },
    ScheduleSelectionPlanned {
      variant_unique,
      form [LalinSchedule.ScheduleForm],
      capability [LalinSchedule.ScheduleEmitterCapability],
      rejected_alternatives [many [LalinSchedule.ScheduleReject]],
    },
  },
  sum. KernelSchedule {
    ScheduleNoPlan {
      variant_unique,
      kernel [LalinKernel.KernelId],
      rejects [many [LalinSchedule.ScheduleReject]],
    },
    SchedulePlanned {
      variant_unique,
      field. id [LalinSchedule.ScheduleId],
      kernel [LalinKernel.KernelId],
      form [LalinSchedule.ScheduleForm],
      proofs [many [LalinSchedule.ScheduleProof]],
      rejected_alternatives [many [LalinSchedule.ScheduleReject]],
    },
  },
  product. ScheduleModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    target [LalinSchedule.ScheduleTarget],
    schedules [many [LalinSchedule.KernelSchedule]],
  },
}
