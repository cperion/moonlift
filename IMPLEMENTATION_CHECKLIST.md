# moonlift implementation checklist

This checklist is derived from the ASDL layers in `lua/moonlift/asdl.lua` and
from the file naming discipline in `FILE_NAMING.md`.

Moonlift implementation is bottom-up: complete and validate the lowest
abstraction layer before moving upward.  Higher layers must be tuned to feed the
lower layers cleanly.

---

## 0. Schema / planning

- [x] `lua/moonlift/asdl.lua` defines the ASDL2 schema
- [x] `test_asdl_define.lua` validates the schema can be defined
- [x] `ASDL2_REFACTOR_MAP.md` maps old rich ASDL concepts into ASDL2 homes
- [x] `FILE_NAMING.md` defines file naming discipline from ASDL modules/types
- [x] `SOURCE_GRAMMAR.md` defines the jump-first authored language grammar target
- [x] `LANGUAGE_REFERENCE.md` is the complete single-file Moonlift language reference
- [x] `lua/moonlift/ast.lua` exposes LuaLS-documented ASDL source constructors (`moonlift.ast`) for hosted Lua program generation
- [x] ASDL-backed project-management model exists (`project_asdl.lua`)
- [x] project ready/blocked/report phases exist

---

## 1. `Moon2Core` — shared atoms

Files should use `core_` prefix.

- [x] `core_scalar.lua` helpers/classification for scalar atoms
- [x] tests for scalar identity and scalar family grouping
- [x] operator/intrinsic mapping helpers only where they produce explicit ASDL facts or decisions

Do not move upward because of core helper convenience alone; only add core code when
lower layers need it.

---

## 2. `Moon2Back` — lowest executable flat command layer

Files should use `back_` prefix.

### ASDL / construction

- [x] `Moon2Back.BackProgram` exists
- [x] categorized `Moon2Back.Cmd` exists
- [x] backend validation issue/report ASDL exists
- [x] first fact-rich backend schema slice exists: canonical `BackTargetModel`, explicit address/provenance values, `BackMemoryInfo`, relational `BackAliasFact`, split int/bit/shift/rotate/float scalar commands, and split vector binary commands
- [x] `back_target_model.lua` provides the default executable `BackTargetModel` plus derived `HostTargetModel` / `VecTargetModel` facets, covered by `test_back_target_model.lua`
- [x] `back_program.lua` construction conveniences exist as pure ASDL `BackProgram` builders (`empty`, `program`, `singleton`, `append`, `extend`, `concat`, `cmds`) covered by `test_back_program.lua`

### Validation

- [x] `back_validate.lua` gathers `BackProgramFact` values and returns `BackValidationReport`
- [x] `test_back_validate.lua` covers basic structural validation
- [x] validation covers sig references
- [x] validation covers func/extern declarations and duplicate ids
- [x] validation covers block lifecycle / block params
- [x] validation covers value definition/use where feasible
- [x] validation covers stack slot references
- [x] validation covers data object references
- [x] validation covers call target/signature references
- [x] validation covers scalar/vector shape requirements for categorized commands
- [x] validation covers the first fact-rich load/store slice: access mode, alignment, dereference byte coverage, nontrapping/motion evidence shape, address value refs, and alias access refs
- [x] validation covers active target-supported shape facts and split scalar arithmetic domains (`int`, `float`, `bit`, `shift`/`rotate`)

### Direct execution through current backend

- [x] `back_jit.lua` replays `Moon2Back.BackProgram` directly into the retained Rust/Cranelift FFI command builder
- [x] `back_object.lua` emits host-native relocatable object bytes from `Moon2Back.BackProgram` through the same deterministic `BackCommandTape` and Rust/Cranelift lowering core, covered by `test_back_object_emit.lua` and `test_back_object_full.lua` linking emitted `.o` files with C harnesses across scalar, local-call, data, stack, memory, extern, memcpy/memset, and vector slices
- [x] `Moon2Link` ASDL defines the curated linker/artifact layer: target model, platform/arch/object format, relocation model, artifact kind, linker tool, inputs, exports, extern policy, runtime paths, options, flat commands, reports, and results
- [x] `link_target_model.lua`, `link_plan_validate.lua`, `link_command_plan.lua`, and `link_execute.lua` implement the first host-native linker phase set over `Moon2Link.LinkPlan`, covered by `test_link_plan.lua`
- [x] `emit_shared.lua` provides `.mlua -> object -> shared library` packaging through the `Moon2Link` path, covered by `test_back_shared_emit.lua` loading the emitted shared library through LuaJIT FFI
- [x] legacy `Moon2Back -> MoonliftBack` bridge removed from the active compile path
- [x] `test_back_add_i32.lua` compiles and runs add_i32 through direct `Moon2Back` backend replay
- [x] branch/select vertical slice compiles and runs
- [x] call vertical slice compiles and runs
- [x] load/store/stack slot vertical slice compiles and runs
- [x] data object vertical slice compiles and runs
- [x] vector command smoke slice compiles or is explicitly deferred
- [x] vector compare/select backend slice (`CmdVecCompare` / `CmdVecSelect` / mask commands) executes through direct `Moon2Back` backend replay and Rust/Cranelift
- [x] cast/intrinsic/switch vertical slice compiles and runs
- [x] extern-call and memcpy/memset vertical slice compiles and runs
- [x] indirect-call and stmt-call vertical slice compiles and runs
- [x] data zero-init / alias / unary bit-bool ops vertical slice compiles and runs
- [x] first fact-rich backend smoke slice (`CmdStoreInfo` / `CmdLoadInfo` with explicit `BackAddress`, `BackMemoryInfo`, and `BackAliasFact`) validates and executes through `back_jit.lua`
- [x] vector-kernel backend lowering emits fact-rich `CmdLoadInfo` / `CmdStoreInfo` for kernel memory accesses, carries proven/assumed kernel safety into `BackDereference` / `BackTrap`, carries vector-kernel alignment evidence into `BackAlignment`, emits relational `BackAliasFact` commands, emits split scalar arithmetic commands for loop/index/tail arithmetic, and emits split `CmdVecBinary` commands for vector arithmetic/bitwise ops
- [x] scalar/tree backend lowering emits fact-rich `CmdLoadInfo` / `CmdStoreInfo`, explicit `CmdPtrOffset`, and split scalar arithmetic commands for source loads/stores, field access, view indexing/windows, descriptor wrappers, and view-return stores
- [x] obsolete generic executable command variants `CmdBinary`, `CmdLoad`, and `CmdStore` and the obsolete `BackBinaryOp` enum are removed from active `Moon2Back`; manual backend tests now use the fact-rich command families
- [x] Rust/FFI memory execution now owns fact-rich `BackMemoryInfo` for scalar/vector loads and stores; old Rust `Load` / `Store` / `VecLoad` / `VecStore` command variants and FFI entry points are removed, and exact safe facts map conservatively to Cranelift `MemFlags` (`notrap`, `checked`, `can_move`, natural `aligned`)
- [x] Rust tape execution now decodes split fact-rich scalar arithmetic commands (`CmdIntBinary`, `CmdBitBinary`, `CmdShift`, `CmdRotate`, and `CmdFloatBinary`) into Rust `BackCmd` values; integer overflow/exactness and float strict/fast-math facts are represented in Rust command values even where Cranelift has no matching metadata
- [x] Rust tape execution now decodes compare and pointer-address formation commands directly; the old generic `moonlift_program_cmd_binary` and all per-command `moonlift_program_cmd_*` FFI replay paths are removed from active replay
- [x] `back_inspect.lua` produces ASDL-backed backend inspection reports for command counts, target models, address/provenance and pointer-offset formation facts, memory facts, alias facts, and int/float semantic facts, covered by `test_back_inspect.lua`

Do not start broad `Moon2Tree` lowering before `Moon2Back` can execute basic flat
programs.

---

## 3. `Moon2Type` — type spine and type classes

Files should use `type_` prefix.

- [x] `type_classify.lua` maps `Moon2Type.Type -> Moon2Type.TypeClass`
- [x] `type_to_back_scalar.lua` maps direct scalar/pointer types to `Moon2Back.BackScalar`
- [x] `type_size_align.lua` produces layout-relevant facts for scalar/pointer/array basics
- [x] ABI class/decision ASDL is added if needed by lower layers
- [x] `type_func_abi_plan.lua` produces explicit function ABI plans, including `view(T) -> (ptr, index)` parameter expansion and deterministic backend argument value ids
- [x] tests cover scalar, pointer, array, slice, view, func, closure, named, slot types

---

## 4. `Moon2Open` — slots/fragments/open-code facts

Files should use `open_` prefix.

- [x] `open_facts.lua` walks open values to `MetaFact` streams
- [x] `open_validate.lua` returns `ValidationReport`
- [x] `open_expand.lua` fills slots/fragments/modules through explicit ASDL fills
- [x] `open_rewrite.lua` applies `RewriteSet`
- [x] tests cover every slot kind and fragment/use node

---

## 5. `Moon2Bind` — bindings, refs, residence

Files should use `bind_` prefix.

- [x] `bind_residence_gather.lua` gathers address/materialization/storage facts
- [x] `bind_residence_decide.lua` produces `ResidenceDecision` / `ResidencePlan`
- [x] `bind_machine_binding.lua` produces `MachineBinding` values
- [x] tests cover local value, local cell, arg, entry/block params, global func/const/static, extern, open/import/slot bindings

---

## 6. `Moon2Sem` — semantic facts and decisions

Files should use `sem_` prefix.

- [x] `sem_layout_resolve.lua` resolves `FieldByName -> FieldByOffset`
- [x] `sem_const_eval.lua` evaluates the supported const subset into `ConstValue`
- [x] `sem_switch_decide.lua` produces `SwitchDecision`
- [x] `sem_call_decide.lua` produces `CallTarget`
- [x] tests cover layout, const, switch, call, field, and value/flow classes

---

## 7. `Moon2Tree` — recursive spines

Files should use `tree_` prefix.

- [x] `tree_expr_type.lua` types expression spines
- [x] `tree_stmt_type.lua` types statement spines
- [x] `tree_place_type.lua` types place spines
- [x] `tree_module_type.lua` types modules/items
- [x] `tree_typecheck.lua` resolves surface names, checks expression/place/stmt/control/function/module types, and rewrites headers to typed nodes with explicit `TypeIssue` reports
- [x] `tree_to_back.lua` lowers manually constructed typed/sem trees to `Moon2Back.BackProgram`
- [x] `tree_to_back.lua` lowers typed pointer indexed loads/stores for source kernels
- [x] manual add_i32 tree lowers and runs
- [x] manual select tree lowers and runs
- [x] redesign `tree_*` implementation around `ControlStmtRegion` / `ControlExprRegion`
- [x] `tree_control_to_back.lua` lowers block params, named jumps, yields, returns, and intra-region `if`/`switch` joins to flat backend blocks
- [x] view parameter ABI lowers `view(T)` params as `(data: ptr, len: index)` for executable source/JIT kernels
- [x] initial contiguous `view(ptr, len)` construction lowers into explicit `TreeBackExprView` / `TreeBackViewLocal` descriptors
- [x] initial strided `view(ptr, len, stride)` construction lowers into explicit `TreeBackExprStridedView` / `TreeBackStridedViewLocal` descriptors for scalar/control execution
- [x] initial `view_window(view, start, len)` construction lowers by deriving explicit data/len/stride descriptors for scalar/control execution
- [x] `window_bounds(base, base_len, start, len)` parses, typechecks, and lowers to binding-backed contract facts
- [x] vector kernel planning looks through prefix local constructed-view aliases (`let v = view(ptr, len)` / unit-stride `view(ptr, len, 1)`) to recover pointer/length bindings for a broad `i32`/`i64`/`u32`/`u64` map/reduction family (`sum`, `dot`, `copy`, `fill`, `add`, `sub`, `scale`, selected bitwise maps/reductions, `inc`, `axpy`)
- [x] vector kernel planning rejects non-unit constructed-view strides with explicit `VecRejectUnsupportedMemory` values rather than silently falling back
- [x] vector kernel planning represents contiguous/unit-stride constructed view windows as explicit offset aliases and vectorizes them when range proofs exist
- [x] vector kernel safety uses explicit `VecWindowRangeObligation` / `VecWindowRangeDecision` values; full-range windows (`start = 0`, `len = base_len`), literal shrink windows (`start = k`, `len = base_len - c`, `c >= k`, including scalar-alias starts), and nested accumulated literal-offset windows are compiler-proven, general subwindows require matching `window_bounds` facts, and unproven windows reject instead of assuming
- [x] vector kernel planning carries prefix scalar aliases (`let m = n - k`) as explicit `VecKernelScalarAlias` facts so window range proofs and backend stop values can stay source-derived
- [x] vector kernel length provenance uses explicit `VecKernelLenSource` values (`LenBinding`, `LenView`, `LenExpr`) instead of forcing every base length into a scalar binding
- [x] view parameters seed vector aliases with `VecKernelLenView`, enabling full/prefix window vectorization over `view(T)` params and `same_len`-backed multi-view window maps
- [x] vector loop memory facts classify constant strided view access as `VecAccessStrided(stride)` and treat stride `1` as `VecAccessContiguous`
- [x] vector loop decisions reject strided/gather/scatter/unknown memory patterns explicitly until matching backend support exists
- [x] `ExprLen` / `len(view)` is parsed, typed as `index`, lowered, and used as a counted-loop stop for proof-backed view kernels
- [x] manual single-block jump/control statement tree lowers and runs
- [x] manual single-block value-yield control expression tree lowers and runs
- [x] manual multi-block jump/control graph tree lowers and runs
- [x] initial `tree_control_facts.lua` gathers label/named-jump-arg/yield/backedge facts and validates labels + named jump argument signatures
- [x] control validation rejects unterminated blocks and invalid yield/result shapes
- [x] counted-loop facts are derived from canonical control backedges rather than authored `next`

Parser/source work must wait until these manual jump/control tree slices prove the IR.

---

## 8. `Moon2Vec` — loop/code-shape facts and decisions

Files should use `vec_` prefix.

- [x] `vec_loop_facts.lua` gathers canonical counted-loop facts from jump-first control regions
- [x] `vec_loop_facts.lua` gathers indexed view/raw-address load facts and indexed store facts with explicit `VecMemoryBase`
- [x] `vec_loop_facts.lua` derives initial alias/dependence facts from `VecMemoryBase`, access pattern, and lane-index evidence
- [x] `vec_loop_decide.lua` produces `VecLoopDecision` with explicit `VecLegality` and `VecSchedule` facets
- [x] `vec_to_back.lua` lowers selected vector/scalar code shape to `Moon2Back`
- [x] `vec_kernel_plan.lua` converts typed control regions into explicit generic, element-typed `VecKernelPlan` / `VecKernelExpr` / store/reduction values with target-op gating and explicit reduction identity values
- [x] `vec_kernel_safety.lua` classifies `VecKernelCore` memory uses into explicit `VecKernelSafetyDecision` values
- [x] `tree_contract_facts.lua` converts typed `bounds` / `disjoint` / `same_len` / `noalias` / `readonly` / `writeonly` contracts to binding-backed `ContractFact` values
- [x] `VecKernelSafety` carries explicit raw-pointer bounds/alias assumptions, contract-derived bounds/alias/same-len proofs, view-length bounds proofs, and same-index in-place safety proofs for widened source kernels
- [x] `vec_kernel_to_back.lua` lowers `VecKernelPlan` values to vector-shaped `Moon2Back` command plans for current executable 128-bit shapes (`i32x4`, `u32x4`, `i64x2`, `u64x2`) and consumes explicit `VecKernelCounter` and `VecSchedule` ASDL decisions (`index` for `view`/`len(view)` stops, `i32` for authored `i32` pointer stops, lanes/unroll/interleave/accumulator policy from schedule) rather than rediscovering policy in backend helpers; the active map/reduce path executes positive integer unroll/interleave schedules and multiple vector accumulators when requested by target-preferred schedule facts
- [x] vector compare/select is represented as `VecKernelMaskExpr` plus `VecKernelExprSelect`, target-gated with explicit compare/select/mask facts, safety-walked through mask/select operands, and lowered to vector compare/select/mask plus scalar-tail select commands
- [x] `tree_to_back.lua` consumes `VecKernelPlan` for source-kernel auto-vectorization (`sum_i32`, `dot_i32`, `prod_i32`, `xor_reduce_i32`, `fill_i32`, `copy_i32`, `add_i32`, `sub_i32`, `scale_i32`, `and_i32`, `or_i32`, `xor_i32`, `inc_i32`, `axpy_i32`, `sum_i64`, `dot_i64`, `add_i64`, `sub_i64`, `scale_i64`, `or_i64`, `sum_u32`, `add_u32`, `sum_u64`, `add_u64`, `xor_u64` shapes)
- [x] tests cover canonical control counted domains, reductions, memory/alias/dependence facts, rejects, proofs, decisions
- [x] nested loop facts/decisions are visible to parent loops
- [x] specialized `VecKernelI32*` plan variants and `VecKernelReductionI32Add` are removed; active i32/u32/i64/u64 kernels use generic element-typed reduce/map plans
- [x] `vec_inspect.lua` reports explicit vector legality/schedule decisions as ASDL `VecInspectionReport`, covered by `test_vec_inspect.lua`
- [x] vector-kernel alias safety decisions lower into explicit `BackAliasFact` scope/relation facts for backend inspection and validation
- [x] `back_diagnostics.lua` produces ASDL-backed backend/vector diagnostics with optional disassembly capture
- [x] `back_command_tape.lua` produces deterministic `BackCommandTape` encodings of `Moon2Back.BackProgram` command streams, and active `back_jit.lua` compilation now crosses Lua→Rust through one `moonlift_jit_compile_tape` call instead of per-command FFI replay

---

## 9. Source/parser layer — intentionally late

- [x] source grammar target exists (`SOURCE_GRAMMAR.md`)
- [x] parser exists after lower IR layers are validated (`parse.lua`)
- [x] parser outputs `Moon2Tree.Module(ModuleSurface)` with `ValueRefName` refs and surface headers for functions, externs, consts, statics, pointer/view kernels, `len(view)`, source contracts/parameter modifiers, and jump-first control slices
- [x] parser returns explicit `Moon2Parse.ParseResult` / `ParseIssue` ASDL values
- [x] parser parses the single source conversion form `as(type, expr)` into `ExprCast`; old angle-bracket machine-cast spellings are rejected as source syntax
- [x] documented `moonlift.ast` constructors cover the existing source ASDL node surface and can build modules that typecheck/lower/execute through the normal pipeline
- [x] parser treats `select(cond, then_expr, else_expr)` as source sugar for `ExprSelect`, leaving typing and vector mask recognition to later phases
- [x] parser does not own semantic decisions; `tree_typecheck.lua` resolves names and types
- [x] `emit_object.lua` provides the first `.mlua -> host-native .o` command-line emitter over the normal parse/typecheck/lower/validate/object path

---

## 10. Hosted syntax / staged Moonlift front-end

- [x] `host_quote.lua` uses root `quote.lua` to translate hosted `func ... end` and `module ... end` keyword forms inside Lua chunks into hygienic Lua constructor calls
- [x] hosted `func` and `module` values compile through the normal Moonlift parse/typecheck/back/JIT path
- [x] hosted antiquote `@{lua_expr}` supports explicit scalar/source/type splices evaluated by the outer Lua chunk
- [x] hosted function bodies accept `region -> T` / `entry` as the continuation-language spelling for inline control regions
- [x] hosted `.mlua` loading works through `Host.loadfile` / `Host.dofile`, with `run_mlua.lua` as a small runner
- [x] hosted syntax is currently a frontend experiment only; semantics remain ASDL/parser/compiler owned
- [x] `test_host_quote.lua` covers scalar function quotes, antiquote, module quotes, `.mlua` loading, and jump-first control-region function quotes
- [x] `test_host_quote_value_splice.lua` covers splicing ASDL-backed `TypeValue` objects through hosted source antiquote
- [x] `HOST_VALUE_API_DESIGN.md` defines the Terra-like ASDL-backed hosted value design and phased implementation checklist
- [x] `host.lua` / `host_session.lua` provide the initial thin facade and session/symbol context for direct ASDL-backed host values
- [x] `host_type_values.lua` implements ASDL-backed scalar/pointer/array/slice/view/function/named `TypeValue` constructors
- [x] `host_struct_values.lua` implements ordered `FieldValue`, type-like `StructValue`, module-owned struct/union/enum/tagged-union declarations, and recursive draft/seal structs covered by `test_host_struct_draft_values.lua`
- [x] `host_template_values.lua` implements ASDL-backed `type_param` values and `struct_template` instantiation through explicit `SlotBinding(SlotType, SlotValueType)` fills covered by `test_host_template_values.lua`
- [x] `Moon2Host` ASDL plus `host_issue_values.lua` provide explicit hosted construction issue/report values; duplicate type and continuation-fill diagnostics are covered by `test_host_issue_values.lua`
- [x] `Moon2Host` now owns the first zero-copy hosted declaration facts (`HostDeclSet`, `HostDecl`, `HostStructDecl`, `HostRepr`, `HostFieldDecl`, `HostFieldAttr`, `HostStorageRep`, `HostAccessorDecl`), with duplicate/invalid declaration rejects covered by `host_decl_validate.lua` and `test_host_decl_validate.lua`
- [x] Host layout facts now include explicit `HostTargetModel` / `HostEndian`; `host_layout_facts.lua` derives pointer/index field sizes from the target model instead of hardcoding 64-bit layout, covered by `test_host_target_model.lua`
- [x] Zero-copy view ABI ASDL is now explicit (`HostExposeSubject`, `HostExposeFacet`, `HostExposeAbi`, `HostStrideUnit`, `HostViewAbi`, `HostViewDescriptor`, per-target exposure facets, mutability, bounds, expose declarations, lifetimes), and `host_layout_facts.lua` can derive `MoonView_T { data, len, stride }` descriptor layout/cdef facts covered by `test_host_view_descriptor_facts.lua`
- [x] Host access plans now distinguish record/ptr/view subjects, use explicit bool decode/encode ops, and include view len/data/stride/index/direct-field access operations instead of hiding descriptor access policy in Lua tables
- [x] Host emission plan ASDL now covers Lua FFI, Terra, C headers, and host export ABI choices (`HostLuaFfiPlan`, `HostTerraPlan`, `HostCPlan`, `HostExportAbi`, and corresponding fact variants)
- [x] `buffer_view.lua` now has a descriptor-backed zero-copy `view(T)` runtime family: `define_view_from_host_descriptor` wraps `MoonView_T { data, len, stride }`, supports `#view`, checked/unchecked `view[i]`, direct `view:get_field(i)` accessors, zero-copy mutation visibility, and table materialization covered by `test_host_zero_copy_view_runtime.lua`
- [x] The zero-copy host ABI PVM phase set is implemented: `host_decl_parse`, `host_decl_validate`, `host_layout_resolve`, `host_view_abi_plan`, `host_access_plan`, `host_lua_ffi_emit_plan`, `host_terra_emit_plan`, `host_c_emit_plan`, and `tree_field_resolve`; `test_host_pvm_phases.lua` covers the end-to-end fact stream from hosted declarations to layout/view/access/emission plans and field resolution
- [x] The first integrated `.mlua` parser/source-language slice is implemented: `mlua_parse.lua` parses the Moonlift/host islands (`struct`, `expose`, `func Type:name`, regions with continuation exits, top-level funcs, modules, module-local regions, canonical block-loop forms, and counted-loop sugar) into ASDL/block-jump form; ordinary Lua method declarations stay LuaJIT syntax and are recorded by the hosted runtime as `HostAccessorLua`; `mlua_region_typecheck.lua` and `mlua_loop_expand.lua` provide explicit PVM phase boundaries covered by `test_mlua_parse.lua`, `test_mlua_module_local_region.lua`, `test_mlua_counted_loop.lua`, and `test_mlua_method_syntax.lua`
- [x] Lua builders are now equal host-declaration frontends for the first `.mlua` slice: `host_decl_values.lua` installs ASDL-producing builders (`host_struct`, `host_field`, `host_expose`, `host_lua_accessor`, etc.), and `test_mlua_builder_equivalence.lua` checks source == builder == ASDL for hosted declarations
- [x] `host_quote.lua` was rewritten as a clean LuaJIT-first hosted-island bridge: it does not parse Lua, only lexically rewrites the added end-delimited `.mlua` islands (`struct`, `expose`, `func`, `func Type:name`, named `module`, module-local regions, counted-loop sugar, and typed antiquote splices) into ordinary Lua calls while routing object code through the existing Moon2Tree/Moon2Back pipeline; each loaded chunk now gets one `HostRuntime`/ASDL context that accumulates `HostDecl` facts from hosted declarations and LuaJIT method assignments, and `runtime:host_pipeline_result()` feeds those facts into layout/view/access/emission phases; `test_mlua_host_quote_pipeline.lua`, `test_mlua_splice_shapes.lua`, and `test_mlua_module_local_region.lua` cover the runnable hosted path
- [x] `mlua_host_pipeline.lua` connects full `.mlua` parse results to hosted declaration validation, layout resolution, view/access planning, and Lua/Terra/C emission plans as one ASDL result (`MluaHostPipelineResult`), covered by `test_mlua_host_pipeline.lua`
- [x] `Moon2Host` now also owns explicit host layout/view/access facts (`HostTypeLayout`, `HostFieldLayout`, `HostExposeFacet`, `HostExposeMode`, `HostAccessPlan`, `HostViewPlan`, `HostFactSet`) so buffer-backed Lua views are represented as ASDL facts instead of hidden JSON/Rust policy
- [x] `host_fragment_values.lua` implements ASDL-backed `expr_frag`, `emit_expr`, and Lua-hosted expression-fragment templates covered by `test_host_fragment_values.lua`
- [x] `host_session.lua` exposes reflection wrappers for type classification, size/alignment, ABI decisions, and host struct layout facts covered by `test_host_reflection.lua`
- [x] `host_expr_values.lua`, `host_place_values.lua`, `host_func_values.lua`, and `host_module_values.lua` implement the first direct expression/place/function/module builder slice, with scalar, conditional, and pointer-index store/load typecheck/backend validation covered by `test_host_func_values.lua` and `test_host_place_values.lua`
- [x] `host_region_values.lua` implements initial direct inline control-region and region-fragment builders; `jump` lowers to `StmtJump` / `StmtJumpCont`, `emit` lowers to `StmtUseRegionFrag`, direct continuation-to-continuation fills lower through `SlotValueContSlot`, `switch_` lowers to `StmtSwitch`, and `test_host_region_values.lua` validates jump/emit regions through open expansion, typecheck, lowering, and backend validation
- [x] `test_host_value_jit.lua` executes direct-builder scalar, conditional, expression-fragment, and jump-first region functions through the current JIT backend
- [x] `tree_to_back.lua` lowers scalar `ExprLoad`, pointer `ExprDeref`, address-of for indexed/deref/offset field places, and stores through indexed/deref/offset field places; `test_host_addr_load_jit.lua` and `test_host_field_jit.lua` cover pointer load/store and struct field store/load execution
- [x] Moonlift object-code semantics now use representation-aware `FieldByOffset(field, offset, expose_ty, storage_rep)`: bool storage fields load through compare-to-zero and store through explicit 0/1 encoding, covered by `test_host_bool_storage_jit.lua`
- [x] Internal `view(T)` ABI is now consistently expanded as `data,len,stride`: `AbiParamView` carries stride, view locals/lowering carry stride, `len(view)` reads descriptor/local len, `view[i]` multiplies by element stride, exported view-parameter functions lower through descriptor-pointer wrappers, and exported `view(T)` returns use an out-descriptor pointer, covered by `test_type_func_abi_plan.lua`, updated view kernel tests, and `test_host_view_return_abi.lua`
- [x] continuation slots are explicit ASDL (`ContSlot`, `SlotCont`, `SlotValueCont`, `StmtJumpCont`) and expand through `open_expand.lua`
- [x] hosted `region name(runtime; cont: cont(...)) entry ... block ... end end` creates `RegionFragValue` values
- [x] hosted `emit fragment(runtime; cont = block)` and explicit `emit @{fragment}(...)` lower to `StmtUseRegionFrag` with explicit continuation fills and expand fragment entry/internal blocks into the surrounding control region
- [x] hosted `expr name(...) -> T ... end` creates `ExprFragValue` values and `emit expr_frag(args)` lowers to `ExprUseExprFrag`
- [x] continuation fill diagnostics catch missing, duplicate, and unknown fills at hosted parse/use sites
- [x] continuation jump diagnostics catch missing, duplicate, and extra jump args before expansion
- [x] `test_host_patterns.lua` exercises higher-order continuation patterns: scanner exits, parser-combinator accumulation, reducer exits, and expression fragments inside region fragments
- [x] `test_host_metaprogramming_patterns.lua` exercises host-generated fragments with dynamic names/constants, choice composition, specialized expression fragments, and continuation adapters
- [x] `json_codegen.lua` exposes the single user-facing JSON projection API (`Json.project`, projector compile/decode/free) over the generic indexed-tape path rather than a separate direct byte-projection compiler
- [x] projection output surfaces remain raw buffers, projected-field Lua tables, and reusable buffer-backed views, but they all decode through `JsonDocDecoder` and low-level indexed-tape field reads
- [x] projected missing fields default to zero/false and reused outputs are overwritten deterministically; raw-key lookup intentionally does not claim escaped-key semantic equality until a future indexed-tape query kernel adds that policy
- [x] `buffer_view.lua` provides the generic buffer-backed Lua table-shaped view layer for explicit structs: layouts define C fields and accessors, proxies hold hidden refs/pointers, and `obj.field` reads backing memory without JSON/Rust semantics; `test_buffer_view.lua` covers this outside JSON
- [x] `host_layout_facts.lua` turns buffer-view layouts into explicit `Moon2Host` ASDL fact streams and access/view plans; `test_host_layout_facts.lua` covers scalar fields, bool storage encodings, cdefs, expose facts, and producer facts
- [x] `json_codegen.lua` exposes indexed-tape JSON projections as raw output buffers, projected-field Lua tables, and reusable buffer-backed views; `test_json_projection_view.lua` validates `view_decoder`, `decode_into_view`, direct pointer-backed field access, and exported `Moon2Host` layout facts with no `host_arena_native` dependency
- [x] slow eager JSON object APIs remain removed from the public path: no eager `Json.decode`, no generic `decode_host_arena`, and no one-shot projection record allocation; retained JSON surfaces are validator/tape facts, reusable indexed docs, and indexed projection buffer/table/reused-view outputs
- [x] `bench_json_projection_cjson.lua` compares indexed projection decoding against `cjson.decode` field extraction
- [x] `bench_json_projection_view_cjson.lua` compares indexed JSON projection into reusable buffer-backed views against `cjson.decode` field extraction
- [x] source-call lowering now uses declared direct/extern signatures instead of fresh incompatible call signatures; this remains available for explicit low-level Moonlift extern calls, while the removed HostArena builder externs are no longer part of the runtime surface
- [x] `test_continuation_slot_expand.lua` validates unfilled continuation-slot diagnostics and filled continuation jump rewriting to a concrete block label

---

## 11. JSON builtin library — low-level Moonlift source

- [x] no JSON-specific concepts are added to the main compiler ASDL
- [x] `lib/json.moon2` provides an allocation-free scalar JSON validator in jump-first Moonlift source
- [x] `lib/json.moon2` provides a fused byte parser that decodes JSON into a compact tag/slice tape without token allocation
- [x] `json_library.lua` compiles the JSON library through the normal parse/typecheck/back/JIT path
- [x] `value_proxy.lua` provides the first generic Lua proxy runtime: hidden FFI `MoonliftValueRef`, optional hidden typed pointer, owner/session pinning, family dispatch, table-like field/index/length/iterator access, immutable proxies, and explicit `:to_table()` materialization
- [x] `buffer_view.lua` and `host_arena_abi.lua` implement the first domain-neutral typed-record/view ABI prototypes: generated-style C layouts, type-local field accessors/methods, hidden pointer/ref proxies, and direct FFI pointer field reads covered by `test_json_projection_view.lua`, `test_host_arena_abi.lua`, and measured by projection/HostArena benchmarks
- [x] `src/host_arena.rs` and `host_arena_native.lua` implement only the Rust-owned typed-record allocation slice: aligned record allocation, scalar field initialization by layout offsets, batch record allocation, stable refs/pointers, generation-checked reset/stale-ref detection, Lua owner pinning, and typed proxy access covered by `test_host_arena_native.lua` and HostArena typed-record benchmarks
- [x] Rust-defined JSON/dynamic HostArena graph experiments were removed: no generic Rust string/array/map arena, no HostArena builder extern surface, and no JSON-shaped Rust runtime path; low-level producers should be Moonlift code plus explicit structs
- [x] `HOST_EXPOSURE_PERFORMANCE_DESIGN.md` defines the proper host exposure performance architecture: explicit proxy/eager/scalar/opaque exposure modes, proxy cache/index policies, reusable decode sessions, coarse batch operations over hidden refs, and a separate native Lua table-builder target
- [x] `lib/json.moon2` provides `json_index_tape_scalar`, a low-level generic structural index over the raw JSON event tape: parent, first-child, next-sibling, child-count, key-index, and matching-end arrays
- [x] `lib/json.moon2` provides raw generic field/value helpers (`json_find_field_raw_scalar`, `json_read_i32_scalar`, `json_read_bool_scalar`) so generic document reads stay in Moonlift code instead of Lua table walking; escaped-key semantic lookup is intentionally left to the next query-kernel layer
- [x] `json_library.lua` exposes `JsonDoc` as a low-level indexed tape wrapper over source bytes and integer buffers plus reusable `JsonDocDecoder` sessions to avoid repeated FFI buffer allocation; slow eager object rebuild and lazy generic object-view public APIs remain removed
- [x] validator/tape decoder cover structural arrays/objects, strings, escapes including `\\uXXXX`, literals, strict number grammar, trailing garbage, and trailing-comma rejection
- [x] current validator intentionally leaves UTF-8 payload validation unchecked as a library-level mode/design limitation
- [x] `bench_json_validate_cjson.lua` compares Moonlift validation against `cjson.decode`
- [x] `test_json_generic_doc.lua` covers indexed-tape roots/children, nested raw field lookup, typed scalar reads, reusable doc decoder sessions, and the explicit raw-key limitation for escaped-key semantic equality
- [x] `bench_json_generic_doc_cjson.lua` compares reusable generic indexed-doc field reads against `cjson.decode` field extraction
- [x] retained JSON benchmarks cover validation, reusable generic indexed-doc reads, and indexed projection paths
- [x] `std.lua` / `builtins.lua` provide the public Moonlift standard-library surface: `require("moonlift").json` exposes cached JSON library compilation, indexed-document decoding, typed scalar reads, and projection helpers while preserving the low-level indexed-tape architecture

---

## 12. Moonlift LSP — integrated editor semantics

- [x] `LSP_INTEGRATION_DESIGN.md` defines the complete ASDL/PVM architecture for integrating the `.mlua` language server into the canonical Moonlift schema.
- [x] `LSP_INTEGRATION_CHECKLIST.md` defines the detailed end-to-end work checklist for the integrated LSP.
- [x] `lua/moonlift/asdl.lua` owns the canonical LSP/editor schema modules: `Moon2Source`, `Moon2Mlua`, `Moon2Editor`, `Moon2Lsp`, and `Moon2Rpc`.
- [x] document snapshots, text edits, source ranges, source slices, and source anchors are represented as `Moon2Source` ASDL values.
- [x] `.mlua` segmentation produces `Moon2Mlua.DocumentParts` and `IslandText` values; scanner output is source-map data only, never semantic truth.
- [x] island/document parse products preserve `MluaParseResult`, `HostDeclSet`, `Moon2Tree.Module`, `RegionFrag*`, and `ExprFrag*` while adding source anchor facts.
- [x] document analysis consumes `MluaHostPipelineResult`, host/layout/access/view facts, open/type/control/vector/backend reports, and emits editor semantic facts. The current pass runs module open validation, module typecheck, control fact gathering, vector loop decisions/rejects, and backend validation when typed modules are suitable for lowering.
- [x] diagnostics, document/workspace symbols, bindings, hover, completion, signature help, definition, references, document highlights, prepare-rename/rename, semantic tokens, diagnostic-origin code actions, folding, selection ranges, and parameter inlay hints are represented as ASDL values before any LSP protocol adaptation.
- [x] Region/expr fragment definitions and `emit` uses now participate in binding facts, go-to-definition, references, and rename through the same ASDL navigation path as structs/fields/functions.
- [x] Local/param navigation now flows through explicit `BindingScopeReport`, `BindingScopeFact`, `ScopedBinding`, and `BindingResolution` ASDL facts, so shadowing, block/continuation params, jump-argument writes, assignment writes, and read/write highlights are no longer same-island/source-order approximations.
- [x] Unresolved value uses produce anchored `DiagFromBindingResolution` diagnostics, hover shows the diagnostic subject, and code actions can insert an explicit local declaration from the diagnostic origin without message-string matching.
- [x] Type and backend diagnostics now use explicit variant dispatch for stable codes/messages; common type issues such as invalid binary operands and return/expected-type mismatches use source anchors instead of full-document fallback when an operator/keyword/name anchor exists, and void cascades after unresolved values are filtered.
- [x] JSON-RPC/LSP transport decodes to `Moon2Rpc.Incoming` / `Moon2Editor.ClientEvent` and writes only flat `Moon2Rpc.OutCommand` values from the final loop; both publish diagnostics and LSP pull diagnostics (`textDocument/diagnostic`) are supported.
