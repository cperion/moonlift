local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.tree_to_code_rules ~= nil then return T._lalin_api_cache.tree_to_code_rules end

    local lalin = require("lalin")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local Tr = T.LalinTree

    local Selection = llb.symbol("TreeToCodeDispatchSelection")
    local dispatch_selection = llb.symbol("dispatch_selection")
    local expr = llb.symbol("expr")
    local place = llb.symbol("place")
    local stmt = llb.symbol("stmt")
    local func = llb.symbol("func")
    local item = llb.symbol("item")
    local contract_fact = llb.symbol("contract_fact")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. dispatch_selection [build_selection],

  relation. select_expr_lowering {
    input { expr [Tr.Expr] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_place_lowering {
    input { place [Tr.Place] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_stmt_lowering {
    input { stmt [Tr.Stmt] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_func_lowering {
    input { func [Tr.Func] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_item_lowering {
    input { item [Tr.Item] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_contract_fact_lowering {
    input { contract_fact [Tr.ContractFact] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  rule. expr_lit { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprLit) }, run { ret { selection = dispatch_selection { kind = "lit" } } } },
  rule. expr_ref { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprRef) }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. expr_unary { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprUnary) }, run { ret { selection = dispatch_selection { kind = "unary" } } } },
  rule. expr_binary { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprBinary) }, run { ret { selection = dispatch_selection { kind = "binary" } } } },
  rule. expr_compare { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprCompare) }, run { ret { selection = dispatch_selection { kind = "compare" } } } },
  rule. expr_logic { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprLogic) }, run { ret { selection = dispatch_selection { kind = "logic" } } } },
  rule. expr_if { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprIf) }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. expr_switch { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprSwitch) }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. expr_control { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprControl) }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. expr_block { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprBlock) }, run { ret { selection = dispatch_selection { kind = "block" } } } },
  rule. expr_machine_cast { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprMachineCast) }, run { ret { selection = dispatch_selection { kind = "machine_cast" } } } },
  rule. expr_cast { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprCast) }, run { ret { selection = dispatch_selection { kind = "surface_cast" } } } },
  rule. expr_select { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprSelect) }, run { ret { selection = dispatch_selection { kind = "select" } } } },
  rule. expr_addr_of { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAddrOf) }, run { ret { selection = dispatch_selection { kind = "addr_of" } } } },
  rule. expr_intrinsic { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprIntrinsic) }, run { ret { selection = dispatch_selection { kind = "intrinsic" } } } },
  rule. expr_agg { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAgg) }, run { ret { selection = dispatch_selection { kind = "agg" } } } },
  rule. expr_array { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprArray) }, run { ret { selection = dispatch_selection { kind = "array" } } } },
  rule. expr_view { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprView) }, run { ret { selection = dispatch_selection { kind = "view" } } } },
  rule. expr_len { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprLen) }, run { ret { selection = dispatch_selection { kind = "len" } } } },
  rule. expr_sizeof { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprSizeOf) }, run { ret { selection = dispatch_selection { kind = "sizeof" } } } },
  rule. expr_alignof { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAlignOf) }, run { ret { selection = dispatch_selection { kind = "alignof" } } } },
  rule. expr_is_null { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprIsNull) }, run { ret { selection = dispatch_selection { kind = "is_null" } } } },
  rule. expr_call { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprCall) }, run { ret { selection = dispatch_selection { kind = "call" } } } },
  rule. expr_deref { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprDeref) }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. expr_field { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprField) }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. expr_index { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprIndex) }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. expr_load { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprLoad) }, run { ret { selection = dispatch_selection { kind = "load" } } } },
  rule. expr_atomic_load { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAtomicLoad) }, run { ret { selection = dispatch_selection { kind = "atomic_load" } } } },
  rule. expr_atomic_rmw { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAtomicRmw) }, run { ret { selection = dispatch_selection { kind = "atomic_rmw" } } } },
  rule. expr_atomic_cas { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprAtomicCas) }, run { ret { selection = dispatch_selection { kind = "atomic_cas" } } } },
  rule. expr_ctor { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprCtor) }, run { ret { selection = dispatch_selection { kind = "ctor" } } } },
  rule. expr_null { llisle.select_expr_lowering { expr = P. expr }, when { P. expr :is (Tr.ExprNull) }, run { ret { selection = dispatch_selection { kind = "null" } } } },

  rule. place_ref { llisle.select_place_lowering { place = P. place }, when { P. place :is (Tr.PlaceRef) }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. place_deref { llisle.select_place_lowering { place = P. place }, when { P. place :is (Tr.PlaceDeref) }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. place_field { llisle.select_place_lowering { place = P. place }, when { P. place :is (Tr.PlaceField) }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. place_index { llisle.select_place_lowering { place = P. place }, when { P. place :is (Tr.PlaceIndex) }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. place_dot { llisle.select_place_lowering { place = P. place }, when { P. place :is (Tr.PlaceDot) }, run { ret { selection = dispatch_selection { kind = "dot" } } } },

  rule. stmt_let { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtLet) }, run { ret { selection = dispatch_selection { kind = "let" } } } },
  rule. stmt_var { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtVar) }, run { ret { selection = dispatch_selection { kind = "var" } } } },
  rule. stmt_set { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtSet) }, run { ret { selection = dispatch_selection { kind = "set" } } } },
  rule. stmt_atomic_store { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtAtomicStore) }, run { ret { selection = dispatch_selection { kind = "atomic_store" } } } },
  rule. stmt_atomic_fence { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtAtomicFence) }, run { ret { selection = dispatch_selection { kind = "atomic_fence" } } } },
  rule. stmt_expr { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtExpr) }, run { ret { selection = dispatch_selection { kind = "expr" } } } },
  rule. stmt_if { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtIf) }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. stmt_switch { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtSwitch) }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. stmt_control { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtControl) }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. stmt_jump { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtJump) }, run { ret { selection = dispatch_selection { kind = "jump" } } } },
  rule. stmt_jump_cont { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtJumpCont) }, run { ret { selection = dispatch_selection { kind = "jump_cont" } } } },
  rule. stmt_yield_value { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtYieldValue) }, run { ret { selection = dispatch_selection { kind = "yield_value" } } } },
  rule. stmt_yield_void { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtYieldVoid) }, run { ret { selection = dispatch_selection { kind = "yield_void" } } } },
  rule. stmt_return_value { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtReturnValue) }, run { ret { selection = dispatch_selection { kind = "return_value" } } } },
  rule. stmt_return_void { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtReturnVoid) }, run { ret { selection = dispatch_selection { kind = "return_void" } } } },
  rule. stmt_trap { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtTrap) }, run { ret { selection = dispatch_selection { kind = "trap" } } } },
  rule. stmt_assert { llisle.select_stmt_lowering { stmt = P. stmt }, when { P. stmt :is (Tr.StmtAssert) }, run { ret { selection = dispatch_selection { kind = "assert" } } } },

  rule. func_local { llisle.select_func_lowering { func = P. func }, when { P. func :is (Tr.FuncLocal) }, run { ret { selection = dispatch_selection { kind = "local" } } } },
  rule. func_export { llisle.select_func_lowering { func = P. func }, when { P. func :is (Tr.FuncExport) }, run { ret { selection = dispatch_selection { kind = "export" } } } },
  rule. func_local_contract { llisle.select_func_lowering { func = P. func }, when { P. func :is (Tr.FuncLocalContract) }, run { ret { selection = dispatch_selection { kind = "local_contract" } } } },
  rule. func_export_contract { llisle.select_func_lowering { func = P. func }, when { P. func :is (Tr.FuncExportContract) }, run { ret { selection = dispatch_selection { kind = "export_contract" } } } },

  rule. item_func { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemFunc) }, run { ret { selection = dispatch_selection { kind = "func" } } } },
  rule. item_data { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemData) }, run { ret { selection = dispatch_selection { kind = "data" } } } },
  rule. item_const { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemConst) }, run { ret { selection = dispatch_selection { kind = "const" } } } },
  rule. item_static { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemStatic) }, run { ret { selection = dispatch_selection { kind = "static" } } } },
  rule. item_extern { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemExtern) }, run { ret { selection = dispatch_selection { kind = "extern" } } } },
  rule. item_type { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemType) }, run { ret { selection = dispatch_selection { kind = "type" } } } },
  rule. item_import { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemImport) }, run { ret { selection = dispatch_selection { kind = "import" } } } },
  rule. item_region_frag { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemRegionFrag) }, run { ret { selection = dispatch_selection { kind = "region_frag" } } } },
  rule. item_expr_frag { llisle.select_item_lowering { item = P. item }, when { P. item :is (Tr.ItemExprFrag) }, run { ret { selection = dispatch_selection { kind = "expr_frag" } } } },

  rule. contract_fact_bounds { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactBounds) }, run { ret { selection = dispatch_selection { kind = "bounds" } } } },
  rule. contract_fact_window_bounds { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactWindowBounds) }, run { ret { selection = dispatch_selection { kind = "window_bounds" } } } },
  rule. contract_fact_disjoint { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactDisjoint) }, run { ret { selection = dispatch_selection { kind = "disjoint" } } } },
  rule. contract_fact_same_len { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactSameLen) }, run { ret { selection = dispatch_selection { kind = "same_len" } } } },
  rule. contract_fact_soa_component { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactSoAComponent) }, run { ret { selection = dispatch_selection { kind = "soa_component" } } } },
  rule. contract_fact_noalias { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactNoAlias) }, run { ret { selection = dispatch_selection { kind = "noalias" } } } },
  rule. contract_fact_readonly { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactReadonly) }, run { ret { selection = dispatch_selection { kind = "readonly" } } } },
  rule. contract_fact_writeonly { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactWriteonly) }, run { ret { selection = dispatch_selection { kind = "writeonly" } } } },
  rule. contract_fact_invalidate { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactInvalidate) }, run { ret { selection = dispatch_selection { kind = "invalidate" } } } },
  rule. contract_fact_preserve { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactPreserve) }, run { ret { selection = dispatch_selection { kind = "preserve" } } } },
  rule. contract_fact_rejected { llisle.select_contract_fact_lowering { contract_fact = P. contract_fact }, when { P. contract_fact :is (Tr.ContractFactRejected) }, run { ret { selection = dispatch_selection { kind = "rejected" } } } },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()
    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine)

    T._lalin_api_cache.tree_to_code_rules = api
    return api
end

return bind_context
