local S = require("lalin.schema.dsl")
S.use()

return schema. LalinSem {
  sum. FieldRef {
    FieldByName { variant_unique, field_name [str], field. ty [LalinType.Type], },
    FieldByOffset {
      variant_unique,
      field_name [str],
      offset [number],
      field. ty [LalinType.Type],
      storage [LalinHost.HostFieldRep],
    },
  },
  product. FieldLayout {
    interned,
    field_name [str],
    offset [number],
    field. ty [LalinType.Type],
  },
  product. MemLayout { interned, size [number], align [number], },
  sum. TypeLayout {
    LayoutNamed {
      variant_unique,
      module_name [str],
      type_name [str],
      fields [many [LalinSem.FieldLayout]],
      size [number],
      align [number],
    },
    LayoutLocal {
      variant_unique,
      sym [LalinCore.TypeSym],
      fields [many [LalinSem.FieldLayout]],
      size [number],
      align [number],
    },
  },
  product. LayoutEnv { interned, layouts [many [LalinSem.TypeLayout]], },
  product. ConstFieldValue {
    interned,
    field. name [str],
    field. value [LalinSem.ConstValue],
  },
  sum. ConstValue {
    ConstInt { variant_unique, field. ty [LalinType.Type], raw [str], },
    ConstFloat { variant_unique, field. ty [LalinType.Type], raw [str], },
    ConstBool { variant_unique, field. value [bool], },
    ConstNil { variant_unique, field. ty [LalinType.Type], },
    ConstAgg {
      variant_unique,
      field. ty [LalinType.Type],
      fields [many [LalinSem.ConstFieldValue]],
    },
    ConstArray {
      variant_unique,
      elem_ty [LalinType.Type],
      elems [many [LalinSem.ConstValue]],
    },
  },
  product. ConstLocalEntry {
    interned,
    binding [LalinBind.Binding],
    field. value [LalinSem.ConstValue],
  },
  product. ConstLocalEnv { interned, entries [many [LalinSem.ConstLocalEntry]], },
  sum. FlowClass {
    FlowUnknown,
    FlowFallsThrough,
    FlowJumps,
    FlowYields,
    FlowReturns,
    FlowTerminates,
  },
}
