local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonEffect {
  product. EffectId { interned, text [str], },
  sum. EffectObject {
    EffectObjectMem { variant_unique, object [MoonMem.MemObjectId], },
    EffectObjectStore { variant_unique, store_value [MoonCode.CodeValueId], },
    EffectObjectUnknown { variant_unique, reason [str], },
  },
  sum. OpEffect {
    EffectRead {
      variant_unique,
      object [MoonEffect.EffectObject],
      proof [optional [MoonMem.MemProof]],
    },
    EffectWrite {
      variant_unique,
      object [MoonEffect.EffectObject],
      proof [optional [MoonMem.MemProof]],
    },
    EffectInvalidate { variant_unique, object [MoonEffect.EffectObject], reason [str], },
    EffectRetain { variant_unique, field. value [MoonCode.CodeValueId], reason [str], },
    EffectNoEscape { variant_unique, field. value [MoonCode.CodeValueId], reason [str], },
    EffectMayTrap { variant_unique, reason [str], },
    EffectNoTrap { variant_unique, reason [str], },
    EffectVolatile { variant_unique, reason [str], },
    EffectAtomic { variant_unique, ordering [str], },
    EffectUnknown { variant_unique, reason [str], },
  },
  product. CallSummary {
    interned,
    callee [optional [MoonCode.CodeFuncId]],
    extern_name [optional [str]],
    effects [many [MoonEffect.OpEffect]],
  },
  product. InstEffect {
    interned,
    inst [MoonCode.CodeInstId],
    effects [many [MoonEffect.OpEffect]],
  },
  product. TermEffect {
    interned,
    block [MoonCode.CodeBlockId],
    effects [many [MoonEffect.OpEffect]],
  },
  product. EffectFactSet {
    interned,
    field. module [MoonCode.CodeModuleId],
    calls [many [MoonEffect.CallSummary]],
    insts [many [MoonEffect.InstEffect]],
    terms [many [MoonEffect.TermEffect]],
  },
}
