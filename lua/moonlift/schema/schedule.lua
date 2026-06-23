local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonSchedule {
  product. ScheduleId { interned, text [str], },
  product. ScheduleTarget { interned, target [MoonBack.BackTargetModel], },
  sum. LaneShape {
    LaneScalar,
    LaneVector { variant_unique, elem_ty [MoonCode.CodeType], lanes [number], },
  },
  sum. TailPlan { TailNone, TailScalar, TailMasked, TailPeel { variant_unique, elems [number], }, },
  sum. ScheduleKind {
    ScheduleScalarIndex,
    ScheduleScalarPointer,
    ScheduleVector {
      variant_unique,
      lanes [MoonSchedule.LaneShape],
      unroll [number],
      interleave [number],
      tail [MoonSchedule.TailPlan],
    },
    ScheduleClosedForm,
  },
  sum. ScheduleProof {
    ScheduleProofTarget { variant_unique, reason [str], },
    ScheduleProofMemory { variant_unique, proof [MoonMem.MemProof], },
    ScheduleProofAlgebra { variant_unique, proof [MoonValue.AlgebraProof], },
    ScheduleProofProfit { variant_unique, reason [str], },
  },
  sum. ScheduleReject {
    ScheduleRejectTarget { variant_unique, reason [str], },
    ScheduleRejectMemory { variant_unique, reason [str], },
    ScheduleRejectAlgebra { variant_unique, reason [str], },
    ScheduleRejectProfit { variant_unique, reason [str], },
  },
  sum. KernelSchedule {
    ScheduleNoPlan {
      variant_unique,
      kernel [MoonKernel.KernelId],
      rejects [many [MoonSchedule.ScheduleReject]],
    },
    SchedulePlanned {
      variant_unique,
      field. id [MoonSchedule.ScheduleId],
      kernel [MoonKernel.KernelId],
      kind [MoonSchedule.ScheduleKind],
      proofs [many [MoonSchedule.ScheduleProof]],
      rejected_alternatives [many [MoonSchedule.ScheduleReject]],
    },
  },
  product. ScheduleModulePlan {
    interned,
    field. module [MoonCode.CodeModuleId],
    target [MoonSchedule.ScheduleTarget],
    schedules [many [MoonSchedule.KernelSchedule]],
  },
}
