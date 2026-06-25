local S = require("lalin.schema.dsl")
S.use()

return schema. LalinPhase {
  product. WorldId { interned, text [str], },
  product. PhaseId { interned, text [str], },
  product. MachineId { interned, text [str], },
  product. RootId { interned, text [str], },
  product. PackageId { interned, text [str], },

  sum. TypeRef {
    TypeRef { variant_unique, module_name [str], type_name [str], },
    TypeRefAny,
    TypeRefValue { variant_unique, field. name [str], },
  },

  product. World {
    interned,
    field. id [LalinPhase.WorldId],
    field. ty [LalinPhase.TypeRef],
  },

  sum. CachePolicy {
    CacheIdentity,
    CacheNode,
    CacheFull,
    CacheNone,
  },

  sum. MachineAbi {
    MachineAbiStatusReturning,
    MachineAbiPure,
    MachineAbiProcess,
    MachineAbiC,
  },

  sum. MachineImpl {
    ImplLalin {
      variant_unique,
      module_name [str],
      function_name [str],
    },
    ImplLua {
      variant_unique,
      module_name [str],
      function_name [str],
    },
    ImplC {
      variant_unique,
      symbol [str],
    },
    ImplExternal {
      variant_unique,
      capability [str],
    },
  },

  product. Machine {
    interned,
    field. id [LalinPhase.MachineId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [optional [LalinPhase.WorldId]],
    abi [LalinPhase.MachineAbi],
    impl [LalinPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Phase {
    interned,
    field. id [LalinPhase.PhaseId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [optional [LalinPhase.WorldId]],
    cache [LalinPhase.CachePolicy],
    deterministic [bool],
    machine [LalinPhase.MachineId],
  },

  product. Root {
    interned,
    field. id [LalinPhase.RootId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
  },

  product. PlanStep {
    interned,
    field. index [number],
    phase [LalinPhase.PhaseId],
    machine [LalinPhase.MachineId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [optional [LalinPhase.WorldId]],
    cache [LalinPhase.CachePolicy],
    deterministic [bool],
    abi [LalinPhase.MachineAbi],
    impl [LalinPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Plan {
    interned,
    root [LalinPhase.RootId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    steps [many [LalinPhase.PlanStep]],
  },

  product. Package {
    interned,
    field. id [LalinPhase.PackageId],
    worlds [many [LalinPhase.World]],
    machines [many [LalinPhase.Machine]],
    phases [many [LalinPhase.Phase]],
    roots [many [LalinPhase.Root]],
  },
}
