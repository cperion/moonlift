local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonSem {
  sum. FieldRef {
    FieldByName { variant_unique, field_name [str], field. ty [MoonType.Type], },
    FieldByOffset {
      variant_unique,
      field_name [str],
      offset [number],
      field. ty [MoonType.Type],
      storage [MoonHost.HostFieldRep],
    },
  },
  product. FieldLayout {
    interned,
    field_name [str],
    offset [number],
    field. ty [MoonType.Type],
  },
  product. MemLayout { interned, size [number], align [number], },
  sum. TypeLayout {
    LayoutNamed {
      variant_unique,
      module_name [str],
      type_name [str],
      fields [many [MoonSem.FieldLayout]],
      size [number],
      align [number],
    },
    LayoutLocal {
      variant_unique,
      sym [MoonCore.TypeSym],
      fields [many [MoonSem.FieldLayout]],
      size [number],
      align [number],
    },
  },
  product. LayoutEnv { interned, layouts [many [MoonSem.TypeLayout]], },
  product. ConstFieldValue {
    interned,
    field. name [str],
    field. value [MoonSem.ConstValue],
  },
  sum. ConstValue {
    ConstInt { variant_unique, field. ty [MoonType.Type], raw [str], },
    ConstFloat { variant_unique, field. ty [MoonType.Type], raw [str], },
    ConstBool { variant_unique, field. value [bool], },
    ConstNil { variant_unique, field. ty [MoonType.Type], },
    ConstAgg {
      variant_unique,
      field. ty [MoonType.Type],
      fields [many [MoonSem.ConstFieldValue]],
    },
    ConstArray {
      variant_unique,
      elem_ty [MoonType.Type],
      elems [many [MoonSem.ConstValue]],
    },
  },
  product. ConstLocalEntry {
    interned,
    binding [MoonBind.Binding],
    field. value [MoonSem.ConstValue],
  },
  product. ConstLocalEnv { interned, entries [many [MoonSem.ConstLocalEntry]], },
  sum. FlowClass {
    FlowUnknown,
    FlowFallsThrough,
    FlowJumps,
    FlowYields,
    FlowReturns,
    FlowTerminates,
  },
}
