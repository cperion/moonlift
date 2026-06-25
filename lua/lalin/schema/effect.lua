local S = require("lalin.schema.dsl")
S.use()

return schema. LalinEffect {
  product. EffectId { interned, text [str], },
  sum. EffectObject {
    EffectObjectMem { variant_unique, object [LalinMem.MemObjectId], },
    EffectObjectStore { variant_unique, store_value [LalinCode.CodeValueId], },
    EffectObjectUnknown { variant_unique, reason [str], },
  },
  sum. OpEffect {
    EffectRead {
      variant_unique,
      object [LalinEffect.EffectObject],
      proof [optional [LalinMem.MemProof]],
    },
    EffectWrite {
      variant_unique,
      object [LalinEffect.EffectObject],
      proof [optional [LalinMem.MemProof]],
    },
    EffectInvalidate { variant_unique, object [LalinEffect.EffectObject], reason [str], },
    EffectRetain { variant_unique, field. value [LalinCode.CodeValueId], reason [str], },
    EffectNoEscape { variant_unique, field. value [LalinCode.CodeValueId], reason [str], },
    EffectMayTrap { variant_unique, reason [str], },
    EffectNoTrap { variant_unique, reason [str], },
    EffectVolatile { variant_unique, reason [str], },
    EffectAtomic { variant_unique, ordering [str], },
    EffectUnknown { variant_unique, reason [str], },
  },
  product. CallSummary {
    interned,
    callee [optional [LalinCode.CodeFuncId]],
    extern_name [optional [str]],
    effects [many [LalinEffect.OpEffect]],
  },
  product. InstEffect {
    interned,
    inst [LalinCode.CodeInstId],
    effects [many [LalinEffect.OpEffect]],
  },
  product. TermEffect {
    interned,
    block [LalinCode.CodeBlockId],
    effects [many [LalinEffect.OpEffect]],
  },
  product. EffectFactSet {
    interned,
    field. module [LalinCode.CodeModuleId],
    calls [many [LalinEffect.CallSummary]],
    insts [many [LalinEffect.InstEffect]],
    terms [many [LalinEffect.TermEffect]],
  },
}
