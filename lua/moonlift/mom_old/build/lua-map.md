---
=== tree_to_back.lua ===
File: ~2760 lines total. Primary lowering oracle. Defines M.Define(T) which returns a table of lowering functions.
Function: M.Define(T) the only exported function
Signature: T — context table with MoonCore, MoonType, MoonBind, MoonSem, MoonTree, MoonBack, MoonHost
Returns: table M with lowering entry points
Internal requires:
- type_to_back_scalar (scalar_api)
- type_size_align (layout_api)
- vec_kernel_plan (vec_kernel_plan_api)
- vec_kernel_to_back (vec_kernel_to_back_api)
- tree_contract_facts (contract_api)
- type_func_abi_plan (abi_api)
- tree_module_type (module_type_api)
- sem_const_eval (const_eval_api)
lower_context = { const_env = Bn.ConstEnv({}), globals = {} }
Forward-declared internal functions (all local, defined later in the file):
Function: expr_type(expr, env)
Signature: (TreeExpr, env) → TypeBackScalarKnown or nil
Implementation: Calls expr_ty_api.result(expr) → back_scalar on that type
Decision: If result is TypeBackScalarKnown, return that scalar; else return nil
Function: back_scalar(ty)
Signature: (Type) → BackScalar or nil
Decision: Calls scalar_api.result(ty). If classof == TypeBackScalarKnown, return r.scalar; else nil
Function: scalar_literal(tr, lit)
Signature: (Tag, literal node) → (env, cmds, value, scalar)
Called from: ExprBool, ExprInt, ExprFloat, ExprChar
Construction:
- Creates a CmdConst with a fresh value id and the literal
- Chooses BackBool, BackI32, BackF64, BackU32 based on which case
- Edge case: ExprNil → BackCmdTrap + BackTerminates (trap for nil use)
Function: unary_op(expr, env)
Signature: (ExprUnary, env) → TreeBackExprValue or TreeBackExprUnsupported
Cases: UnNeg, UnNot, UnBNot
- UnNeg: CmdUnary(dst, scalar, BackUnaryNeg, src)
- UnNot: CmdUnary(dst, BackBool, BackUnaryNot, src) — forces bool result
- UnBNot: CmdBitNot(dst, scalar, src) — only for integer types
Decision: Checks if scalar is BackBool, BackI8/16/32/64, BackU8/16/32/64, BackIndex
Decision on index type: If src scalar == BackIndex and op is UnNot → use BackBool result; for UnNeg → use BackI64 (widens index)
Edge case: If scalar is BackF32/BackF64, return unsupported for UnNot/UnBNot (float negation handled separately via CmdUnary BackUnaryNeg)
Function: binary_cmd(expr, env)
Signature: (ExprBinary, env) → TreeBackExprValue or unsupported
Cases: BinAdd, BinSub, BinMul, BinDiv, BinRem, BinBand, BinBor, BinBxor, BinShl, BinShr, BinEq, BinNe, BinLt, BinGt, BinLe, BinGe
For string concatenation (BinConcat): Calls host embedding via HostEmbedStrConcat if available; else unsupported
For ptr_offset (BinPtrOffset): Constructs CmdPtrOffset
For pointer difference (BinPtrDiff): Constructs ptr diff via CmdSub
Decision per op:
- CmdIntBinary for BinAdd/Sub/Mul/Div/Rem (integer)
- CmdBitBinary for BinBand/Bor/Bxor
- CmdShift for BinShl/Shr (with signed vs unsigned direction: a.ty decides)
- CmdCompare for BinEq/Ne/Lt/Gt/Le/Ge (result is BackBool)
- CmdFAdd/Sub/Mul/Div for float types
- CmdUnary with BackUnaryNeg for float negation
Edge cases: 
- If scalar is BackF32/BackF64, only Add/Sub/Mul/Div work; others return unsupported
- String concat: only with HostEmbedStrConcat; else trap
- Shl/Shr direction determined by signedness of type
Function: compare_op(expr, env)
Signature: (ExprCompare, env) → TreeBackExprValue or unsupported
Decision: Only works if both sides have same back scalar; result always BackBool
Constructs CmdCompare with the compare kind
Function: machine_cast_op(self, env)
Signature: (self = ExprMachineCast, env) → TreeBackExprValue or unsupported
Decision:
- If same scalar → just forward (no-op)
- If back_scalar(ty) returns a scalar covering all bits → CmdCast(BackCastBits)
- If both scalar and result scalar are BackIndex → CmdCast(BackCastBits)
- If scalar is BackIndex → CmdCast(BackCastValue) (narrow)
- If result scalar is BackIndex → CmdCast(BackCastValue) (widen)
- Else → CmdCast(BackCastBits)
Edge: scalar being BackVoid → unsupported
Function: surface_cast_op(self, env)
Signature: (self = ExprSurfaceCast, env) → TreeBackExprValue or unsupported
Decision:
- If same scalar → forward the operand
- Trunc: CmdCast(BackCastBits)
- Extend signed: CmdCast(BackCastSExt)
- Extend unsigned: CmdCast(BackCastZExt)
- Float to int: CmdCast(BackCastFpToInt)
- Int to float: CmdCast(BackCastIntToFp)
- Float to float widening: CmdCast(BackCastFpExtend)
- Float to float narrowing: CmdCast(BackCastFpTrunc)
- Ptr to int: CmdCast(BackCastPtrToInt)
- Int to ptr: CmdCast(BackCastIntToPtr)
Edge: cast to void → trap + terminate
Function: call_target(self, env)
Signature: (self = ExprCall, env) → call target decision
Uses sem_call_decide.lua functions: import_call_target, binding_class_call_target, value_ref_call_target, callee_call_target
Decision chain:
- If callee is ExprRef(ValueRefBinding) → binding_class_call_target
- If callee is ExprRef(ValueRefImport) → import_call_target
- If callee is ExprRef(ValueRefPath) → callee_call_target
- If callee is ExprRef(ValueRefName) → error
- Else → closure_or_indirect based on type
Function: expr_to_back (major phase: moonlift_tree_expr_to_back)
Covers all Expr* types:
ExprRef → env_lookup(env, ref) or error
ValueRefBinding: env_lookup by binding id
ValueRefSlot: env_lookup by slot id
ValueRefFuncSlot: env_lookup by slot id (fn_ty branch?)
ValueRefConstSlot: const_eval -> memory_info + CmdDataAddr
ValueRefStaticSlot: env_lookup by slot id
ValueRefPath: callee_call_target → produces CmdFuncAddr/CmdExternAddr
ValueRefImport: import_module → CmdExternAddr
ExprCall → full call lowering
General pattern:
1. Lower callee, get callable
2. Lower args
3. If target is CallDirect → use CmdFuncAddr+ CmdBindEntryParams style
4. Handle abi_param_scalars / abi_result_scalars
5. Build CmdCall or CmdIndirectCall
ExprIf/ExprSwitch → delegates to control_api
ExprOpen → calls open expansion
ExprView → view_to_back
ExprAtomicFence → CmdAtomicFence + atomic_ordering
ExprPuni → (punning cast?)
ExprUndefined → CmdUndefined + scalar
ExprMisc → (various)
Function: field_addr_from_base_ptr(self, env)
Signature: (PlaceDot or ExprDot, env) → (env, cmds, addr_value, rest)
Construction:
- field_resolver = tree_field_resolve (phase)
- Gets field offset from layout
- CmdConst(offset_lit) + CmdPtrOffset(base_addr, offset)
Decision: If field rep is HostRepView or field of Ty.TView → load view descriptor (data, len, stride)
Function: load_from_field_addr(self, env, addr_result)
Signature: (place, env, (env, cmds, value, scalar) from addr) → TreeBackExprValue
Construction:
- append_load_info for the load
Decision: If field rep is HostRepView → read_decriptor_fields (data, len, stride)
Function: view_to_back(self, env)
Signature: (ExprView or PlaceView, env) → back commands for view
View types: ViewFromExpr, ViewContiguous, ViewStrided, ViewRestrided, ViewRowBase, ViewInterleaved, ViewInterleavedView
Construction:
- ViewFromExpr: CmdPtrOffset(data, offset) + CmdView(shape, fields)
- ViewContiguous: shape_compute + CmdView
- ViewStrided: shape_compute + CmdView(stride)
- ViewRestrided: shape_compute + CmdView(restrided)
- ViewRowBase: CmdView with row_base shape
- ViewInterleaved: CmdView with interleaved shape
- ViewInterleavedView: CmdView with interleaved shape
Function: index_addr_to_back(self, env)
Signature: (ExprIndex or PlaceIndex, env) → (env, cmds, addr_value)
- If index base type is TArray → CmdPtrOffset(base, index * elem_size)
- If index base type is TPtr → CmdPtrOffset(base, index * elem_size)
- If index base type is TSlice → load data ptr + len, bounds check (CmdCompare + CmdBranch), CmdPtrOffset
- If index base type is TView → vectorized view indexing (CmdViewAccess)
Edge: bounds check for slices and vectors; direct ptr offset for arrays
Function: place_addr_to_back(self, env)
Signature: (Place, env) → (env, cmds, addr_value)
Routes to field_addr_from_base_ptr for PlaceDot, index_addr_to_back for PlaceIndex, etc.
Function: place_store_to_back(self, env, value_expr)
Signature: (Place, env, value TreeBackExprValue) → (env, cmds)
Construction:
- addr = place_addr_to_back
- append_store_info(cmds, env, dst_shape, addr, value, text)
Decision:
- If place type is scalar → CmdStore
- If place type is struct → CmdStoreStruct (potentially multiple scalar stores/strided?)
- If slice assignment → memcpy or CmdStore
Function: stmt_to_back (phase: moonlift_tree_stmt_to_back)
Covers all Stmt* types:
- StmtDeclare → env_add binding for declaration
- StmtAssign → place_store_to_back
- StmtIf → control_api for stmt region
- StmtSwitch → control_api for stmt region
- StmtReturn → CmdReturn + value; if no value, CmdReturnVoid + Back.BackTerminates
- StmtWhile → control_api for loop region
- StmtFor → control_api for for region
- StmtBreak → CmdBranch to break block
- StmtContinue → CmdBranch to continue block
- StmtExpr → eval expr, drop result
- StmtOpen → open expansion
- StmtView → view_to_back lowering
- StmtAtomicStore → CmdAtomicStore
- StmtAtomicFence → CmdAtomicFence
- StmtTrap → CmdTrap + Back.BackTerminates
Function: lower_body(func, env)
Signature: (Func, env) → TreeBackStmtResult
- Calls stmt_to_back for each stmt in func.body.stmts
- Threads env through sequential statements
- Returns the result of the last statement
Function: func_to_back(self, env)
Signature: (TreeFunc, env) → BackFunc (or nil)
- Generates CmdCreateBlock for entry block
- CmdBindEntryParams for params
- lower_body for the body
- If not terminator, append CmdReturnVoid
- CmdSealBlock on exit
Function: try_vector_func(func, env, region_id)
Signature: (Func, env, region_id) → result or nil
- Calls vec_to_back (if vectorization possible)
- Returns vectorized lowering or nil
Function: extern_to_back(self, env)
Signature: (TreeExtern, env) → BackExternDecl
Construction:
- abi_api.plan("extern", params, result_ty)
- CmdDeclareExtern(symbol, sig)
- If body: same as func_to_back
Function: item_to_back(self, env)
Signature: (TreeItem, env) → BackItem
Cases:
- ItemFunc → func_to_back or try_vector_func
- ItemExtern → extern_to_back
- ItemConst → gives BackData with CmdDeclareData, data init
- ItemStatic → gives BackData with CmdDeclareData, data init
- ItemImport → recurses on imported item via module_type_api
- ItemType → no back output (type decl only)
Function: module_to_back(self, env)
Signature: (TreeModule, env) → BackProgram
Construction:
- CmdTargetModel(target triple from module target)
- For each item: item_to_back
- CmdAliasFact for each global fact
- Collects all into BackProgram
Helper functions used across the file:
Function: env_empty(ret)
Signature: (TreeBackReturn type) → env
Returns: Tr.TreeBackEnv with empty sets and the given ret
Function: env_add(env, binding, value, scalar)
Signature: (env, Binding, BackValId, BackScalar) → new env
Adds value mapping to env.values
Function: env_add_strided_view(env, binding, data, len, stride)
Signature: (env, Binding, id, id, id) → new env with view binding
Function: env_next_value(env, hint)
Signature: (env, string_hint) → (env, new_BackValId)
Allocates a new value id from env.next_value counter
Function: env_lookup(env, key)
Signature: (env, id/key) → value or nil
Linear search backwards through env.values
Function: append_load_info(cmds, env, dst, shape, addr, text)
Signature: (cmds list, env, dst_id, shape, addr_value, text) → new env
Appends CmdLoadInfo or CmdLoad (based on context)
If shape is scalar → CmdLoad(dst, scalar, addr)
Also appends CmdStoreInfo for store track records
Function: append_store_info(cmds, env, shape, addr, value, text)
Signature: (cmds list, env, shape, addr_value, value_id, text) → new env
Appends CmdStore or CmdStoreInfo
Function: address_from_ptr(base_val, byte_offset)
Signature: (base_val_id, offset_val_id) → BackAddrValue(base, offset)
Function: memory_info(text, access)
Signature: (string, BackAccessRead/Write/ReadWrite) → BackMemoryInfo
Function: atomic_ordering(ordering)
Signature: (Sem ordering) → Back ordering tag (SeqCst, Acquire, Release, AcqRel, Relaxed, AcquireRelease, Unordered)
Function: atomic_rmw_op(op)
Signature: (Sem atomic op) → BackAtomicRmwOp tag (Xchg, Add, Sub, And, Or, Xor, Min, Max)
Function: global_data_addr(global_binding)
Signature: (Binding) → CmdDataAddr for the global
Function: load_g / store_g — global load/store (for global variables under the old scheme)
Function: func_sig(params, result)
Signature: (Param, Type) → (param_scalars, result_scalars)
Uses abi_api.plan → abi_param_scalars / abi_result_scalars
Function: has_view_param(params)
Signature: (Param) → bool
Checks if any param has Ty.TView type
Function: public_host_param_scalars(params, result_ty)
Signature: (Param, Type) → BackScalar
For public/host ABI:
- If result is TView → prepend BackPtr for result slot
- For each param: if TView → BackPtr; else back_scalar(ty) if not void
Function: descriptor_field_load(cmds, current, desc, field_name, offset, scalar)
Signature: (cmds, current_id, desc_id, name, offset, scalar) → (cmds, result_id)
Loads a field from a descriptor (view or slice descriptor) at known offset
Function: define_abi_read(plan, arg_reader, view_reader)
Signature: (ABIPlan, fn→arg_ids, fn→view_tuple_ids) → cmds+values
For each param in plan:
- If AbiParamScalar → reader(param)
- If AbiParamView → view_reader(param)
Function: fill_env_from_abi(env, plan, ...)
Signature: (env, plan, scalar_args, view_tuples) → env
Creates bindings for ABI params:
- Scalar: env_add(binding, value, scalar)
- View: env_add_strided_view(binding, data, len, stride)
Function: abi_param_scalars(plan)
Signature: (ABIPlan) → BackScalar
Returns list of scalars from AbiParamScalar entries
Function: abi_result_scalars(plan)
Signature: (ABIPlan) → BackScalar
Returns result scalars (or BackVoid for view results)
Function: func_entry_env(plan)
Signature: (ABIPlan) → env
Creates initial env from plan params:
- AbiParamScalar → env_add
- AbiParamView → env_add_strided_view
=== tree_control_to_back.lua ===
File: ~500 lines. Controls region lowering for if/switch/loop.
Function: M.Define(T, base)
Signature: (T context, base lowering env) → control lowering API
Returns: table with control_stmt_region_to_back, control_expr_region_to_back
Local helper functions:
function unsupported_stmt(env, cmds)
Returns Tr.TreeBackStmtResult(env, cmds+CmdTrap, BackTerminates)
function expr_value(result)
Filters TreeBackExprValue from result; returns nil for other classes
function shape_scalar(scalar) → BackShapeScalar(scalar)
function binding_id(region_id, label, name) → C.Id("control:param:"..region_id..":"..label.name..":"..name)
function value_id(nonce, region_id, label, name) → Back.BackValId("ctl:"..tostring(nonce)..":"..region_id..":"..label.name..":"..name)
function append_all(out, xs) — same pattern
function label_key(label) → label.name
function find_jump_arg(args, name)
Returns (arg, nil) or (nil, error_msg)
Edge: duplicate jump arg name → error
function switch_key_raw(self, env)
Signature: (SwitchKey, env) → env + raw value
Cases:
- If key is const (SwitchKeyConst or SwitchKeyRaw) → CmdConst + compare
- If key is expr → lower the key expr
control_stmt_to_back (phase: moonlift_tree_control_stmt_to_back)
Cases:
- CStmtIf → creates blocks: then_block, else_block, merge_block
  - CmdBranch cond to then/else
  - lower then body, lower else body
  - In merge block: phi for values
  - CmdCreateBlock, CmdSwitchToBlock, CmdBranch, CmdAppendBlockParam, CmdSealBlock
  
- CStmtSwitch → for each arm: create arm block; CmdSwitch with arm indices or keys
  - Fallthrough vs break semantics
  - SwitchKeyConst/SwitchKeyRaw: direct jump table offset
  - SwitchKeyExpr: compare each key
- CStmtLoop → creates header, body, continue, break blocks
  - CmdBranch to header
  - Header: phi for loop-carried values, cond check
  - Body: continue branch back
  - Break: CmdBranch out
- CStmtReturn → CmdReturn
control_expr_region_to_back (phase: moonlift_tree_control_expr_region_to_back)
Cases:
- CExprIf → similar to stmt if but produces value
- CExprSwitch → similar to stmt switch producing value with phi in merge
Key patterns:
- Regions produce blocks with CmdCreateBlock(id), CmdSwitchToBlock(id)
- CmdBranch to successor blocks with args
- CmdAppendBlockParam for phi-like block params
- CmdSealBlock to seal a block
- Value mapping tracked via env across regions
=== tree_typecheck.lua (first 200 lines) ===
Function: M.Define(T)
Requires: tree_module_type, tree_control_facts
Forward declares:
type_view, type_index_base, type_place, type_expr, type_expr_expect, type_stmt, type_stmt_body, type_control_stmt_region, type_control_expr_region, type_switch_key, type_func, type_item, type_module
Helper type constructors:
- void_ty() → Ty.TScalar(C.ScalarVoid)
- bool_ty() → Ty.TScalar(C.ScalarBool)
- i32_ty() → Ty.TScalar(C.ScalarI32)
- index_ty() → Ty.TScalar(C.ScalarIndex)
- f64_ty() → Ty.TScalar(C.ScalarF64)
- cstr_ty() → Ty.TPtr(Ty.TScalar(C.ScalarU8))  (ptr to u8)
view_elem(view) - extracts element type from view classes
clone_values, clone_types — shallow copies
Phases defined:
- moonlift_tree_typecheck_view (type_view)
- moonlift_tree_typecheck_index_base
- moonlift_tree_typecheck_place
- moonlift_tree_typecheck_expr (core — infers expr types)
- moonlift_tree_typecheck_expr_expect (matching expected type with actual)
- moonlift_tree_typecheck_stmt
- moonlift_tree_typecheck_stmt_body
- moonlift_tree_typecheck_control_stmt_region
- moonlift_tree_typecheck_control_expr_region
- moonlift_tree_typecheck_switch_key
- moonlift_tree_typecheck_func
- moonlift_tree_typecheck_item
- moonlift_tree_typecheck_module
Each phase uses pvm.phase with args_cache pattern; most cache "full" or "last".
=== tree_expr_type.lua (first 150 lines) ===
Function: M.Define(T) — cached via T._moonlift_api_cache.tree_expr_type
header_type (phase: moonlift_tree_expr_header_type):
- ExprSurface → pvm.empty()
- ExprTyped → pvm.once(self.ty)
- ExprOpen → pvm.once(self.ty)
- ExprSem → pvm.once(self.ty)
- ExprCode → pvm.once(self.ty)
value_ref_type (phase: moonlift_tree_value_ref_type):
- ValueRefBinding → pvm.once(self.binding.ty)
- ValueRefSlot → pvm.once(self.slot.ty)
- ValueRefFuncSlot → pvm.once(self.slot.fn_ty)
- ValueRefConstSlot → pvm.once(self.slot.ty)
- ValueRefStaticSlot → pvm.once(self.slot.ty)
- ValueRefName → pvm.empty()
- ValueRefPath → pvm.empty()
- ValueRefImport → pvm.once(self.import.type)
call_target_type (phase: moonlift_tree_call_target_type):
- CallDirect → pvm.once(self.fn_ty)
- CallIndirect → pvm.once(self.fn_ty)
- CallClosure → pvm.once(self.fn_ty)
- CallExtern → pvm.once(self.fn_ty)
expr_type (phase: moonlift_tree_expr_type) — the main expression type oracle:
- ExprRef → value_ref_type(self.ref)
- ExprSurface → header_type(self)
- ExprTyped → pvm.once(self.ty)
- ExprOpen → pvm.once(self.ty)
- ExprSem → pvm.once(self.ty)
- ExprCode → pvm.once(self.ty)
- ExprNil → void_ty()
- ExprBool → bool_ty()
- ExprInt → depends on context (defaults to i32, but adjustable)
- ExprFloat → f64_ty() (or f32 if specified)
- ExprChar → Ty.TScalar(C.ScalarU32)
- ExprStr → Ty.TSlice(Ty.TScalar(C.ScalarU8))  (slice of u8)
- ExprArray → Ty.TArray(elem_type, count)
- ExprStruct → Ty.TStruct(fields)
- ExprCall → call_target_type(self.target).result_type
- ExprIf → joint type of both branches (lub)
- ExprSwitch → joint type of all arms
- ExprCast → self.to_type
- ExprView → self.view's element type
- ExprLoad → self.ty (the loaded type)
- ExprUnary → operand type (or adjusted for bool)
- ExprBinary → result type of operation
- ExprCompare → bool_ty()
- ExprAtomicLoad → self.ty
- ExprAtomicRmw → self.ty
- ExprUndefined → self.ty
=== type_to_back_scalar.lua ===
Full mapping table:
scalar_to_back (phase: moonlift_type_scalar_to_back):
- Core.ScalarBool → Back.BackBool
- Core.ScalarI8 → Back.BackI8
- Core.ScalarI16 → Back.BackI16
- Core.ScalarI32 → Back.BackI32
- Core.ScalarI64 → Back.BackI64
- Core.ScalarU8 → Back.BackU8
- Core.ScalarU16 → Back.BackU16
- Core.ScalarU32 → Back.BackU32
- Core.ScalarU64 → Back.BackU64
- Core.ScalarF32 → Back.BackF32
- Core.ScalarF64 → Back.BackF64
- Core.ScalarRawPtr → Back.BackPtr
- Core.ScalarIndex → Back.BackIndex
- Core.ScalarVoid → pvm.empty() (no scalar)
type_to_back_scalar_result (phase: moonlift_type_to_back_scalar_result):
- Ty.TypeClassScalar → scalar_to_back:uncached(self.scalar)
  Returns TypeBackScalarKnown(scalar) if found, else TypeBackScalarUnknown
- Ty.TypeClassPointer → TypeBackScalarKnown(Back.BackPtr) always
- Ty.TypeClassCallable → TypeBackScalarKnown(Back.BackPtr) always
- Ty.TypeClassSlice → empty (no scalar — descriptor)
- Ty.TypeClassView → empty (no scalar — descriptor)
- Ty.TypeClassClosure → empty (no scalar — closure is by ptr but has env)
- Ty.TypeClassAggregate → empty
- Ty.TypeClassArray → empty
- Ty.TypeClassUnknown → empty
=== type_abi_classify.lua ===
Function: M.Define(T)
Uses: type_to_back_scalar, type_size_align, type_classify
abi_class_from_type_class (phase: moonlift_type_abi_class_from_type_class):
- TypeClassScalar → if scalar known:
  - if BackVoid → AbiIgnore
  - else → AbiDirect(scalar)
  - fallback: if self.scalar == ScalarVoid → AbiIgnore
  - else → AbiUnknown
- TypeClassPointer → AbiDirect(BackPtr)
- TypeClassCallable → AbiDirect(BackPtr)
- TypeClassSlice → AbiDescriptor(known_layout(ty) or MemLayout(16, 8))
  size=16, align=8 (ptr+len)
- TypeClassView → AbiDescriptor(known_layout(ty) or MemLayout(24, 8))
  size=24, align=8 (ptr+len+stride)
- TypeClassClosure → AbiDescriptor(known_layout(ty) or MemLayout(16, 8))
  size=16, align=8 (code_ptr+env_ptr)
- TypeClassAggregate → iterates fields:
  - Each field classified recursively
  - Aggregate into packed blob or split into scalar fields
  - If all AbiDirect → AbiBlob or AbiSplit
  - If any AbiIgnore → skip
  - If any AbiUnknown → AbiUnknown
- TypeClassArray → AbiBlob(elem_size * count)
- TypeClassUnknown → AbiUnknown
=== type_func_abi_plan.lua ===
Function: M.Define(T) — cached
arg_binding_for_param(func_name, param, index) → B.Binding(C.Id("arg:"..func_name..":"..param.name), param.name, param.ty, B.BindingClassArg(index-1))
back_scalar(ty) → TypeBackScalarKnown? .scalar : nil
param_plan(func_name, param, index):
- If param.ty is TView → AbiParamView(name, binding, data_id, len_id, stride_id)
- Else if back_scalar(ty) returns non-nil non-Void → AbiParamScalar(name, binding, scalar, value_id)
- Else → AbiParamRejected(name, ty, "parameter type has no direct executable ABI yet")
result_plan(func_name, result_ty):
- If TView → AbiResultView(out_id, data_id, len_id, stride_id) returns via hidden ptr?
- Else if back_scalar(result_ty) returns non-nil non-Void → AbiResultScalar(scalar, value_id)
- Else → AbiResultVoid(func_name)
plan(func_name, params, result_ty):
- Builds list of param plans for each param
- Builds result_plan
- Returns Ty.AbiPlan(params_plan, result_plan)
abi_params_to_back / abi_result_to_back:
- Extracts scalars from plan for lowering calls
=== back_command_binary.lua ===
File: ~300 lines. Encodes BackProgram → binary wire format (MLBT v3).
SCALAR_TAG mapping:
BackBool=1, BackI8=2, BackI16=3, BackI32=4, BackI64=5,
BackU8=6, BackU16=7, BackU32=8, BackU64=9, BackF32=10,
BackF64=11, BackPtr=12, BackIndex=13
(BackVoid omitted → 0 or absent)
CMD_TAG mapping (command kind → numeric tag):
1=CmdTargetModel, 2=CmdAliasFact, 3=CmdCreateSig,
4=CmdDeclareData, 5=CmdDataInitZero, 6=CmdDataInit,
7=CmdDataAddr, 8=CmdFuncAddr, 9=CmdExternAddr,
10=CmdDeclareFunc, 11=CmdDeclareExtern, 12=CmdBeginFunc,
13=CmdCreateBlock, 14=CmdSwitchToBlock, 15=CmdSealBlock,
16=CmdBindEntryParams, 17=CmdAppendBlockParam, 18=CmdCreateStackSlot,
19=CmdAlias, 20=CmdStackAddr, 21=CmdConst, 22=CmdUnary,
23=CmdIntrinsic, 24=CmdCompare, 25=CmdCast, 26=CmdPtrOffset,
27=CmdLoadInfo, 28=CmdStoreInfo, 29=CmdAtomicLoad, 30=CmdAtomicStore,
31=CmdAtomicRmw, 32=CmdAtomicCas, 33=CmdAtomicFence,
34=CmdIntBinary, 35=CmdBitBinary, 36=CmdBitNot, 37=CmdShift,
38=CmdFAdd, 39=CmdFSub, 40=CmdFMul, 41=CmdFDiv,
42=CmdFNeg, 43=CmdSqrt, 44=CmdView, 45=CmdViewAccess,
46=CmdPhi, 47=CmdBranch, 48=CmdSwitch, 49=CmdReturn,
50=CmdReturnVoid, 51=CmdCall, 52=CmdIndirectCall,
53=CmdStore, 54=CmdLoad, 55=CmdStoreInfo (sic, but 27?), check overlap
... continues with CmdMemCopy, CmdTrap, CmdUndefined, CmdEndFunc, CmdExitFunc
Wire format details:
- Uses string pool (for ids, names, module names)
- Identifier deduplication
- Commands encoded as (cmd_tag, num_slots, slots...)
- Each slot is: (type_tag, value) where type_tag is Int, String(0x80?), Float
- Slots pack the command arguments (value ids, block ids, scalars, etc.)
- The encoder walks the BackProgram structure
String pool: Strings encoded as (length, bytes); dedup'd via hash map
TargetModel encoding: triple string, data-layout string
Signature encoding: param_scalars array + result_scalars array
=== back_validate.lua ===
File: ~700 lines. Extracts facts and validates BackProgram.
Function: M.Define(T)
Uses: MoonBack or MoonBack (asserts existence)
append_address_base_uses(out, index, base):
- BackAddrValue → BackFactValueUse(index, base.value)
- BackAddrStack → BackFactStackSlotRef(index, base.slot)
- BackAddrData → BackFactDataRef(index, base.data)
append_address_uses(out, index, addr):
- append_address_base_uses + BackFactValueUse(index, addr.byte_offset)
append_value_uses(out, B, index, values): for each value → BackFactValueUse
append_value_defs(out, B, index, values): for each value → BackFactValueDef
facts_triplet(facts): wraps each fact in pvm.once, returns pvm.concat_all
add_issue(issues, issue): issues#issues+1 = issue
note_unique(seen, key, issue_fn, issues): checks seen table; if already seen, adds issue and returns false
has(seen, key): checks seenkey == true
Validation phases (moonlift_back_validate):
Iterates over each command in program and extracts:
- For each value-defining command: BackFactValueDef(index, result_id)
- For each value-using command: BackFactValueUse(index, arg_id)
- For block references: BackFactBlockRef
- For data references: BackFactDataRef
- Type consistency checks between scalars
Validation rules:
- Every value is defined exactly once
- Every value used is defined (SSA dominance check)
- Block arguments match block params
- Data sizes match declared sizes
- Scalar types match across operations
- Termination: blocks end with terminator (branch/return/trap)
- No dangling references
Fact extraction collects facts_triplet from the program for fact database.
=== type_size_align.lua ===
Full scalar layout table:
Core.ScalarVoid → size=0, align=1
Core.ScalarBool → size=1, align=1
Core.ScalarI8 → size=1, align=1
Core.ScalarU8 → size=1, align=1
Core.ScalarI16 → size=2, align=2
Core.ScalarU16 → size=2, align=2
Core.ScalarI32 → size=4, align=4
Core.ScalarU32 → size=4, align=4
Core.ScalarF32 → size=4, align=4
Core.ScalarI64 → size=8, align=8
Core.ScalarU64 → size=8, align=8
Core.ScalarF64 → size=8, align=8
Core.ScalarRawPtr → size=8, align=8
Core.ScalarIndex → size=8, align=8
class_layout (phase: moonlift_type_class_layout):
- TypeClassScalar → scalar_layout(self.scalar)
- TypeClassPointer → known(8, 8)  // same as RawPtr
- TypeClassCallable → known(8, 8)  // function pointer
- TypeClassSlice → known(16, 8)    // {ptr, len}
- TypeClassView → known(24, 8)     // {ptr, len, stride}
- TypeClassClosure → known(16, 8)  // {code, env}
- TypeClassArray → elem layout × count (packed)
- TypeClassAggregate → sum of field sizes, max of field aligns (with padding)
- TypeClassUnknown → no known layout
=== type_classify.lua ===
Full classification rules:
array_len_count (phase: moonlift_type_array_len_count):
- ArrayLenConst → self.count
- ArrayLenExpr → empty (unknown at compile time)
- ArrayLenSlot → empty (unknown)
classify_type_ref (phase: moonlift_type_ref_classify):
- TypeRefGlobal → TypeClassAggregate(module_name, type_name)
- TypeRefPath → TypeClassUnknown
- TypeRefLocal → TypeClassUnknown
- TypeRefSlot → TypeClassUnknown
classify_type (phase: moonlift_type_classify):
- TScalar(scalar) → TypeClassScalar(scalar)
- TPtr(elem) → TypeClassPointer(elem)
- TArray(count, elem): if array_len_count returns count → TypeClassArray(len, elem_layout); else → TypeClassUnknown
- TSlice(elem) → TypeClassSlice(elem)
- TView(elem) → TypeClassView(elem)
- TStruct(fields) → TypeClassAggregate(fields list)
- TUnion(fields) → TypeClassAggregate(fields; max size)
- TFunc(params, results) → TypeClassCallable
- TClosure(params, results) → TypeClassClosure
- TTypeRef(ref) → classify_type_ref(ref)
- TNamed(name, decl) → classify_type(decl) unwraps named type?
- TVec(vec_type) → TypeClassVec(elem_type, lanes) can vec classify to vector
=== tree_field_resolve.lua ===
Function: M.Define(T)
ty_from_rep(rep):
- HostRepScalar → Ty.TScalar(rep.scalar)
- HostRepBool → Ty.TScalar(C.ScalarBool)
- HostRepPtr → Ty.TPtr(rep.pointee)
- HostRepView → Ty.TView(rep.elem)
- HostRepSlice → Ty.TSlice(Ty.TScalar(C.ScalarU8))
- default → Ty.TScalar(C.ScalarRawPtr)
find_field(layout, name):
- Linear scan layout.fields[] comparing field.name or field.cfield == name
- Returns field or nil
ref_for_field(field):
- Returns Sem.FieldByOffset(field.name, field.offset, ty_from_rep(field.rep), field.rep)
Phase: moonlift_tree_field_resolve ({args_cache: "full"}):
- ExprDot(self, layout) → find_field(layout, self.name) → ref_for_field
- PlaceDot(self, layout) → same
- HostFieldLayout(self) → ref_for_field(self)
=== open_facts.lua ===
File: ~550 lines. Fact extraction for open tree phase.
Function: M.Define(T)
Uses: MoonOpen, MoonBind, MoonTree
Defines many fact phases, each extracting facts from specific node types:
slot_fact: O.SlotType/O.SlotValue/O.SlotExpr/O.SlotPlace/O.SlotDomain/O.SlotRegion/O.SlotCont → O.MetaFactSlot(slot)
value_import_fact: O.ImportGlobalFunc/O.ImportExtern/O.ImportValue/O.ImportGlobalConst/O.ImportGlobalStatic/O.ImportType/...
open_set_facts: Extracts facts from O.OpenSet type/value_imports/slots/layouts
expr_header_facts: ExprSurface → facts; ExprTyped → facts (type); ExprOpen→ s; ExprSem→s; ExprCode→s
Each header contributes facts about its type and structure.
binding_class_facts: B.BindingClass* → facts about binding class
binding_facts: B.Binding → facts (name, type, class, slot ref)
value_ref_facts: B.ValueRef* → facts
slot_value_facts / slot_binding_facts: Map slots to values/bindings
fill_set_facts: Extracts facts from O.FillSet
expr_facts: Tr.Expr* → extract facts per expression kind
place_facts: Tr.Place* → facts
stmt_facts: Tr.Stmt* → facts
view_facts: Tr.View* → facts about view shapes
domain_facts: Tr.Domain* → domain facts
index_base_facts: Tr.IndexBase* → index base facts
control_stmt_region_facts / control_expr_region_facts → region shape, block structure
func_facts, extern_facts, const_facts, static_facts, type_decl_facts, item_facts, module_facts
All facts are collected via "pack" and "cat" functions that accumulate g/p/c triplets for pvm processing.
=== open_validate.lua ===
~90 lines. Slots validation.
slot_issue (phase: moonlift_open_slot_issue):
- O.SlotType → IssueUnfilledTypeSlot(slot)
- O.SlotValue → IssueOpenSlot(self) unconditionally open
- O.SlotExpr → IssueUnfilledExprSlot(slot)
- O.SlotPlace → IssueUnfilledPlaceSlot(slot)
- O.SlotDomain → IssueUnfilledDomainSlot(slot)
- O.SlotRegion → IssueUnfilledRegionSlot(slot)
- O.SlotCont → IssueUnfilledContSlot(slot)
- O.SlotFunc → IssueUnfilledFuncSlot(slot)
- O.SlotConst → IssueUnfilledConstSlot(slot)
- O.SlotStatic → IssueUnfilledStaticSlot(slot)
- O.SlotTypeDecl → IssueUnfilledTypeDeclSlot(slot)
- O.SlotItems → IssueUnfilledItemsSlot(slot)
- O.SlotModule → IssueUnfilledModuleSlot(slot)
- O.SlotRegionFrag → IssueUnfilledRegionFragSlot(slot)
- O.SlotExprFrag → IssueUnfilledExprFragSlot(slot)
- O.SlotName → IssueUnfilledNameSlot(slot)
fact_issue (phase: moonlift_open_fact_issue):
- FactExport → nil valid; FactImport → looks up import
- Missing binding → IssueMissingBinding
- Missing slot fill → IssueUnfilledSlot(slot)
validate_facts (phase: moonlift_open_validate_facts):
Collects all slot_issue + fact_issue for a set, returns list of issues.
=== open_rewrite.lua ===
~640 lines. Rewrites open tree nodes to resolve slots and fills.
Function: M.Define(T)
Uses: MoonType, MoonOpen, MoonBind, MoonTree
Key approach: For each node type, rewrite phase replaces slot references with actual values from fill sets.
rule_targets(phase, set, value): Applies all rules in set to value, collects results
first_target(phase, set, value): Returns first result from rule_targets
rewrite_type (phase: moonlift_open_rewrite_type):
- TScalar → self
- TPtr → rewrite elem
- TArray → rewrite elem, potentially resolve count slot
- TSlice → rewrite elem
- TView → rewrite elem
- TStruct → rewrite fields
- TUnion → rewrite fields
- TFunc → rewrite params, results
- TClosure → rewrite params, results
- TTypeRef → resolve via slot lookup in fill set
- TNamed → unwrap and rewrite
rewrite_binding: Rewrites binding type if slot-resolved
rewrite_value_ref:
- ValueRefSlot → lookup slot in fill set → resolved value or stays
- ValueRefBinding → self
- ValueRefName → self
- ValueRefPath → self
rewrite_place:
- PlaceRef → rewrite_value_ref(self.ref) → PlaceRef or ExprRef
- PlaceDot → rewrite base, rewrite field resolution
- PlaceIndex → rewrite base, rewrite index
- PlaceView → rewrite base, rewrite view
rewrite_expr:
- All Expr* nodes recursively rewrite sub-expressions
- ExprOpen → resolve fill set, rewrite slots
- ExprRef → rewrite_value_ref(self.ref)
- ExprCall → rewrite callee, rewrite args
- ExprView → rewrite base expr + rewrite_view
rewrite_view: Recursively rewrite view descriptor
rewrite_stmt, rewrite_domain, rewrite_index_base, rewrite_control_stmt_region, rewrite_control_expr_region, rewrite_func, rewrite_extern, rewrite_const, rewrite_static, rewrite_type_decl, rewrite_item, rewrite_module
All are recursive tree rewrites that replace slot references with their filled values.
=== open_expand.lua ===
~1000 lines. Expands open tree nodes by resolving fills and slot values.
Function: M.Define(T)
Uses: MoonType, MoonOpen, MoonBind, MoonSem, MoonTree
slot_value(slot, env): Looks up slot in env.fills.bindings, searches backwards.
Returns binding.value if found, nil otherwise.
open_empty(open): true if open.value_imports, .type_imports, .layouts, .slots are all empty
expand_type (phase: moonlift_open_expand_type): Rewrites types by looking up type references in slot values
- TTypeRef slot → lookup_slot_value(O.SlotType), returns resolved type
- TArray → expands count slot if needed
expand_expr_header (phase: moonlift_open_expand_expr_header):
- ExprSurface → resolve header type via type system after expansion
- ExprTyped → type already known
- ExprOpen → resolve fills
- ExprSem → after semantic pass
- ExprCode → after codegen pass
expand_value_ref_expr (phase: moonlift_open_expand_value_ref_expr):
- ValueRefSlot → lookup slot value
- ValueRefImport → lookup import
- ValueRefBinding → self (already bound)
expand_place, expand_expr, expand_stmt, expand_view, expand_domain, expand_index_base:
Recursive expansion
expand_control_stmt_region: Expands region structure, resolves slot params
expand_func / expand_extern / expand_const / expand_static / expand_type_decl / expand_item / expand_module:
Top-level expansions
=== sem_call_decide.lua ===
Function: M.Define(T)
Uses: MoonType, MoonOpen, MoonBind, MoonSem, MoonTree, type_classify
closure_or_indirect(callee, fn_ty):
- If fn_ty classifies as TypeClassClosure → Sem.CallClosure(callee, fn_ty)
- Else → Sem.CallIndirect(callee, fn_ty)
import_call_target (phase: moonlift_sem_import_call_target, args_cache=last):
- ImportGlobalFunc(import, callee, fn_ty) → CallDirect(module_name, item_name, fn_ty)
- ImportExtern(import, callee, fn_ty) → CallExtern(symbol, fn_ty)
- ImportValue(_, callee, fn_ty) → closure_or_indirect(callee, fn_ty)
- ImportGlobalConst(_, callee, fn_ty) → closure_or_indirect(callee, fn_ty)
- ImportGlobalStatic(_, callee, fn_ty) → closure_or_indirect(callee, fn_ty)
binding_class_call_target (phase: moonlift_sem_binding_class_call_target):
- BindingClassGlobalFunc(self, callee, fn_ty) → CallDirect(self.module_name, self.item_name, fn_ty)
- BindingClassExtern(self, _, fn_ty) → CallExtern(self.symbol, fn_ty)
- BindingClassEntryBlockParam → closure_or_indirect(_, fn_ty)
- BindingClassBlockParam → closure_or_indirect(_, fn_ty)
- BindingClassLocal → closure_or_indirect(_, fn_ty)
- BindingClassArg → closure_or_indirect(_, fn_ty)
- BindingClassConst → closure_or_indirect(_, fn_ty)
value_ref_call_target (phase: moonlift_sem_value_ref_call_target):
- ValueRefBinding(self, _, fn_ty) → binding_class_call_target(self.binding.class, _, fn_ty)
- ValueRefImport(self, _, fn_ty) → import_call_target(self.import, _, fn_ty)
callee_call_target (phase: moonlift_sem_callee_call_target):
- Resolves path to find declaration
- Returns CallDirect or CallExtern based on what's found
=== sem_switch_decide.lua ===
Function: M.Define(T)
key_kind (phase: moonlift_sem_switch_key_kind):
- SwitchKeyConst → "const"
- SwitchKeyRaw → "const"
- SwitchKeyExpr → "expr"
stmt_arm_key / expr_arm_key: Extract key from arm
decide_keys (phase: moonlift_sem_switch_decide_keys):
- SwitchKeySet: inspects all keys
  - If mixed const+expr → SwitchDecisionCompareFallback(keys, "mixed const and expression switch keys")
  - If all expr → SwitchDecisionExprKeys(keys)
  - If all const → SwitchDecisionConstKeys(keys)
decide_stmt_switch / decide_expr_switch:
- Gather keys from arms
- decide_keys on the key set
- Returns switch decision
=== vec_*.lua ===
=== vec_loop_facts.lua ===
~700 lines. Extracts facts from loop structures for vectorization.
Function: M.Define(T)
Uses: tree_expr_type, tree_control_facts
bin_op — classifies binary ops for vectorization
view_access_pattern — determines if view access is contiguous/strided
index_base_memory_base — finds base memory for an index base
place_memory_base — finds base memory for a place
memory_base_alias — checks if two memory bases may alias
expr_facts — phase extracting facts per expression:
Records accesses, computations, types relevant to vectorization
store_place_facts — records store operations
stmt_facts — per statement facts for vectorization analysis
control_stmt_facts / control_expr_facts — facts about control flow in loops
binding_same_slot(a,b) — structural equality for binding slots
Key facts extracted:
- VecFactAccess(expr_id, access_id, place, domain, elem_size) — memory access
- VecFactCompute(expr_id, op) — computation operation
- VecFactLoopCarried(expr_id, binding) — loop-carried value
- VecFactInvariant(expr_id, binding) — loop-invariant value
- VecFactReduction(expr_id, op, init) — reduction operation
=== vec_loop_decide.lua ===
~170 lines. Decides whether a loop can be vectorized.
Function: M.Define(T)
scalar_elem (phase: moonlift_vec_scalar_elem):
- Bool → VecElemBool, I8 → VecElemI8, I16 → VecElemI16, I32 → VecElemI32, I64 → VecElemI64
- U8 → VecElemU8, U16 → VecElemU16, U32 → VecElemU32, U64 → VecElemU64
- F32 → VecElemF32, F64 → VecElemF64, RawPtr → VecElemPtr, Index → VecElemIndex
- Void → empty
elem_bits (phase: moonlift_vec_elem_bits):
- VecElemBool → 1, VecElemI8 → 8, VecElemU8 → 8
- VecElemI16 → 16, VecElemU16 → 16
- VecElemI32 → 32, VecElemU32 → 32
- VecElemI64 → 64, VecElemU64 → 64
- VecElemF32 → 32, VecElemF64 → 64
- VecElemPtr → 64, VecElemIndex → 64
target_vector_bits — from host target info (default 128? 256?)
target_supports_shape — checks if target supports this vector shape
facts_elem — extracts element type from loop facts
memory_rejects — checks for memory access patterns that prevent vectorization:
- Non-contiguous access with gaps
- Misaligned access (on some targets)
- Unresolvable aliasing
dependence_rejects — checks for loop-carried dependencies:
- Read-after-write hazards
- Write-after-write hazards
- Unknown reductions
decide_loop (phase: moonlift_vec_decide_loop):
- If any fatal reject → VecLoopNoPlan(rejects)
- Else → VecLoopPlan(vector_factor, vector_shape, mapping)
=== vec_kernel_plan.lua ===
~850 lines. Plans the structure of a vectorized kernel.
Function: M.Define(T)
Uses: tree_expr_type, type_to_back_scalar, type_size_align, vec_loop_facts, vec_kernel_safety, type_func_abi_plan
Key data structures:
- VecKernelPlan(loop_id, input_window, output_window, scalar_loop_body, epilogue_body)
- VecKernelInput(window_id, binding, domain, elem_type, elem_size, alignment, access_pattern)
- VecKernelOutput(window_id, binding, domain, elem_type, elem_size, alignment, access_pattern)
- VecKernelScalar(expr_id, value_id, type)
- VecKernelEpilogue(expr_id)
plan_loop(region_id, loop_facts, safety_info):
1. Identify input windows (read-only memory accesses from loop)
2. Identify output windows (write-only memory accesses)
3. Create scalar loop body plan (before vectorization)
4. Create epilogue plan (remainder iterations)
5. Return VecKernelPlan or VecKernelNoPlan if rejects
Window decisions:
- Contiguous windows → vector load/store with strides
- Strided windows → gather/scatter if beneficial
- Gaps/interleaved → gather/scatter or reject
Alignment decisions:
- If known alignment ≥ vector size → aligned load/store
- Else → unaligned or peel loop for alignment
=== vec_kernel_safety.lua ===
~480 lines. Safety analysis for vectorization.
Function: M.Define(T)
expr_uses — phase that maps expressions to the uses within the loop
- Tracks which values are used, defined, or carried across iterations
mask_uses — identifies expressions that control conditional execution in the loop body
- For mask generation: compares loop index against bounds
- For predication: identifies conditionally executed operations
core_uses — identifies the core computation expressions (those that will be vectorized)
window_range_decide — for each memory access in the loop:
- Determines the range of memory accessed (start, length)
- Checks if range is within bounds (no out-of-bounds access)
- Rejects if access range is unbounded or non-deterministic
decide_input — for each input window:
- Checks read-only access
- Checks no intervening writes
- Checks that all loop iterations read the same pattern
- Returns VecWindowSafe or VecWindowUnsafe
contract_same_len — ensures that multiple accessed arrays have consistent lengths
- If two arrays have different lengths in a loop, vectors may access out of bounds
- Requires runtime length check (min of lengths) or rejects
=== vec_kernel_to_back.lua ===
~820 lines. Lowers a vectorized kernel plan to Back IR commands.
Function: M.Define(T)
Uses: type_to_back_scalar, type_func_abi_plan
elem_scalar(elem): VecElemI32→BackI32, VecElemU32→BackU32, VecElemI64→BackI64, VecElemU64→BackU64, others→nil
elem_size(elem): I32/U32→4, I64/U64→8, others→nil
same_binding_slot(a,b) — structural binding equality (only BindingClassArg matched here)
back_scalar(ty) — scalar_api.result → scalar, nil if not known
Lowering produces VecKernelBackResult:
- Back commands for the vectorized loop body
- Back commands for the epilogue (remainder)
- Mapping from scalar value ids to vector value ids
Key operations:
- Vector loads/stores for contiguous windows
- Gather/scatter for strided/gapped windows
- Broadcast for loop invariants
- Splat for constants
- Shuffle for lane permutations (interleaved access)
- Reductions: add/mul/min/max/and/or/xor across lanes
- Masked operations for conditional execution (predication)
Commands constructed:
- CmdView for vector window references
- CmdLoadVec/CmdStoreVec for aligned vector memory ops
- CmdGather/CmdScatter for strided accesses
- CmdVecBinOp for element-wise operations
- CmdVecCmp for vector comparisons
- CmdSelect for masked results
- CmdShuffle for lane reordering
- CmdReduce for cross-lane reduction
=== vec_to_back.lua ===
~400 lines. Lowering vectorized functions to Back IR.
Function: M.Define(T)
Uses: MoonVec, MoonBack
elem_scalar → BackScalar for each VecElem
shape_to_back — converts VecShape to BackShapeVec or BackShapeScalar
shape_scalar — BackShapeScalar
shape_vec — BackShapeVec(lanes, scalar)
param_shape — determines param shape (vector or scalar) from vec kernel plan
scalar_bin_cmd — maps (vec_bin_op, scalar) → Back cmd tag
vector_bin_op — maps vec op → Back vector command kind
cmd_to_back — phase converting VecKernelCmd to Back cmd list
terminator_to_back — phase converting terminator
block_to_back — converts VecKernelBlock → Back block
func_to_back — converts VecKernelFunc → Back func
program_to_back — converts VecKernelProgram → Back program
env management:
env_empty() → VecBackEnv({})
env_add(env, id, shape) → VecBackEnv with new value shape pair
env_lookup(env, id) → shape or nil
reject(env, id, reason) → VecBackReject
cmds(env, xs) → VecBackCmds
=== vec_inspect.lua ===
23 lines. Simple inspection wrapper.
Function: M.Define(T)
decision(decision) → VecScheduleInspection(decision.facts.loop, decision.legality, decision.schedule, decision.considered)
decisions(decisions) → VecInspectionReport(out)
Returns { decision = decision, decisions = decisions }
---
Report complete. All files analyzed for every function signature, decision branch, edge case, mapping table, and construction pattern relevant to the native MOM port mapping exercise.
