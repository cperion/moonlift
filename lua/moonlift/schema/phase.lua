local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonPhase {
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
    field. id [MoonPhase.WorldId],
    field. ty [MoonPhase.TypeRef],
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
    MachineAbiCranelift,
  },

  sum. MachineImpl {
    ImplMoonlift {
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
    ImplCranelift {
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
    field. id [MoonPhase.MachineId],
    input [MoonPhase.WorldId],
    output [MoonPhase.WorldId],
    diagnostics [optional [MoonPhase.WorldId]],
    abi [MoonPhase.MachineAbi],
    impl [MoonPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Phase {
    interned,
    field. id [MoonPhase.PhaseId],
    input [MoonPhase.WorldId],
    output [MoonPhase.WorldId],
    diagnostics [optional [MoonPhase.WorldId]],
    cache [MoonPhase.CachePolicy],
    deterministic [bool],
    machine [MoonPhase.MachineId],
  },

  product. Root {
    interned,
    field. id [MoonPhase.RootId],
    input [MoonPhase.WorldId],
    output [MoonPhase.WorldId],
  },

  product. PlanStep {
    interned,
    field. index [number],
    phase [MoonPhase.PhaseId],
    machine [MoonPhase.MachineId],
    input [MoonPhase.WorldId],
    output [MoonPhase.WorldId],
    diagnostics [optional [MoonPhase.WorldId]],
    cache [MoonPhase.CachePolicy],
    deterministic [bool],
    abi [MoonPhase.MachineAbi],
    impl [MoonPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Plan {
    interned,
    root [MoonPhase.RootId],
    input [MoonPhase.WorldId],
    output [MoonPhase.WorldId],
    steps [many [MoonPhase.PlanStep]],
  },

  product. Package {
    interned,
    field. id [MoonPhase.PackageId],
    worlds [many [MoonPhase.World]],
    machines [many [MoonPhase.Machine]],
    phases [many [MoonPhase.Phase]],
    roots [many [MoonPhase.Root]],
  },
}
