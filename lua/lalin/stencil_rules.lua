local pvm = require("lalin.pvm")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_rules ~= nil then return T._lalin_api_cache.stencil_rules end

    local lalin = require("lalin")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local Core = T.LalinCore
    local Code = T.LalinCode
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Value = T.LalinValue
    local function sym(name) return llb.symbol(name) end
    local StencilExprFact = sym("StencilExprFact")
    local StencilClassFact = sym("StencilClassFact")
    local IndexLaneSelection = sym("IndexLaneSelection")
    local CodeType = sym("CodeType")
    local StencilTypeFact = sym("StencilTypeFact")
    local StoreStencilFact = sym("StoreStencilFact")
    local StoreStencilSelection = sym("StoreStencilSelection")
    local ReduceStencilFact = sym("ReduceStencilFact")
    local ReduceStencilSelection = sym("ReduceStencilSelection")
    local expr = sym("expr")
    local class = sym("class")
    local lane = sym("lane")
    local ty = sym("ty")
    local ctx = sym("ctx")
    local selection = sym("selection")
    local kernel_value = sym("kernel_value")
    local load = sym("load")
    local fill = sym("fill")
    local unary = sym("unary")
    local cast = sym("cast")
    local binary = sym("binary")
    local cmp = sym("cmp")
    local map = sym("map")
    local compare = sym("compare")
    local zip_map = sym("zip_map")
    local zip_compare = sym("zip_compare")
    local int = sym("int")
    local float = sym("float")
    local index = sym("index")
    local bool8 = sym("bool8")
    local load_class = sym("load_class")
    local fill_class = sym("fill_class")
    local map_class = sym("map_class")
    local cast_class = sym("cast_class")
    local zip_map_class = sym("zip_map_class")
    local compare_class = sym("compare_class")
    local pred_const = sym("pred_const")
    local zip_compare_class = sym("zip_compare_class")
    local index_lane = sym("index_lane")
    local type_class = sym("type_class")
    local store_fill = sym("store_fill")
    local store_copy = sym("store_copy")
    local store_gather = sym("store_gather")
    local store_scatter = sym("store_scatter")
    local store_in_place_map = sym("store_in_place_map")
    local store_map = sym("store_map")
    local store_cast = sym("store_cast")
    local store_compare = sym("store_compare")
    local store_zip_map = sym("store_zip_map")
    local store_zip_compare = sym("store_zip_compare")
    local scan_array = sym("scan_array")
    local find_array = sym("find_array")
    local partition_array = sym("partition_array")
    local reduce_array = sym("reduce_array")
    local reduce_map = sym("reduce_map")
    local reduce_zip = sym("reduce_zip")
    local reduce_count = sym("reduce_count")
    local is_int_type, is_float_type, is_index_type, is_bool8_type, is_index_data_type
    local same_type, unary_supported, binary_supported, reduction_supported, cast_supported
    local predicate_from_cmp_const
    local impl = {}
    local function with_class_kind(kind, fields)
        fields.kind = kind
        return fields
    end
    local function with_selection_kind(kind, vocab, fields)
        fields.kind = kind
        fields.vocab = vocab
        return fields
    end
    impl.has_const_pred = function(op, value, const_on_left)
        return predicate_from_cmp_const(op, value, const_on_left) ~= nil
    end
    impl.type_class = function(fields) return fields end
    impl.load_class = function(fields) return with_class_kind("load", fields) end
    impl.fill_class = function(fields)
        local value = fields.value
        if pvm.classof(value) == Value.ValueExprConst
            and pvm.classof(value.const) == Code.CodeConstLiteral
            and pvm.classof(value.const.literal) == Core.LitInt then
            fields.const_int = tonumber(value.const.literal.raw)
        end
        return with_class_kind("fill", fields)
    end
    impl.map_class = function(fields) return with_class_kind("map", fields) end
    impl.cast_class = function(fields) return with_class_kind("cast", fields) end
    impl.zip_map_class = function(fields) return with_class_kind("zip_map", fields) end
    impl.compare_class = function(fields) return with_class_kind("compare", fields) end
    impl.zip_compare_class = function(fields) return with_class_kind("zip_compare", fields) end
    impl.pred_const = function(fields) return predicate_from_cmp_const(fields.op, fields.value, fields.const_on_left) end
    impl.index_lane = function(fields) return fields end
    impl.store_fill = function(fields) return with_selection_kind("fill", Stencil.StencilFill, fields) end
    impl.store_copy = function(fields) return with_selection_kind("copy", Stencil.StencilCopy, fields) end
    impl.store_gather = function(fields) return with_selection_kind("gather", Stencil.StencilGather, fields) end
    impl.store_scatter = function(fields) return with_selection_kind("scatter", Stencil.StencilScatter, fields) end
    impl.store_in_place_map = function(fields) return with_selection_kind("in_place_map", Stencil.StencilInPlaceMap, fields) end
    impl.store_map = function(fields) return with_selection_kind("map", Stencil.StencilMap, fields) end
    impl.store_cast = function(fields) return with_selection_kind("cast", Stencil.StencilCast, fields) end
    impl.store_compare = function(fields) return with_selection_kind("compare", Stencil.StencilCompare, fields) end
    impl.store_zip_map = function(fields) return with_selection_kind("zip_map", Stencil.StencilZipMap, fields) end
    impl.store_zip_compare = function(fields) return with_selection_kind("zip_compare", Stencil.StencilZipCompare, fields) end
    impl.scan_array = function(fields) return with_selection_kind("scan", Stencil.StencilScan, fields) end
    impl.find_array = function(fields) return with_selection_kind("find", Stencil.StencilFind, fields) end
    impl.partition_array = function(fields) return with_selection_kind("partition", Stencil.StencilPartition, fields) end
    impl.reduce_array = function(fields) return with_selection_kind("reduce", Stencil.StencilReduce, fields) end
    impl.reduce_map = function(fields) return with_selection_kind("map_reduce", Stencil.StencilMapReduce, fields) end
    impl.reduce_zip = function(fields) return with_selection_kind("zip_reduce", Stencil.StencilZipReduce, fields) end
    impl.reduce_count = function(fields) return with_selection_kind("count", Stencil.StencilCount, fields) end
    impl.store_stencil_plan = function(fields) return fields end
    impl.reduce_stencil_plan = function(fields) return fields end
    impl.store_stencil_no_plan = function(fields) fields.kind = "no_plan"; return fields end
    impl.reduce_stencil_no_plan = function(fields) fields.kind = "no_plan"; return fields end

    local function build_rules()
    return llisle {
  predicate. has_const_pred [impl.has_const_pred] { input { sym("op") [Any], sym("value") [Any], sym("const_on_left") [Any] }, pure },
  predicate. is_int_type [impl.is_int_type] { input { sym("ty") [Any] }, pure },
  predicate. is_float_type [impl.is_float_type] { input { sym("ty") [Any] }, pure },
  predicate. is_index_type [impl.is_index_type] { input { sym("ty") [Any] }, pure },
  predicate. is_bool8_type [impl.is_bool8_type] { input { sym("ty") [Any] }, pure },
  predicate. is_index_data_type [impl.is_index_data_type] { input { sym("ty") [Any] }, pure },
  predicate. same_type [impl.same_type] { input { sym("a") [Any], sym("b") [Any] }, pure },
  predicate. unary_supported [impl.unary_supported] { input { sym("op") [Any], sym("ty") [Any] }, pure },
  predicate. binary_supported [impl.binary_supported] { input { sym("op") [Any], sym("ty") [Any] }, pure },
  predicate. reduction_supported [impl.reduction_supported] { input { sym("reduction") [Any], sym("elem_ty") [Any], sym("result_ty") [Any] }, pure },
  predicate. cast_supported [impl.cast_supported] { input { sym("op") [Any], sym("src_ty") [Any], sym("dst_ty") [Any] }, pure },

  constructor. type_class [impl.type_class] { input { sym("kind") [Any], sym("ty") [CodeType] }, output { sym("class") [StencilTypeFact] } },
  constructor. load_class [impl.load_class] { input { sym("lane") [Any], sym("index") [Any] }, output { sym("class") [StencilClassFact] } },
  constructor. fill_class [impl.fill_class] { input { sym("value") [Any] }, output { sym("class") [StencilClassFact] } },
  constructor. map_class [impl.map_class] { input { sym("op") [Any], sym("lane") [Any], sym("index") [Any], sym("result_ty") [CodeType] }, output { sym("class") [StencilClassFact] } },
  constructor. cast_class [impl.cast_class] { input { sym("op") [Any], sym("lane") [Any], sym("index") [Any], sym("src_ty") [CodeType], sym("result_ty") [CodeType] }, output { sym("class") [StencilClassFact] } },
  constructor. zip_map_class [impl.zip_map_class] { input { sym("op") [Any], sym("lhs") [Any], sym("rhs") [Any], sym("lhs_index") [Any], sym("rhs_index") [Any], sym("result_ty") [CodeType] }, output { sym("class") [StencilClassFact] } },
  constructor. compare_class [impl.compare_class] { input { sym("pred") [Any], sym("lane") [Any], sym("index") [Any], sym("result_ty") [CodeType] }, output { sym("class") [StencilClassFact] } },
  constructor. zip_compare_class [impl.zip_compare_class] { input { sym("cmp") [Any], sym("lhs") [Any], sym("rhs") [Any], sym("lhs_index") [Any], sym("rhs_index") [Any], sym("result_ty") [CodeType] }, output { sym("class") [StencilClassFact] } },
  constructor. pred_const [impl.pred_const] { input { sym("op") [Any], sym("value") [Any], sym("const_on_left") [Any] }, output { sym("pred") [Any] } },
  constructor. index_lane [impl.index_lane] { input { sym("lane") [Any], sym("index") [Any] }, output { sym("lane") [IndexLaneSelection] } },
  constructor. store_fill [impl.store_fill] { input { sym("info") [sym("StoreFillInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_copy [impl.store_copy] { input { sym("info") [sym("StoreCopyInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_gather [impl.store_gather] { input { sym("info") [sym("StoreGatherInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_scatter [impl.store_scatter] { input { sym("info") [sym("StoreScatterInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_in_place_map [impl.store_in_place_map] { input { sym("op") [Any], sym("info") [sym("StoreInPlaceMapInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_map [impl.store_map] { input { sym("op") [Any], sym("info") [sym("StoreMapInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_cast [impl.store_cast] { input { sym("op") [Any], sym("info") [sym("StoreCastInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_compare [impl.store_compare] { input { sym("op") [Any], sym("info") [sym("StoreCompareInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_zip_map [impl.store_zip_map] { input { sym("op") [Any], sym("info") [sym("StoreZipMapInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. store_zip_compare [impl.store_zip_compare] { input { sym("op") [Any], sym("info") [sym("StoreZipCompareInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [StoreStencilSelection] } },
  constructor. scan_array [impl.scan_array] { input { sym("reduction") [Any], sym("info") [sym("ScanArrayInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [sym("ScanStencilSelection")] } },
  constructor. find_array [impl.find_array] { input { sym("op") [Any], sym("info") [sym("FindArrayInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [sym("FindStencilSelection")] } },
  constructor. partition_array [impl.partition_array] { input { sym("op") [Any], sym("info") [sym("PartitionArrayInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [sym("PartitionStencilSelection")] } },
  constructor. reduce_array [impl.reduce_array] { input { sym("info") [sym("ReduceArrayInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [ReduceStencilSelection] } },
  constructor. reduce_map [impl.reduce_map] { input { sym("op") [Any], sym("info") [sym("MapReduceInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [ReduceStencilSelection] } },
  constructor. reduce_zip [impl.reduce_zip] { input { sym("op") [Any], sym("info") [sym("ZipReduceInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [ReduceStencilSelection] } },
  constructor. reduce_count [impl.reduce_count] { input { sym("op") [Any], sym("info") [sym("CountInfo")], sym("args") [sym("StencilArgList")] }, output { sym("selection") [ReduceStencilSelection] } },
  constructor. store_stencil_plan [impl.store_stencil_plan] { input { sym("selection") [StoreStencilSelection] }, output { sym("plan") [sym("StoreStencilPlan")] } },
  constructor. store_stencil_no_plan [impl.store_stencil_no_plan] { input { sym("reason") [str] }, output { sym("plan") [sym("StoreStencilPlan")] } },
  constructor. reduce_stencil_plan [impl.reduce_stencil_plan] { input { sym("reduction") [Any], sym("selection") [ReduceStencilSelection] }, output { sym("plan") [sym("ReduceStencilPlan")] } },
  constructor. reduce_stencil_no_plan [impl.reduce_stencil_no_plan] { input { sym("reason") [str] }, output { sym("plan") [sym("ReduceStencilPlan")] } },

  relation. classify_expr {
    input { expr [StencilExprFact] },
    output { class [StencilClassFact] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. kernel_value {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (kernel_value)) * (P. expr.binding :present ()),
    },
    bind. inner {
      llisle.classify_expr { expr = P. expr.binding },
    },
    run { ret { class = V. inner.class } },
  },

  rule. load {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (load) },
    run {
      ret { class = load_class { lane = P. expr.lane, index = P. expr.index } },
    },
  },

  rule. fill {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (fill) },
    run {
      ret { class = fill_class { value = P. expr.value } },
    },
  },

  rule. unary_map {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (unary)) * (P. expr.op :present ()),
    },
    bind. inner {
      llisle.classify_expr { expr = P. expr.value },
    },
    when { V. inner.class.kind :eq (load) },
    run {
      ret {
        class = map_class {
          op = P. expr.op,
          lane = V. inner.class.lane,
          index = V. inner.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. cast_map {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (cast) },
    bind. inner {
      llisle.classify_expr { expr = P. expr.value },
    },
    when { V. inner.class.kind :eq (load) },
    run {
      ret {
        class = cast_class {
          op = P. expr.op,
          lane = V. inner.class.lane,
          index = V. inner.class.index,
          src_ty = P. expr.src_ty,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. cast_compare {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (cast) },
    bind. inner {
      llisle.classify_expr { expr = P. expr.value },
    },
    when { V. inner.class.kind :eq (compare) },
    run {
      ret {
        class = compare_class {
          pred = V. inner.class.pred,
          lane = V. inner.class.lane,
          index = V. inner.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. zip_map {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (binary)) * (P. expr.op :present ()),
    },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (load)) * (V. rhs.class.kind :eq (load)),
    },
    run {
      ret {
        class = zip_map_class {
          op = P. expr.op,
          lhs = V. lhs.class.lane,
          rhs = V. rhs.class.lane,
          lhs_index = V. lhs.class.index,
          rhs_index = V. rhs.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. binary_mul_identity_right {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (binary))
        * (P. expr.algebra :eq ("mul")),
    },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. rhs.class.kind :eq (fill)) * (V. rhs.class.const_int :eq (1)),
    },
    run { ret { class = V. lhs.class } },
  },

  rule. binary_mul_identity_left {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (binary))
        * (P. expr.algebra :eq ("mul")),
    },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (fill)) * (V. lhs.class.const_int :eq (1)),
    },
    run { ret { class = V. rhs.class } },
  },

  rule. binary_add_identity_right {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (binary))
        * (P. expr.algebra :eq ("add")),
    },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. rhs.class.kind :eq (fill)) * (V. rhs.class.const_int :eq (0)),
    },
    run { ret { class = V. lhs.class } },
  },

  rule. binary_add_identity_left {
    llisle.classify_expr { expr = P. expr },
    when {
      (P. expr.kind :eq (binary))
        * (P. expr.algebra :eq ("add")),
    },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (fill)) * (V. lhs.class.const_int :eq (0)),
    },
    run { ret { class = V. rhs.class } },
  },

  rule. compare_load_const {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (cmp) },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (load))
        * (V. rhs.class.kind :eq (fill))
        * (P. expr.op :has_const_pred (V. rhs.class.value, false)),
    },
    run {
      ret {
        class = compare_class {
          pred = pred_const { op = P. expr.op, value = V. rhs.class.value, const_on_left = false },
          lane = V. lhs.class.lane,
          index = V. lhs.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. compare_const_load {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (cmp) },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (fill))
        * (V. rhs.class.kind :eq (load))
        * (P. expr.op :has_const_pred (V. lhs.class.value, true)),
    },
    run {
      ret {
        class = compare_class {
          pred = pred_const { op = P. expr.op, value = V. lhs.class.value, const_on_left = true },
          lane = V. rhs.class.lane,
          index = V. rhs.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  rule. zip_compare {
    llisle.classify_expr { expr = P. expr },
    when { P. expr.kind :eq (cmp) },
    bind. lhs { llisle.classify_expr { expr = P. expr.lhs } },
    bind. rhs { llisle.classify_expr { expr = P. expr.rhs } },
    when {
      (V. lhs.class.kind :eq (load)) * (V. rhs.class.kind :eq (load)),
    },
    run {
      ret {
        class = zip_compare_class {
          cmp = P. expr.op,
          lhs = V. lhs.class.lane,
          rhs = V. rhs.class.lane,
          lhs_index = V. lhs.class.index,
          rhs_index = V. rhs.class.index,
          result_ty = P. expr.result_ty,
        },
      },
    },
  },

  relation. select_index_lane {
    input { class [StencilClassFact] },
    output { lane [IndexLaneSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. index_lane_load {
    llisle.select_index_lane { class = P. class },
    when { P. class.kind :eq (load) },
    run {
      ret {
        lane = index_lane {
          lane = P. class.lane,
          index = P. class.index,
        },
      },
    },
  },

  rule. index_lane_cast_load {
    llisle.select_index_lane { class = P. class },
    when { P. class.kind :eq (cast) },
    run {
      ret {
        lane = index_lane {
          lane = P. class.lane,
          index = P. class.index,
        },
      },
    },
  },

  relation. classify_stencil_type {
    input { ty [CodeType] },
    output { class [StencilTypeFact] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. stencil_type_int {
    llisle.classify_stencil_type { ty = P. ty },
    when { P. ty :is_int_type () },
    run { ret { class = type_class { kind = int, ty = P. ty } } },
  },

  rule. stencil_type_float {
    llisle.classify_stencil_type { ty = P. ty },
    when { P. ty :is_float_type () },
    run { ret { class = type_class { kind = float, ty = P. ty } } },
  },

  rule. stencil_type_index {
    llisle.classify_stencil_type { ty = P. ty },
    when { P. ty :is_index_type () },
    run { ret { class = type_class { kind = index, ty = P. ty } } },
  },

  rule. stencil_type_bool8 {
    llisle.classify_stencil_type { ty = P. ty },
    when { P. ty :is_bool8_type () },
    run { ret { class = type_class { kind = bool8, ty = P. ty } } },
  },

  relation. plan_store_stencil {
    input { ctx [sym("StoreStencilPlanInput")] },
    output { plan [sym("StoreStencilPlan")] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. store_plan_ready {
    llisle.plan_store_stencil { ctx = P. ctx },
    when {
      (P. ctx.planned :eq (true))
        * (P. ctx.returns_void :eq (true))
        * (P. ctx.counted_positive :eq (true))
        * (P. ctx.single_store :eq (true))
        * (P. ctx.dst_base_present :eq (true))
        * (P. ctx.class_ready :eq (true)),
    },
    bind. selected {
      llisle.select_store_stencil { ctx = P. ctx.selection_ctx },
    },
    run {
      ret {
        plan = sym("store_stencil_plan") {
          selection = V. selected.selection,
        },
      },
    },
  },

  rule. store_plan_not_ready {
    llisle.plan_store_stencil { ctx = P. ctx },
    when {
      P. ctx.plan_ready :eq (false),
    },
    run {
      ret {
        plan = store_stencil_no_plan {
          reason = P. ctx.reject_reason,
        },
      },
    },
  },

  relation. select_store_stencil {
    input { ctx [StoreStencilFact] },
    output { selection [StoreStencilSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. store_fill {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (fill))
        * (P. ctx.store_index_primary :eq (true)),
    },
    run {
      ret {
        selection = store_fill {
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.dst_elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            value = P. ctx.class.value,
            dst_topology = P. ctx.dst_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.start_expr, P. ctx.stop_expr, P. ctx.class.value_expr },
        },
      },
    },
  },

  rule. store_copy {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.elem_ty :same_type (P. ctx.dst_elem_ty)),
    },
    run {
      ret {
        selection = store_copy {
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            semantics = P. ctx.copy_semantics,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  relation. select_scan_stencil {
    input { ctx [sym("ScanStencilFact")] },
    output { selection [sym("ScanStencilSelection")] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. scan_array {
    llisle.select_scan_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.result_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.result_ty :same_type (P. ctx.dst_elem_ty))
        * (P. ctx.reduction_kind :reduction_supported (P. ctx.class.elem_ty, P. ctx.result_ty)),
    },
    run {
      ret {
        selection = scan_array {
          reduction = P. ctx.reduction,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.result_ty,
            init = P. ctx.init,
            mode = P. ctx.mode,
            dst = P. ctx.dst,
            array = P. ctx.class.src,
            dst_topology = P. ctx.dst_topology,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr, P. ctx.init_expr },
        },
      },
    },
  },

  relation. select_find_stencil {
    input { ctx [sym("FindStencilFact")] },
    output { selection [sym("FindStencilSelection")] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. find_array {
    llisle.select_find_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.not_found_minus_one :eq (true)),
    },
    run {
      ret {
        selection = find_array {
          op = P. ctx.pred,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            array = P. ctx.class.src,
            pred = P. ctx.pred,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  relation. select_partition_stencil {
    input { ctx [sym("PartitionStencilFact")] },
    output { selection [sym("PartitionStencilSelection")] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. partition_array {
    llisle.select_partition_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.elem_ty :same_type (P. ctx.dst_elem_ty)),
    },
    run {
      ret {
        selection = partition_array {
          op = P. ctx.pred,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            dst = P. ctx.dst,
            array = P. ctx.class.src,
            pred = P. ctx.pred,
            semantics = P. ctx.semantics,
            dst_topology = P. ctx.dst_topology,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_gather {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    bind. index_ty { llisle.classify_stencil_type { ty = P. ctx.class.index_lane.elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_lane.index_primary :eq (true))
        * (P. ctx.class.elem_ty :same_type (P. ctx.dst_elem_ty))
        * (P. ctx.class.index_lane.elem_ty :is_index_data_type ()),
    },
    run {
      ret {
        selection = store_gather {
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            index = P. ctx.class.index_lane.base,
            index_ty = P. ctx.class.index_lane.elem_ty,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
            index_topology = P. ctx.class.index_lane.topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.class.index_lane.base_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_scatter {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    bind. index_ty { llisle.classify_stencil_type { ty = P. ctx.store_index_lane.elem_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.store_index_lane.index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.elem_ty :same_type (P. ctx.dst_elem_ty))
        * (P. ctx.store_index_lane.elem_ty :is_index_data_type ()),
    },
    run {
      ret {
        selection = store_scatter {
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            index = P. ctx.store_index_lane.base,
            index_ty = P. ctx.store_index_lane.elem_ty,
            conflicts = P. ctx.scatter_conflicts,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
            index_topology = P. ctx.store_index_lane.topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.store_index_lane.base_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_in_place_map {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (map))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.same_src_dst_ty :eq (true))
        * (P. ctx.class.op :unary_supported (P. ctx.class.elem_ty))
        * (P. ctx.class.result_ty :same_type (P. ctx.class.elem_ty)),
    },
    run {
      ret {
        selection = store_in_place_map {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.class.result_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_map {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.class.result_ty } },
    when {
      (P. ctx.class.kind :eq (map))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.op :unary_supported (P. ctx.class.elem_ty))
        * (P. ctx.class.result_ty :same_type (P. ctx.dst_elem_ty)),
    },
    run {
      ret {
        selection = store_map {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.class.result_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_cast {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. src_ty { llisle.classify_stencil_type { ty = P. ctx.class.src_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (cast))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.result_ty :same_type (P. ctx.dst_elem_ty))
        * (P. ctx.class.op :cast_supported (P. ctx.class.src_ty, P. ctx.class.result_ty)),
    },
    run {
      ret {
        selection = store_cast {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.dst_elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            src_ty = P. ctx.class.src_ty,
            dst_ty = P. ctx.class.result_ty,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_compare {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (compare))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.dst_elem_ty :is_bool8_type ())
        * (P. ctx.class.result_ty :same_type (P. ctx.dst_elem_ty)),
    },
    run {
      ret {
        selection = store_compare {
          op = P. ctx.class.pred,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.class.elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            src = P. ctx.class.src,
            pred = P. ctx.class.pred,
            dst_topology = P. ctx.dst_topology,
            src_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_zip_map {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. lhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.lhs_ty } },
    bind. rhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.rhs_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.class.result_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (zip_map))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.lhs_index_primary :eq (true))
        * (P. ctx.class.rhs_index_primary :eq (true))
        * (P. ctx.class.lhs_ty :same_type (P. ctx.class.rhs_ty))
        * (P. ctx.class.lhs_ty :same_type (P. ctx.class.result_ty))
        * (P. ctx.class.result_ty :same_type (P. ctx.dst_elem_ty))
        * (P. ctx.class.op :binary_supported (P. ctx.class.result_ty)),
    },
    run {
      ret {
        selection = store_zip_map {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.dst_elem_ty,
            result_ty = P. ctx.class.result_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            lhs = P. ctx.class.lhs_base,
            rhs = P. ctx.class.rhs_base,
            lhs_ty = P. ctx.class.lhs_ty,
            rhs_ty = P. ctx.class.rhs_ty,
            dst_topology = P. ctx.dst_topology,
            lhs_topology = P. ctx.class.lhs_topology,
            rhs_topology = P. ctx.class.rhs_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.lhs_expr, P. ctx.class.rhs_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  rule. store_zip_compare {
    llisle.select_store_stencil { ctx = P. ctx },
    bind. lhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.lhs_ty } },
    bind. rhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.rhs_ty } },
    bind. dst_ty { llisle.classify_stencil_type { ty = P. ctx.dst_elem_ty } },
    when {
      (P. ctx.class.kind :eq (zip_compare))
        * (P. ctx.store_index_primary :eq (true))
        * (P. ctx.class.lhs_index_primary :eq (true))
        * (P. ctx.class.rhs_index_primary :eq (true))
        * (P. ctx.class.lhs_ty :same_type (P. ctx.class.rhs_ty))
        * (P. ctx.dst_elem_ty :is_bool8_type ()),
    },
    run {
      ret {
        selection = store_zip_compare {
          op = P. ctx.class.cmp,
          info = {
            step_num = P. ctx.step_num,
            elem_ty = P. ctx.dst_elem_ty,
            result_ty = P. ctx.dst_elem_ty,
            dst = P. ctx.dst,
            start = P. ctx.start,
            stop = P. ctx.stop,
            lhs = P. ctx.class.lhs_base,
            rhs = P. ctx.class.rhs_base,
            lhs_ty = P. ctx.class.lhs_ty,
            rhs_ty = P. ctx.class.rhs_ty,
            dst_topology = P. ctx.dst_topology,
            lhs_topology = P. ctx.class.lhs_topology,
            rhs_topology = P. ctx.class.rhs_topology,
          },
          args = { P. ctx.dst_expr, P. ctx.class.lhs_expr, P. ctx.class.rhs_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  relation. select_reduce_stencil {
    input { ctx [ReduceStencilFact] },
    output { selection [ReduceStencilSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. reduce_array {
    llisle.select_reduce_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.result_ty } },
    when {
      (P. ctx.class.kind :eq (load))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.reduction_kind :reduction_supported (P. ctx.class.elem_ty, P. ctx.result_ty)),
    },
    run {
      ret {
        selection = reduce_array {
          info = {
            step_num = P. ctx.step_num,
            result_ty = P. ctx.result_ty,
            init = P. ctx.init,
            array = P. ctx.class.src,
            elem_ty = P. ctx.class.elem_ty,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr, P. ctx.init_expr },
        },
      },
    },
  },

  rule. reduce_map {
    llisle.select_reduce_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. mapped_ty { llisle.classify_stencil_type { ty = P. ctx.class.result_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.result_ty } },
    when {
      (P. ctx.class.kind :eq (map))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.class.op :unary_supported (P. ctx.class.elem_ty))
        * (P. ctx.reduction_kind :reduction_supported (P. ctx.class.result_ty, P. ctx.result_ty)),
    },
    run {
      ret {
        selection = reduce_map {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            result_ty = P. ctx.result_ty,
            init = P. ctx.init,
            array = P. ctx.class.src,
            elem_ty = P. ctx.class.elem_ty,
            mapped_ty = P. ctx.class.result_ty,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr, P. ctx.init_expr },
        },
      },
    },
  },

  rule. reduce_zip {
    llisle.select_reduce_stencil { ctx = P. ctx },
    bind. lhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.lhs_ty } },
    bind. rhs_ty { llisle.classify_stencil_type { ty = P. ctx.class.rhs_ty } },
    bind. mapped_ty { llisle.classify_stencil_type { ty = P. ctx.class.result_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.result_ty } },
    when {
      (P. ctx.class.kind :eq (zip_map))
        * (P. ctx.class.lhs_index_primary :eq (true))
        * (P. ctx.class.rhs_index_primary :eq (true))
        * (P. ctx.class.lhs_ty :same_type (P. ctx.class.rhs_ty))
        * (P. ctx.class.lhs_ty :same_type (P. ctx.class.result_ty))
        * (P. ctx.class.op :binary_supported (P. ctx.class.result_ty))
        * (P. ctx.reduction_kind :reduction_supported (P. ctx.class.result_ty, P. ctx.result_ty)),
    },
    run {
      ret {
        selection = reduce_zip {
          op = P. ctx.class.op,
          info = {
            step_num = P. ctx.step_num,
            result_ty = P. ctx.result_ty,
            init = P. ctx.init,
            lhs = P. ctx.class.lhs_base,
            rhs = P. ctx.class.rhs_base,
            lhs_ty = P. ctx.class.lhs_ty,
            rhs_ty = P. ctx.class.rhs_ty,
            mapped_ty = P. ctx.class.result_ty,
            lhs_topology = P. ctx.class.lhs_topology,
            rhs_topology = P. ctx.class.rhs_topology,
          },
          args = { P. ctx.class.lhs_expr, P. ctx.class.rhs_expr, P. ctx.start_expr, P. ctx.stop_expr, P. ctx.init_expr },
        },
      },
    },
  },

  rule. reduce_count {
    llisle.select_reduce_stencil { ctx = P. ctx },
    bind. elem_ty { llisle.classify_stencil_type { ty = P. ctx.class.elem_ty } },
    bind. result_ty { llisle.classify_stencil_type { ty = P. ctx.result_ty } },
    when {
      (P. ctx.class.kind :eq (compare))
        * (P. ctx.class.index_primary :eq (true))
        * (P. ctx.reduction_add :eq (true))
        * (P. ctx.init_zero :eq (true))
        * (P. ctx.result_i32 :eq (true)),
    },
    run {
      ret {
        selection = reduce_count {
          op = P. ctx.class.pred,
          info = {
            step_num = P. ctx.step_num,
            result_ty = P. ctx.result_ty,
            init = P. ctx.init,
            array = P. ctx.class.src,
            elem_ty = P. ctx.class.elem_ty,
            pred = P. ctx.class.pred,
            array_topology = P. ctx.class.src_topology,
          },
          args = { P. ctx.class.src_expr, P. ctx.start_expr, P. ctx.stop_expr },
        },
      },
    },
  },

  relation. plan_reduce_stencil {
    input { ctx [sym("ReduceStencilPlanInput")] },
    output { plan [sym("ReduceStencilPlan")] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. reduce_plan_ready {
    llisle.plan_reduce_stencil { ctx = P. ctx },
    when {
      (P. ctx.planned :eq (true))
        * (P. ctx.result_reduction :eq (true))
        * (P. ctx.returns_reduction :eq (true))
        * (P. ctx.counted_positive :eq (true))
        * (P. ctx.class_ready :eq (true)),
    },
    bind. selected {
      llisle.select_reduce_stencil { ctx = P. ctx.selection_ctx },
    },
    run {
      ret {
        plan = sym("reduce_stencil_plan") {
          reduction = P. ctx.reduction,
          selection = V. selected.selection,
        },
      },
    },
  },

  rule. reduce_plan_not_ready {
    llisle.plan_reduce_stencil { ctx = P. ctx },
    when {
      P. ctx.plan_ready :eq (false),
    },
    run {
      ret {
        plan = reduce_stencil_no_plan {
          reason = P. ctx.reject_reason,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end

    local function stencil_unary_op(op)
        if op == Core.UnaryNeg then return Stencil.StencilUnaryNeg end
        if op == Core.UnaryBitNot then return Stencil.StencilUnaryBitNot end
        if op == Core.UnaryNot then return Stencil.StencilUnaryBoolNot end
        return nil
    end

    local function stencil_binary_op(op)
        if op == Core.BinAdd then return Stencil.StencilBinaryAdd end
        if op == Core.BinSub then return Stencil.StencilBinarySub end
        if op == Core.BinMul then return Stencil.StencilBinaryMul end
        if op == Core.BinBitAnd then return Stencil.StencilBinaryAnd end
        if op == Core.BinBitOr then return Stencil.StencilBinaryOr end
        if op == Core.BinBitXor then return Stencil.StencilBinaryXor end
        return nil
    end

    is_int_type = function(ty)
        return pvm.classof(ty) == Code.CodeTyInt
    end

    is_float_type = function(ty)
        return pvm.classof(ty) == Code.CodeTyFloat
    end

    is_index_type = function(ty)
        return ty == Code.CodeTyIndex
    end

    is_bool8_type = function(ty)
        return ty == Code.CodeTyBool8
    end

    local function is_scalar_type(ty)
        return is_int_type(ty) or is_float_type(ty) or is_index_type(ty) or is_bool8_type(ty)
    end

    same_type = function(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    is_index_data_type = function(ty)
        return is_int_type(ty) or is_index_type(ty)
    end

    local function supports_bitwise_ty(ty)
        return is_int_type(ty) or is_bool8_type(ty)
    end

    unary_supported = function(op, ty)
        if not is_scalar_type(ty) then return false end
        if op == Stencil.StencilUnaryBitNot then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilUnaryIdentity or op == Stencil.StencilUnaryNeg or op == Stencil.StencilUnaryBoolNot then return true end
        return false
    end

    binary_supported = function(op, ty)
        if not is_scalar_type(ty) then return false end
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilBinaryAdd or op == Stencil.StencilBinarySub or op == Stencil.StencilBinaryMul
            or op == Stencil.StencilBinaryMin or op == Stencil.StencilBinaryMax then
            return true
        end
        return false
    end

    reduction_supported = function(kind, elem_ty, result_ty)
        if not same_type(elem_ty, result_ty) then return false end
        if is_int_type(result_ty) then
            return kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionAnd or kind == Value.ReductionOr or kind == Value.ReductionXor
                or kind == Value.ReductionMin or kind == Value.ReductionMax
        end
        if is_float_type(result_ty) then
            return kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionMin or kind == Value.ReductionMax
        end
        return false
    end

    local function type_bits(ty)
        if is_int_type(ty) or is_float_type(ty) then return tonumber(ty.bits) end
        if is_bool8_type(ty) then return 8 end
        return nil
    end

    local function is_signed_int_type(ty)
        return is_int_type(ty) and ty.signedness == Code.CodeSigned
    end

    local function is_unsigned_int_type(ty)
        return is_int_type(ty) and ty.signedness == Code.CodeUnsigned
    end

    cast_supported = function(op, src_ty, dst_ty)
        if not is_scalar_type(src_ty) or not is_scalar_type(dst_ty) then return false end
        if op == Core.MachineCastIdentity then return same_type(src_ty, dst_ty) end
        if op == Core.MachineCastBitcast then return type_bits(src_ty) ~= nil and type_bits(src_ty) == type_bits(dst_ty) end
        if op == Core.MachineCastIreduce then return is_int_type(src_ty) and is_int_type(dst_ty) and type_bits(dst_ty) <= type_bits(src_ty) end
        if op == Core.MachineCastSextend or op == Core.MachineCastUextend then return is_int_type(src_ty) and is_int_type(dst_ty) and type_bits(dst_ty) >= type_bits(src_ty) end
        if op == Core.MachineCastFpromote then return is_float_type(src_ty) and is_float_type(dst_ty) and type_bits(dst_ty) >= type_bits(src_ty) end
        if op == Core.MachineCastFdemote then return is_float_type(src_ty) and is_float_type(dst_ty) and type_bits(dst_ty) <= type_bits(src_ty) end
        if op == Core.MachineCastSToF then return is_signed_int_type(src_ty) and is_float_type(dst_ty) end
        if op == Core.MachineCastUToF then return is_unsigned_int_type(src_ty) and is_float_type(dst_ty) end
        if op == Core.MachineCastFToS then return is_float_type(src_ty) and is_signed_int_type(dst_ty) end
        if op == Core.MachineCastFToU then return is_float_type(src_ty) and is_unsigned_int_type(dst_ty) end
        return false
    end

    predicate_from_cmp_const = function(op, cexpr, const_on_left)
        if pvm.classof(cexpr) ~= Value.ValueExprConst then return nil end
        if const_on_left then
            if op == Core.CmpLt then op = Core.CmpGt
            elseif op == Core.CmpLe then op = Core.CmpGe
            elseif op == Core.CmpGt then op = Core.CmpLt
            elseif op == Core.CmpGe then op = Core.CmpLe end
        end
        if op == Core.CmpEq then return Stencil.StencilPredEqConst(cexpr) end
        if op == Core.CmpNe then return Stencil.StencilPredNeConst(cexpr) end
        if op == Core.CmpLt then return Stencil.StencilPredLtConst(cexpr) end
        if op == Core.CmpLe then return Stencil.StencilPredLeConst(cexpr) end
        if op == Core.CmpGt then return Stencil.StencilPredGtConst(cexpr) end
        if op == Core.CmpGe then return Stencil.StencilPredGeConst(cexpr) end
        return nil
    end

    local expr_fact
    expr_fact = function(expr, bindings, seen)
        if expr == nil then return nil, "missing stencil expression" end
        seen = seen or {}
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprKernelValue then
            if seen[expr.value.text] then return nil, "cyclic kernel binding" end
            local binding = bindings and bindings[expr.value.text] or nil
            if binding == nil then return nil, "missing kernel binding " .. expr.value.text end
            local next_seen = {}
            for k, v in pairs(seen) do next_seen[k] = v end
            next_seen[expr.value.text] = true
            local fact, err = expr_fact(binding.expr, bindings, next_seen)
            if fact == nil then return nil, err end
            return { kind = "kernel_value", id = expr.value, binding = fact }, nil
        elseif cls == Kernel.KernelExprLaneLoad then
            return { kind = "load", lane = expr.lane, index = expr.index }, nil
        elseif cls == Kernel.KernelExprAlgebra then
            local v = expr.expr
            local vcls = pvm.classof(v)
            if vcls == Value.ValueExprConst then
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprValue then
                local kid = Kernel.KernelValueId("kval:" .. v.value.text)
                local binding = bindings and bindings[kid.text] or nil
                if binding ~= nil then
                    if seen[kid.text] then return nil, "cyclic kernel binding" end
                    local next_seen = {}
                    for k, x in pairs(seen) do next_seen[k] = x end
                    next_seen[kid.text] = true
                    local fact, err = expr_fact(binding.expr, bindings, next_seen)
                    if fact == nil then return nil, err end
                    return { kind = "kernel_value", id = kid, binding = fact }, nil
                end
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprUnary then
                local fact, err = expr_fact(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if fact == nil then return nil, err end
                return { kind = "unary", op = stencil_unary_op(v.op), raw_op = v.op, value = fact, result_ty = v.ty }, nil
            elseif vcls == Value.ValueExprCast then
                local fact, err = expr_fact(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if fact == nil then return nil, err end
                return { kind = "cast", op = v.op, value = fact, src_ty = v.from, result_ty = v.to }, nil
            elseif vcls == Value.ValueExprAdd or vcls == Value.ValueExprSub or vcls == Value.ValueExprMul then
                local lhs, lhs_err = expr_fact(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_err end
                local rhs, rhs_err = expr_fact(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_err end
                local bop = vcls == Value.ValueExprAdd and Core.BinAdd or vcls == Value.ValueExprSub and Core.BinSub or Core.BinMul
                local algebra = vcls == Value.ValueExprAdd and "add" or vcls == Value.ValueExprSub and "sub" or "mul"
                return { kind = "binary", algebra = algebra, op = stencil_binary_op(bop), raw_op = bop, lhs = lhs, rhs = rhs, result_ty = v.ty }, nil
            elseif vcls == Value.ValueExprCmp then
                local lhs, lhs_err = expr_fact(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_err end
                local rhs, rhs_err = expr_fact(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_err end
                return { kind = "cmp", op = v.op, lhs = lhs, rhs = rhs, result_ty = Code.CodeTyBool8 }, nil
            end
        end
        return nil, "unsupported store stencil expression"
    end

    impl.is_int_type = is_int_type
    impl.is_float_type = is_float_type
    impl.is_index_type = is_index_type
    impl.is_bool8_type = is_bool8_type
    impl.is_index_data_type = is_index_data_type
    impl.same_type = same_type
    impl.unary_supported = unary_supported
    impl.binary_supported = binary_supported
    impl.reduction_supported = reduction_supported
    impl.cast_supported = cast_supported

    local rules = build_rules()
    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine)

    function api.classify_expr(expr, bindings)
        local fact, err = expr_fact(expr, bindings or {})
        if fact == nil then return nil, err end
        return api:run("classify_expr", { expr = fact }, "class", "unsupported store stencil expression")
    end

    function api.classify_type(ty)
        return api:run("classify_stencil_type", { ty = ty }, "class", "unsupported stencil type")
    end

    local function store_plan_reject_reason(ctx, suffix)
        return ("store stencil is not ready: planned=%s returns_void=%s counted_positive=%s single_store=%s dst_base_present=%s class_ready=%s (%s)"):format(
            tostring(ctx and ctx.planned),
            tostring(ctx and ctx.returns_void),
            tostring(ctx and ctx.counted_positive),
            tostring(ctx and ctx.single_store),
            tostring(ctx and ctx.dst_base_present),
            tostring(ctx and ctx.class_ready),
            tostring(suffix or "no matching plan")
        )
    end

    local function reduce_plan_reject_reason(ctx, suffix)
        return ("reduction stencil is not ready: planned=%s result_reduction=%s returns_reduction=%s counted_positive=%s class_ready=%s (%s)"):format(
            tostring(ctx and ctx.planned),
            tostring(ctx and ctx.result_reduction),
            tostring(ctx and ctx.returns_reduction),
            tostring(ctx and ctx.counted_positive),
            tostring(ctx and ctx.class_ready),
            tostring(suffix or "no matching plan")
        )
    end

    local function copy_fields(ctx)
        local out = {}
        for k, v in pairs(ctx or {}) do out[k] = v end
        return out
    end

    function api.plan_store(ctx)
        local input = copy_fields(ctx)
        input.plan_ready = input.planned == true
            and input.returns_void == true
            and input.counted_positive == true
            and input.single_store == true
            and input.dst_base_present == true
            and input.class_ready == true
        input.reject_reason = store_plan_reject_reason(input)
        local plan, err = api:run("plan_store_stencil", { ctx = input }, "plan", "no matching plan")
        if plan == nil then return nil, store_plan_reject_reason(input, err) end
        if plan.kind == "no_plan" then return nil, plan.reason end
        return plan, nil
    end

    function api.plan_reduce(ctx)
        local input = copy_fields(ctx)
        input.plan_ready = input.planned == true
            and input.result_reduction == true
            and input.returns_reduction == true
            and input.counted_positive == true
            and input.class_ready == true
        input.reject_reason = reduce_plan_reject_reason(input)
        local plan, err = api:run("plan_reduce_stencil", { ctx = input }, "plan", "no matching plan")
        if plan == nil then return nil, reduce_plan_reject_reason(input, err) end
        if plan.kind == "no_plan" then return nil, plan.reason end
        return plan, nil
    end

    local function product_fields(decl, kind)
        for _, item in ipairs(decl and decl.body or {}) do
            if Llisle.cls(item) == "ProductSpec" and item.kind == kind then return item.fields or {} end
        end
        return nil
    end

    local function field_names(fields)
        local out = {}
        for i, field in ipairs(fields or {}) do out[i] = field.name end
        return out
    end

    function api.constructor(name)
        return engine.constructors[name]
    end

    function api.constructor_contract(name)
        local decl = engine.constructors[name]
        if decl == nil then return nil end
        return {
            name = decl.name,
            input = field_names(product_fields(decl, "input")),
            output = field_names(product_fields(decl, "output")),
            decl = decl,
        }
    end

    api.rules = rules
    api.engine = engine
    api.expr_fact = expr_fact

    T._lalin_api_cache.stencil_rules = api
    return api
end

return bind_context
