# PVM Hard-Yank Checklist

This is the source-of-truth checklist for removing PVM as a Lalin compiler
concept and replacing freeform lowering passes with typed semantic methods.

The goal is not a rename. The goal is to remove the PVM architecture from the
compiler, keep only the ASDL runtime services that are real, and make semantic
lowering live on the ASDL classes/types that own the semantics.

## Non-Negotiable Rewrite Doctrine

Read this section before touching compiler rewrite code.

1. ASDL reasoning comes first. If a method wants broad state, loose tables,
   hidden fields, or ad hoc parameters, stop and fix the schema before editing
   implementation code.
2. After ASDL defines the vocabulary, write methods on the ASDL leaf types that
   own the behavior. The concrete union member is the dispatch.
3. Do not dispatch on ASDL class identity in migrated semantic code. No
   `schema.classof(x) == Variant`, no `kind` strings, no action strings, no
   selector tables, and no rule runners.
4. Do not preserve old architecture through new names. No compatibility shims,
   compatibility aliases, fake visitors, run orchestrators, or relation wrappers.
5. Do not pass generic `ctx`, `context`, `env`, `type_state`, or option bags
   through semantic methods. If an operation needs input, model a precise ASDL
   product for that input and pass that product.
6. Do not add method parameters casually. A leaf method takes no argument unless
   the operation genuinely needs another explicit ASDL value.
7. Parent/sum methods are allowed only as real shared defaults or delegation
   contracts. They must not inspect leaf classes to choose behavior.
8. Hidden Lua fields on ASDL values are not semantic state. Semantic state is
   explicit ASDL data.
9. Tests may be red during the rewrite. Do not keep old dispatch, bags, or shims
   to make tests green mid-migration.
10. If these rules and existing code conflict, rewrite the code. Do not negotiate
    the rules downward.

## Current Rewrite Progress

Keep this section current after every rewrite pass. It is the short ledger; the
long checklist below remains the full audit.

- [x] `AGENTS.md` points future agents to this doctrine before PVM/compiler
      rewrite work.
- [x] `lua/lalin/asdl.lua` is the active ASDL runtime surface.
- [x] Direct ASDL method assignment works, including nullary singleton variants.
- [x] ASDL sum parents propagate explicitly installed parent methods to
      variants; missing methods are absent and do not synthesize nil-returning
      functions.
- [x] ASDL runtime values no longer expose synthetic `.kind` tags or class
      metadata through instance lookup; diagnostics use explicit class-name
      reflection helpers.
- [x] ASDL class runtime metadata now lives in private side tables; compiler
      code uses `asdl.fields`, `asdl.members`, `asdl.context_of`, and
      `asdl.isa` instead of reading class internals.
- [x] ASDL parent methods are inherited by class lookup without copying into
      leaves, so child overrides survive later parent defaults.
- [x] `lua/lalin/tree_typecheck_rules.lua` is deleted.
- [x] `lua/lalin/tree_typecheck_type.lua` installs direct schema-context methods.
- [x] `lua/lalin/tree_typecheck_layout.lua` installs direct schema-context methods.
- [x] `lua/lalin/tree_typecheck_expr.lua` installs direct schema-context methods
      for the current expression rewrite slice.
- [x] `lua/lalin/tree_typecheck_fact.lua` installs direct schema-context methods
      for explicit module facts.
- [x] `TypeModuleFacts` and related typed input/result products exist in
      `lua/lalin/schema/tree.lua`.
- [x] `tree_typecheck.lua` no longer stores variant, handle, or function-effect
      facts in hidden raw fields on `LalinBind.Env`.
- [x] `tree_typecheck.lua` now carries explicit `TypeModuleFacts` in typed
      input products instead of hidden environment fields.
- [x] `ItemType` validation now delegates to `TypeDecl*` methods instead of
      dispatching on the concrete type declaration class.
- [x] `IndexBase` element typing now delegates to `IndexBase*` methods instead
      of dispatching on the concrete index-base class.
- [x] `View` element typing now delegates to `View*` methods instead of
      dispatching on the concrete view class.
- [x] Local `TypeRef` leaf extraction now delegates to `TypeRef` methods instead
      of duplicating class dispatch.
- [x] Expression/place typed-header extraction now delegates to header methods
      instead of dispatching on header classes.
- [x] Handle lease domain/invalidation type-shape checks now delegate to
      `Type` leaf methods instead of checking `TPtr`, `TView`, or `TLease` in
      the driver.
- [x] Item diagnostic names now delegate to `Item*` methods instead of
      dispatching on item classes in the driver.
- [x] Dead `type_switch_key` table-dispatch code was removed from
      `tree_typecheck.lua`.
- [x] `ControlReject*` explanation methods return typed
      `ControlRejectExplanation` ASDL values, not plain Lua report tables.
- [x] `TypeIssueExplanation` ASDL exists and most non-unary diagnostic
      explanation branches now convert from typed issue methods instead of
      returning plain Lua report tables directly.
- [x] `TypeIssueInvalidUnary` carries a typed `TypeUnaryIssueReason` ASDL sum;
      unary diagnostic explanation lives on the issue/reason ASDL methods and
      `explain_type_issue` no longer dispatches on issue `kind`.
- [x] `Func*` and `Item*` typecheck methods now receive typed
      `TypeFuncInput`/`TypeItemInput` products instead of loose
      `module_env, facts` pairs.
- [x] Region signature validation now lives on `Region` as a typed method using
      `TypeItemInput`, instead of a free helper taking loose module facts.
- [x] Switch arms now carry typed `SwitchKey` ASDL leaves
      (`SwitchKeyInt`/`SwitchKeyBool`/`SwitchKeyName`/`SwitchKeyExpr`) and
      switch-key decisions use the `SwitchKeyDecision` ASDL sum instead of
      plain Lua `kind` tables or raw-key strings.
- [x] `TypeCheckEnv` is removed from the ASDL schema and active typecheck path;
      driver plumbing now uses `TypeValueScope`, `TypeExprInput`,
      `TypePlaceInput`, `TypeStmtInput`, and `TypeControlInput` products.
- [x] Move statement/place/control behavior out of `tree_typecheck.lua` and onto
      concrete ASDL classes.
      - [x] `lua/lalin/tree_typecheck_stmt.lua` owns `StmtReturnValue`,
            `StmtReturnVoid`, `StmtExpr`, `StmtLet`, `StmtVar`, `StmtIf`,
            `StmtSet`, atomics, `StmtAssert`, `StmtSwitch`, `StmtJump`,
            `StmtJumpCont`, yields, `StmtControl`, `StmtTrap`, control block
            typing, and `TypeStmtInput:typecheck_tree_stmt_body`.
      - [x] `TypeControlInput` is an ASDL product carrying the typed statement
            input and region id; control typing no longer uses a loose table.
      - [x] `tree_typecheck.lua` no longer exports expression/place/statement/
            control/function/item/module facade helpers; callers use ASDL
            methods or the real stage API `check_module`.
- [x] Remove remaining class-inspection branches from rewritten typecheck code
      by adding missing leaf methods or schema products first.
      - [x] Rewritten typecheck method files and touched typecheck tests are
            clean for `schema.isa`, `classof`, `.kind`, and equivalent checks.
      - [x] Typecheck tests assert semantic ASDL predicates instead of inspecting
            concrete classes.
- [x] Rename method module filenames to the final semantic-stage names once the
      typecheck split is stable.
      - [x] Typecheck-owned method modules now use `tree_typecheck_*` names:
            `tree_typecheck_type`, `tree_typecheck_layout`,
            `tree_typecheck_fact`, `tree_typecheck_expr`, and
            `tree_typecheck_stmt`.
- [x] Rewrite `tree_to_code_rules.lua` after the typecheck rewrite stopped
      carrying old dispatch behavior.
      - [x] Deleted `lua/lalin/tree_to_code_rules.lua`.
      - [x] Deleted `tests/frontend/test_tree_to_code_rules.lua`.
      - [x] Added `tests/frontend/test_tree_to_code_methods.lua`.
      - [x] `lua/lalin/tree_to_code.lua` installs lowering behavior directly on
            ASDL classes for expressions, places, statements, function/item
            forms, contract facts, view/index lowering, constant globals, and
            module registration.
      - [x] Production `tree_to_code.lua` is clean for `asdl.classof`,
            `schema.isa`, `.kind`, selector-table, and rule-module dispatch.
- [x] Continue `lua/lalin/code_to_back.lua` method rewrite.
      - [x] `CodeInstOp` and `CodeTermOp` behavior lives on concrete ASDL
            leaf methods; the old instruction/terminator ladders are gone.
      - [x] Code-to-Back facts, state, inputs, and state/value/address/memory
            results are explicit ASDL products.
      - [x] Code-to-Back semantic helpers no longer mutate `state.cmds`,
            scratch maps, or `next_tmp` directly; state changes are returned
            through typed products and synced by the driver.

## ASDL Tower Review TODO

This section records the 2026-06-30 ASDL tower/lowering review. These are not
style notes. They are architecture debt against `docs/ASDL_GUIDE.md`: type and
dispatch must live in ASDL, leaf methods own semantic behavior, and semantic
methods return typed ASDL results instead of ad hoc tables, nil protocols,
manual dispatch, or large mutable context bags.

- [x] Keep the ASDL runtime escape hatch closed.
      - [x] No ASDL `any`, `table`, `table_ty`, or `map` field type is
            currently exposed.
      - [x] Keep schema guard tests that reject `any`, `table`, `table_ty`,
            `map`, and equivalent catch-all field types loudly.
      - [x] Remove ASDL `map` support from `lalin.schema.dsl`; keyed relations
            must be named ASDL entry products carried under `many`.
      - [x] Remove runtime `.kind` tags from generated ASDL classes; semantic
            dispatch must be direct method lookup, with class-name reflection
            reserved for diagnostics and formatting.
      - [x] Remove synthetic default nil methods from ASDL sum parents; parent
            defaults must be explicitly installed methods.
      - [x] Hide class metadata from ASDL instances by exposing only fields and
            real methods through instance lookup.
      - [x] Move constructor plans, field lists, context ownership, singleton
            values, membership sets, raw getters, and unique-slot counters into
            private runtime side metadata.
      - [x] Replace active compiler reads of raw ASDL metadata with explicit
            runtime helpers.
- [ ] Semantic naming audit: make ASDL type and method names say what they are.
      This is not a cosmetic old-name replacement pass; names must expose the
      semantic role of the value or method.
      - [x] Replace generic payload names such as `*Info`, `*Data`, `*Payload`,
            and broad `*Input` products when the fields describe a concrete
            domain object. Current high-priority examples:
            `StencilMachineStoreNInfo`, `StencilMachineReduceNInfo`,
            `StencilMachineScanArrayInfo`, `StencilMachineFindArrayInfo`,
            `StencilMachinePartitionArrayInfo`,
            `StencilMachineScatterReduceNInfo`, and select inputs containing
            a field named `class`.
            Closed by renaming the stencil-machine operation payloads to
            `*Descriptor`, selection inputs to `*SelectionFacts`, selected
            payload fields to `descriptor`, and the selected point-expression
            field to `point_facts`.
      - [x] Rename `StencilMachinePointClass`; it is not a runtime/class tag.
            Use a semantic name for the grouped point-input facts/capabilities.
            Closed as `StencilMachinePointExprFacts`.
      - [x] Audit all `*Kind` and `*Class` sums. Keep only names where
            `kind` or `class` is the actual domain term; otherwise rename to
            the semantic choice being modeled. The only remaining schema
            `*Class` names are intentional domain terms: C `StorageClass` and
            ABI `AbiClass`.
            - [x] `BindingClass` became `BindingRole`; `Binding.class` became
                  `Binding.role`.
            - [x] `TypeClass` became `TypeShape`; unavailable type-layout and
                  scalar results now carry `shape`, and `AbiDecision.class`
                  became `AbiDecision.abi`.
            - [x] Memory schema category names became semantic names:
                  `MemAccessKind` -> `MemAccessOp`,
                  `MemObjectKind` -> `MemObjectForm`, and
                  `MemProjectionKind` -> `MemProjectionStep`; access/object
                  fields now use `op` and `form`.
            - [x] Code instruction and terminator operation sums became
                  `CodeInstOp` and `CodeTermOp`.
            - [x] LuaJIT machine operation sum became `LJMachineOp`; machines
                  now carry `op`.
            - [x] Exec fragment, source anchor, and C type category names became
                  semantic schema names: `ExecFragmentKind` ->
                  `ExecFragmentBody`, `AnchorKind` -> `AnchorRole`, and
                  `CTypeKind` -> `CTypeShape`; their fields are now `body`,
                  `role`, and `shape`.
            - [x] C AST directive/include/macro category names became semantic
                  names: `CDirectiveKind` -> `CDirectiveToken`,
                  `CIncludeKind` -> `CIncludeDelimiter`, and `CMacroKind` ->
                  `CMacroForm`; their payload fields are now `directive`,
                  `delimiter`, and `form`.
            - [x] Host category names became semantic names:
                  `HostLayoutKind` -> `HostLayoutShape`, `HostValueKind` ->
                  `HostValueSubject`, `HostProxyKind` -> `HostProxyShape`, and
                  `HostProducerKind` -> `HostProducerBackend`; fields are now
                  `shape`, `subject`, `proxy`, and `backend`.
            - [x] Link artifact/tool category names became semantic names:
                  `LinkArtifactKind` -> `LinkOutputForm` and `LinkerKind` ->
                  `LinkToolDriver`; plan/tool fields are now `output_form` and
                  `driver`.
            - [x] MLua island category names became semantic names:
                  `IslandKind` -> `IslandRole`; island text and malformed
                  island payloads now carry `role`.
            - [x] Flow induction category names became semantic names:
                  `FlowInductionKind` -> `FlowInductionRole`; induction facts
                  now carry `role`.
            - [x] Stencil proof category names became semantic names:
                  `StencilProofObligationKind` -> `StencilProofRequirement`;
                  proof obligation records now carry `requirement`.
            - [x] DASM was removed from the codebase: no `LalinDasm` schema,
                  no `back/dasm` backend, and no retired DASM tests.
            - [x] Schedule category names became semantic names:
                  `ScheduleKind` -> `ScheduleForm`; planned schedules and
                  schedule selections now carry `form`.
            - [x] C backend helper category names became semantic names:
                  `CBackendHelperKind` -> `CBackendHelperSpec`; helper uses
                  now carry `spec`.
            - [x] Core open-symbol category names became semantic names:
                  `SymKind` -> `SymRole`; `OpenSym` now carries `role`.
            - [x] Core operator grouping names became semantic names:
                  `UnaryOpClass`, `BinaryOpClass`, `CmpOpClass`, and
                  `IntrinsicClass` became `UnaryOpFamily`, `BinaryOpFamily`,
                  `CmpOpFamily`, and `IntrinsicFamily`.
            - [x] Statement flow category names became semantic names:
                  `FlowClass` -> `FlowOutcome`.
            - [x] C AST struct/union category names became semantic names:
                  `StructKind` -> `StructForm`; struct-or-union type specs now
                  carry `form`.
            - [x] Compiler diagnostics stopped using schema-class wording:
                  `CodeResultIssueWrongClass` and
                  `FlatlineImageIssueWrongClass` became
                  `CodeResultIssueUnexpectedValue` and
                  `FlatlineImageIssueUnexpectedValue`.
            - [x] Host layout reject names stopped using field-kind wording:
                  `HostRejectUnknownFieldKind` became
                  `HostRejectUnknownFieldRep`.
            - [x] Reduction category names became explicit operation names:
                  `ReductionKind` -> `ReductionOp`; reduction facts and
                  stencil-machine descriptors now carry `op`/`reduction_op`.
      - [x] Audit `*Mode` sums. Keep `mode` only when it is a real user/domain
            mode; otherwise rename to the policy/semantics being chosen.
            Only `CodeFloatMode` and `StencilScanMode` remain as intentional
            domain modes.
            - [x] Trap/div/shift choices became policies:
                  `CodeTrapMode` -> `CodeTrapPolicy`, `CodeDivMode` ->
                  `CodeDivPolicy`, `CodeShiftMode` -> `CodeShiftPolicy`,
                  `CBackendTrapMode` -> `CBackendTrapPolicy`,
                  `CBackendDivMode` -> `CBackendDivPolicy`, and
                  `CBackendShiftMode` -> `CBackendShiftPolicy`.
            - [x] Read/write access choices became effects:
                  `CodeMemoryMode` -> `CodeMemoryEffect`,
                  `BackAccessMode` -> `BackAccessEffect`, and memory/access
                  products now carry `effect`.
            - [x] Store/reduce sink choices became semantics:
                  `StencilStoreMode` -> `StencilStoreSemantics` and
                  `StencilReduceMode` -> `StencilReductionSemantics`; store
                  and reduce sinks now carry `semantics`.
            - [x] Host exposure choice became strategy:
                  `HostExposeMode` -> `HostExposeStrategy`; expose facets now
                  carry `strategy`.
            - [x] Typechecking yield choice became result:
                  `TypeYieldMode` -> `TypeYieldResult`.
      - [ ] Replace methods that return selector strings or booleans for later
            branching with direct leaf behavior or typed ASDL result values.
            Current high-priority examples: `stencil_artifact_kind`,
            `lower_emit_is_*`, `lower_plan_is_*`, `exec_plan_is_*`,
            `stencil_machine_kernel_is_*`, `stencil_machine_skeleton_is_*`,
            and `lower_emit_needs_schedule`.
            - [x] Removed `stencil_artifact_kind`; concrete stencil-machine
                  selections now call artifact providers through
                  `select_stencil_artifact`.
            - [x] Removed `lower_emit_needs_schedule`; lowering strategies now
                  resolve schedules through `lower_emit_schedule`.
            - [x] Removed `lower_emit_is_*`, `lower_plan_is_*`,
                  `exec_plan_is_*`, `stencil_machine_kernel_is_*`,
                  `stencil_machine_skeleton_is_*`, and `schedule_plan_is_*`;
                  focused tests now assert selected ASDL values or exercise
                  the selected leaf behavior directly.
            - [ ] Continue the broader predicate audit. Remaining visible
                  families include `kernel_plan_is_*`,
                  `typecheck_tree_is_*`, and local legality predicates that
                  should become direct leaf behavior or typed result values.
            - [x] Removed `kernel_plan_is_*` loop-plan selectors; tests now
                  assert the selected ASDL value payloads directly and the
                  planner continues through `add_selected_loop_plan`.
            - [x] Removed memory read/write selector predicates from kernel
                  planning and semantic Back/C lowerers. Memory access op
                  leaves now add dependence rejects or select read/write lane
                  accesses directly.
      - [ ] Rename method parameters named `ctx`, `context`, `env`, `state`,
            `info`, or `input` unless the parameter type name is already narrow
            and exact. Broad examples still visible in the audit include
            `tree_code_*` helpers taking `ctx`, `stencil_c_*` methods taking
            `ctx`, and `emit_to_back`/`emit_to_c` methods taking long loose
            argument lists.
            - [x] `lua/lalin/stencil_c.lua` no longer uses `ctx` for producer
                  loop semantics. The producer loop object is named
                  `loop_scope`, and its constructor is named
                  `stencil_loop_scope`.
            - [x] `LowerEmitSelection:emit_to_back` and
                  `LowerEmitSelection:emit_to_c` no longer receive long loose
                  argument lists. They take a named emission builder plus
                  `LowerBackEmitInput`/`LowerCEmitInput` ASDL products carrying
                  the exact fragment facts.
            - [x] `lua/lalin/lower_to_c.lua` no longer uses a `ctx` identifier
                  for semantic C lowering. The mutable driver-side builder is
                  named `c_emission`, and type lookup is named
                  `c_type_projection`.
            - [x] `lua/lalin/lower_to_back.lua` no longer uses a `ctx`
                  identifier for semantic Back lowering. The mutable
                  driver-side builder is named `back_emission`, and memory
                  backend metadata parameters are named `backend_access`.
            - [x] `lua/lalin/code_to_c.lua` no longer uses a `ctx` identifier
                  for generic Code-to-C lowering. The mutable builder is named
                  `c_emission`, and the type lookup table is named
                  `c_type_projection`.
            - [x] `lua/lalin/tree_to_code.lua` no longer uses `ctx` for typed
                  TreeCode method inputs. The active lowering input is named
                  `tree_code_input`; remaining `input` parameters are explicit
                  ASDL products such as `TreeCodeExprInput`,
                  `TreeCodeStmtInput`, and `TreeCodeItemLowerInput`.
      - [ ] Rename files whose module name hides the semantic owner. Current
            candidates: `schema_runtime.lua`, `schema_context.lua`,
            `compiler_driver.lua`, `phase_execute.lua`, `exec_plan.lua`,
            `code_lower_plan.lua`, `lower_to_back.lua`, `lower_to_c.lua`, and
            the `luajit_*` family if the schema/module is no longer strictly
            LuaJIT-specific.
      - [ ] Treat `Plan`, `Selection`, `Candidate`, and `Result` as acceptable
            only when the type name also states the specific thing being
            planned, selected, considered, or returned.
- [x] Repair module/context ownership for the active Lalin compiler surfaces.
      - [x] `lalin.ast` no longer creates a private default schema context or
            exposes raw context/builders through its constructor API.
      - [x] `lalin.dsl` binds through `dsl(T)`; the public `lalin` facade owns
            and passes its default authoring context.
      - [x] `lalin.dsl.format` installs ASDL formatting methods on the value's
            owning context instead of allocating its own context.
      - [x] `lalin.phase_dsl`, `compiler_package`, and `phase_plan` no longer
            allocate private fallback phase contexts.
      - [x] Parsed syntax submodules require a projected context instead of
            silently installing schema projection.
- [x] Rewrite `lua/lalin/sem_const_eval.lua` as ASDL leaf methods.
      - [x] Add explicit `ConstEvalInput` in `LalinSem`.
      - [x] Add `ConstExprResult` ASDL leaves such as `ConstKnown`,
            `ConstNotFoldable`, and `ConstRejected`.
      - [x] Add `ConstStmtFlow` ASDL leaves such as `ConstFallsThrough`,
            `ConstReturnVoid`, `ConstReturnValue`, `ConstYieldVoid`,
            `ConstYieldValue`, and `ConstJump`.
      - [x] Install `Expr*` constant-eval behavior on concrete `LalinTree.Expr`
            leaves.
      - [x] Install `Stmt*` constant-eval behavior on concrete `LalinTree.Stmt`
            leaves.
      - [x] Delete the generated/manual `schema.isa`/`schema.classof` ladders.
      - [x] Delete `yes/no`, nil-as-not-constant, `single(...)` phase wrappers,
            and `{ kind = ..., env = ... }` result records.
- [ ] Repair `lua/lalin/tree_to_code.lua` state semantics.
      - [x] Split `TreeCodeFuncContext` into precise ASDL products such as
            module facts, function facts, block state, control state, binding
            projection, and emission result.
      - [x] Stop treating one mutable context product as the default semantic
            input for all leaf methods.
      - [ ] Make leaf methods return typed state/result products instead of
            mutating maps, counters, current block slots, control-region slots,
            and alpha-renaming slots in place.
            - [x] Removed illegal ASDL product-field mutation from the active
                  Tree-to-Code path. Current block, alpha suffix, control-region
                  stack/exit flags, and module string counters now live in
                  typed keyed state collections instead of optional/scalar
                  product fields.
            - [x] Control target storage now uses
                  `TreeCodeControlTargetEntry` values instead of a hidden
                  string-keyed map inside `TreeCodeControlRegion.targets`.
            - [x] Module lowering reads back `funcs`, `data`, `globals`, and
                  contract facts from the typed input products after ASDL
                  construction, rather than relying on pre-constructor tables.
      - [x] Rename `TreeCodeFuncContext` only if the resulting shape is honest:
            use `TreeCodeFuncState` for explicit state, or split it instead of
            renaming a bag.
      - [x] Remove the old Tree-to-Code free lowering helpers for expressions,
            places, calls, if/switch/control lowering, view index lowering,
            variant payload binds, globals, and function bodies; those semantics
            now live on ASDL input products or concrete ASDL leaves.
        progress: `TreeCodeFuncContext` and `TreeCodeModuleContext` are removed.
        Tree-to-Code now separates `TreeCodeModuleFacts`,
        `TreeCodeModuleSigState`, `TreeCodeModuleRegistrationState`,
        `TreeCodeModuleEmissionState`, `TreeCodeFuncFacts`, and
        `TreeCodeFuncState`. The remaining debt is no longer free-helper
        dispatch; it is the mutable state protocol inside the Tree-to-Code
        state products.
- [x] Repair Code-to-Back state shape after the method rewrite.
      - [x] Audit `CodeBackModuleFacts`, `CodeBackFunctionFacts`, and
            `CodeBackFunctionState` for map-heavy side state.
      - [x] Replace aggregate-address, capture, local-slot, tmp-counter, and
            readonly side maps with named ASDL facts/projections where they are
            semantic state.
      - [x] Keep private lookup indexes only inside local driver scopes; do not
            pass raw maps as semantic method inputs.
        debt paid: `CodeBackFunctionState` now carries
        `CodeBackAggregateState`, `CodeBackClosureState`,
        `CodeBackLocalSlotState`, and `CodeBackTempState`; module readonly
        facts are carried by `CodeBackReadonlyProjection`.
- [x] Methodize `lua/lalin/code_to_c.lua`.
      - [x] Move `CodeConst` to C atom lowering onto `CodeConst` leaves.
      - [x] Move `CodePlace` to C place lowering onto `CodePlace` leaves.
      - [x] Move `CodeGlobalRef` name/signature/reloc behavior onto
            `CodeGlobalRef` leaves.
      - [x] Move `CodeInstOp` to C statement lowering onto `CodeInstOp`
            leaves.
      - [x] Move `CodeTermOp` to C terminator lowering onto `CodeTermOp`
            leaves.
      - [x] Delete the `asdl.classof` ladders in `inst_to_stmts`, `term_to_c`,
            `place_to_c`, `const_atom`, and related helpers.
- [x] Methodize `lua/lalin/stencil_c.lua`.
      - [x] Move producer parameter and loop emission onto `StencilProducerShape`
            leaves.
      - [x] Move point-expression C emission onto `StencilPointExpr` leaves.
      - [x] Move access-layout offset/address emission onto
            `StencilAccessLayout` leaves.
      - [x] Move artifact declaration selection onto typed stencil artifact,
            body, sink, or descriptor leaves.
      - [x] Remove `producer.kind` checks and `artifact_shape(...).kind`
            dispatch from compiler semantics.
- [x] Repair `lua/lalin/code_kernel_plan.lua` skeleton semantics.
      - [x] Move primary-index recognition and value-key construction for
            `ValueExpr` leaves out of local `asdl.classof` switches and onto
            parent/default plus leaf ASDL methods.
      - [x] Move scatter-reduce expression classification onto `ValueExpr`
            parent/default plus leaf ASDL methods.
      - [x] Replace ad hoc skeleton records such as
            `{ effects = ..., result = ..., handles_dependences = ... }` with
            an ASDL `KernelSkeletonSelection` or equivalent union.
      - [x] Move skeleton inference outcomes into typed leaves for scan, find,
            partition, copy, scatter-reduce, and no-plan/reject.
      - [x] Keep temporary indexes local; do not pass side maps as semantic
            inputs when a named ASDL fact/projection is needed.
- [x] Replace optional-soup candidate products with unions.
      - [x] Replace `KernelLoopPlanInput` booleans plus optional candidates with
            a `KernelLoopCandidate` union: not-counted, missing-owner,
            rejected-facts, closed-form, reduction, skeleton, original-control.
      - [x] Replace `LowerFragmentPlanInput` option clusters with a
            `LowerFragmentCandidate` union.
      - [x] Replace `LowerEmitInput` option clusters with an explicit
            `LowerEmitCandidate` or selection union.
- [x] Delete `StencilMachineSelectionInfo` optional soup.
      - [x] Move store/reduce/scan/find/partition/copy/scatter-reduce payloads
            into leaf-specific ASDL products.
      - [x] Ensure each `StencilMachineSelected` leaf consumes the exact ASDL
            payload it needs, not a shared product with dozens of nullable
            fields.
      - [x] Ensure `StencilMachineSkeletonInput` becomes a candidate/selection
            union rather than several optional plan slots plus a reason string.
- [x] Methodize remaining fact/type helpers that still dispatch manually.
      - [x] Move `code_graph` def/use/edge extraction onto `CodeInstOp`,
            `CodeTermOp`, `CodePlace`, and `CodeCallTarget` leaves.
      - [x] Move `code_value_facts` expression/fact extraction onto
            `CodeInstOp`, `Core.BinaryOp`, and `ValueExpr` leaves.
      - [x] Move `type_size_align` scalar/class layout behavior onto
            `Core.Scalar`, `TypeShape`, `TypeRef`, and `Type` leaves.
      - [x] Move `type_to_back_scalar` behavior onto `Core.Scalar` and
            `TypeShape` leaves.
      - [x] Replace raw index products such as `expr_by_value`, `proof_by_value`,
            and `backend_by_access` with named ASDL lookup/projection products
            whenever they cross a semantic method boundary.

## Goal

Make the Lalin compiler architecture direct, typed, and locally understandable.

After this migration, a compiler contributor should be able to answer questions
like "how does this node typecheck?", "how does this expression lower to
`LalinCode`?", "how does this code value become C?", or "why is this stencil
legal?" by going to the ASDL class/type that owns the source semantic form and
reading the method for that exact operation.

The final architecture is:

- ASDL classes define the vocabulary.
- Typed semantic methods define class-specific compiler behavior.
- Compiler drivers orchestrate stages and pass typed state products, but do not
  own per-class semantics.
- Backend planners and emitters operate on explicit typed facts and typed IR.
- There is no PVM compiler layer, no PVM recording phase abstraction, and no
  compatibility surface that pretends PVM still exists.

## Why This Is Necessary

The current compiler has too much semantic behavior in freeform functions,
external rule tables, and phase-shaped modules. That makes ownership unclear:
to understand one node, you often have to search several driver/rule/lowering
files and mentally reconstruct which table or helper handles it.

This slows down backend work because gaps hide inside dispatch glue instead of
being visible as missing methods on concrete types. It also makes hard-yank
changes dangerous: old behavior can survive through fallbacks, compatibility
shims, or stale rule tables.

The replacement pattern is stricter:

- If a type owns a semantic form, that type owns the lowering/checking method.
- Migrated semantic code must not dispatch on ASDL class identity. No
  `schema.classof(x) == SomeVariant`, no `kind` strings, and no selector tables
  to choose behavior. ASDL union members implement the operation directly; parent
  union methods provide only shared defaults when that is the real semantic
  contract.
- If direct method ownership needs schema/runtime support, add that support to
  ASDL first. Nullary variants are still ASDL classes: install methods with
  `function SomeModule.SomeNullaryVariant:operation(...) ... end`, not by
  inspecting class identity in compiler code.
- If a stage needs state, that state is an explicit typed product with a precise
  name and purpose.
- If a stage crosses an IR boundary, the method name says so explicitly.
- If a class does not support an operation, the compiler fails loudly or returns
  a typed reject/diagnostic. It does not silently fall through old machinery.

## Non-Goals

- [x] Do not preserve `lalin.pvm` as a compatibility alias.
- [x] Do not keep `pvm_erase` migration tooling.
- [ ] Do not rename freeform rule tables and call the job done.
- [ ] Do not create a new generic visitor framework that recreates the same
      indirection.
- [ ] Do not add one universal `lower` method.
- [ ] Do not collapse stage boundaries just to reduce files.
- [ ] Do not hide backend fallback decisions in drivers.
- [ ] Do not force user-facing modules into Lalin; Lua tables remain the native
      composition model.

## Definition Of Done

- [x] No compiler code requires `lalin.pvm`.
- [x] No compiler code requires top-level `pvm`.
- [x] `require("lalin").pvm` is gone.
- [x] `lalin.asdl` is a minimal ASDL runtime, not a phase runtime.
- [x] `pvm.lua`, `pvm_erase.lua`, and `tests/pvm` are gone or moved out of the
      compiler architecture with explicit justification.
- [ ] Per-class semantic behavior lives on ASDL class methods.
- [ ] Old `*_rules.lua` dispatch tables are deleted or listed as remaining
      migration debt in this document.
- [ ] Compiler drivers are thin stage orchestrators.
- [ ] Missing lowering support is visible as a missing method, typed reject, or
      typed diagnostic.
- [ ] Backend fallback choices are explicit typed facts, never hidden control
      flow.
- [ ] The verification gates at the end of this document pass.

## Target Architecture

- [x] `lalin.asdl` is the compiler ASDL runtime.
- [x] `lalin.asdl` exposes only:
  - [x] `context(opts)`
  - [x] `classof(value)`
  - [x] `with(node, overrides)`
  - [x] `singleton(T, class)`
  - [x] minimal sequence/triplet helpers if still needed by compiler code.
- [x] `lalin.asdl` does not expose `phase`.
- [x] `lalin.asdl` does not contain recording caches, memoized phase machinery,
      hit/miss accounting, warm/cached/report APIs, or phase-boundary concepts.
- [x] `lalin.pvm` is deleted.
- [ ] top-level `pvm` compatibility is deleted or moved out of the compiler
      tree if UI still temporarily needs it.
- [x] `lalin.pvm_erase` is deleted.
- [x] `tests/pvm` is deleted or split into correctly named compiler-process
      tests if any still describe real behavior.
- [x] `lalin.init` does not export `M.pvm`.
- [x] public docs no longer tell users or compiler contributors that PVM is part
      of Lalin.
- [ ] LLBL/LLPVM names that contain `pvm` are audited separately. They are not
      automatically the same problem as `lalin.pvm`, but must not leak a PVM
      compiler architecture back into Lalin.

## Current Partial State To Resolve

- [x] Review the in-progress mechanical rename from `lalin.pvm` to
      `lalin.asdl`.
- [x] Keep the useful part: compiler files should depend on `lalin.asdl`, not
      `lalin.pvm`.
- [x] Fix local variable names after the mechanical rename:
  - [x] `local pvm = require("lalin.asdl")` should become `local asdl = ...`
        or `local schema = ...` where practical.
  - [ ] Call sites should read `asdl.classof`, `asdl.context`, `asdl.with`,
        etc. instead of `pvm.classof`.
- [x] Verify `lua/lalin/asdl.lua` is a clean runtime, not a copied PVM file with
      removed pieces.
- [x] Delete any remaining references to `pvm.phase` in compiler code.
- [ ] Delete or quarantine UI references before deleting the old module:
  - [ ] `lua/ui/**`
  - [ ] `lua/mlui/**`
  - [ ] `tests/ui/**`
  - [ ] `tests/mlui/**`
- [ ] Decide whether UI is still in-scope for this repo. If yes, migrate UI to a
      UI-owned runtime name. If no, move/retire it.

## ASDL Runtime Cut

- [x] Create/finish `lua/lalin/asdl.lua`.
- [x] Move only the real ASDL runtime pieces into it:
  - [x] schema context construction through `schema_context.NewContext`
  - [x] `classof`
  - [x] immutable `with`
  - [x] `NIL` sentinel if generated `__with` still needs it
  - [x] sequence helpers only if current compiler code truly uses them
- [x] Remove from the ASDL runtime:
  - [x] `phase`
  - [x] `normalize_handlers`
  - [x] recording cache tables
  - [x] pending/inflight recording entries
  - [x] `cached`
  - [x] `warm`
  - [x] `stats`
  - [x] `hit_ratio`
  - [x] `reuse_ratio`
  - [x] `reset`
  - [x] `report`
  - [x] `report_string`
- [x] Rename errors from `pvm.*` to `asdl.*`.
- [x] Add focused ASDL runtime tests:
  - [x] context builds all schemas
  - [x] `classof` returns classes for nodes and false for non-nodes
  - [x] `with` preserves class and updates immutable fields
  - [x] mutation still errors through generated `__newindex`
  - [x] sequence helpers, if kept, drain/one/concat/children correctly
- [x] Remove old PVM phase tests instead of adapting them.

## Public Surface Hard Yank

- [x] Remove `M.pvm` from `lua/lalin/init.lua`.
- [x] Replace internal `M.pvm.context()` call sites with `asdl.context()`.
- [x] Ensure `require("lalin").pvm` is nil or absent.
- [x] Remove any documented `lalin.pvm` usage.
- [x] Remove any top-level `require("pvm") == require("lalin.pvm")`
      compatibility assertion.
- [x] Remove `tests/pvm` from `tests/run.lua` default and all suites.
- [x] Delete `tests/pvm/test_pvm_erase.lua`.
- [x] Delete `lua/lalin/pvm_erase.lua`.
- [x] Delete `lua/lalin/pvm.lua` only after UI/top-level compatibility is
      explicitly handled.

## Compiler Process And Package Naming Audit

The current `phase_*` files are not necessarily PVM recording phases, but the
name is polluted. Audit them by semantics, not by name.

- [ ] Inspect `lua/lalin/schema/phase.lua`.
- [ ] Decide whether this is still a real compiler package/process model.
- [ ] If real, rename the concept away from `phase`:
  - [ ] candidate: `compiler_step`
  - [ ] candidate: `compiler_process`
  - [ ] candidate: `compiler_transition`
- [ ] If not real, delete it.
- [ ] Audit and either rename or delete:
  - [ ] `lua/lalin/phase_model.lua`
  - [ ] `lua/lalin/phase_dsl.lua`
  - [ ] `lua/lalin/phase_validate.lua`
  - [ ] `lua/lalin/phase_plan.lua`
  - [ ] `lua/lalin/phase_execute.lua`
  - [ ] `lua/lalin/schema/phase.lua`
- [x] Move surviving tests out of `tests/pvm` into a correctly named suite:
  - [x] `tests/compiler_process`
  - [ ] or `tests/compiler_package`
- [ ] Delete tests that only validate the old PVM migration story.

## Typed Semantic Method Design

- [ ] Extend schema class generation so ASDL classes can own semantic methods.
- [x] Choose exact method definition mechanism:
  - [x] direct Lua method assignment on schema class tables
- [x] Method calls use ordinary Lua colon syntax on ASDL values.
- [x] Methods must attach to classes, not to ad hoc external dispatch tables.
- [x] Missing sum-parent methods return nil by default; unsupported leaf
      behavior is absence, not a driver-side dispatch branch.
- [x] Methodization means moving the actual semantic implementation body onto
      the concrete ASDL class. A method that only returns a selector string,
      `kind`, relation name, handler key, or other dispatch token is still the
      old pattern and is not acceptable.
- [ ] Method names must be semantic and typed:
  - [ ] `typecheck_expr`
  - [ ] `typecheck_stmt`
  - [ ] `lower_tree_to_code`
  - [ ] `lower_code_to_back`
  - [ ] `lower_code_to_c`
  - [ ] `plan_kernel`
  - [ ] `plan_schedule`
  - [ ] `lower_luajit`
- [ ] Do not create one giant universal `lower` method.
- [ ] Generic context bags are forbidden. Do not introduce or preserve a vague
      `ctx` object as the default way to move state through semantic methods.
- [ ] Methods receive only the typed, well-named semantic inputs they actually
      need:
  - [ ] no mandatory context argument by convention
  - [ ] no hidden globals
  - [ ] no module-level mutable current context
  - [ ] if an operation needs bindings, pass the typed binding/type environment
  - [ ] if an operation needs return/yield expectations, pass a named typed
        expectation/state value
  - [ ] if an operation needs nothing, pass nothing
- [ ] Methods return typed ASDL results or diagnostics directly, not informal
      tuples and not phase-shaped wrappers.

## Lowering Conventions

These conventions are mandatory for the rewrite. A lowering is not acceptable
just because it works on one fixture; it must fit this shape.

### Ownership

- [ ] The class that owns the source semantic form owns the lowering method.
- [ ] A lowering method belongs on the source class, not the destination class.
      Example: a `LalinTree.ExprBinary` lowers itself to `LalinCode`; a
      `LalinCode.ValueExprBinary` does not reach backward into tree syntax.
- [ ] Cross-cutting orchestration may live in driver modules, but per-class
      behavior may not live in driver modules.
- [ ] Drivers may sequence work, allocate context, collect diagnostics, and
      choose backend mode. Drivers may not contain large `if class == ...`
      semantic ladders.
- [ ] Helper functions are allowed only when they implement shared mechanics,
      not when they hide class-specific lowering behind another dispatch table.
- [ ] Do not replace a rule table with class methods that return `kind`,
      selector names, relation names, or handler keys. The class method must do
      the work for that class and return the operation's real result shape.

### Naming

- [ ] Method names must state both source stage and destination stage.
- [ ] Use `lower_<source>_to_<dest>` for representation changes.
- [ ] Use `check_<domain>` or `validate_<domain>` for validation that preserves
      representation.
- [ ] Use `plan_<domain>` for planning facts that choose strategies but do not
      emit destination IR.
- [ ] Use `emit_<target>` only for textual/binary emission from an already
      target-shaped IR.
- [ ] Avoid generic names:
  - [ ] no class method named just `lower`
  - [ ] no class method named just `emit`
  - [ ] no class method named just `visit`
  - [ ] no class method named just `handle`
- [ ] Preferred operation names:
  - [ ] `typecheck_tree_expr`
  - [ ] `typecheck_tree_stmt`
  - [ ] `lower_tree_expr_to_code`
  - [ ] `lower_tree_place_to_code`
  - [ ] `lower_tree_stmt_to_code`
  - [ ] `lower_code_type_to_back`
  - [ ] `lower_code_value_to_back`
  - [ ] `lower_code_place_to_back`
  - [ ] `lower_code_inst_to_back`
  - [ ] `lower_code_type_to_c`
  - [ ] `lower_code_value_to_c`
  - [ ] `plan_code_kernel`
  - [ ] `plan_code_schedule`
  - [ ] `plan_exec_fragment`
  - [ ] `lower_code_to_luajit`
  - [ ] `emit_luajit_lua`
  - [ ] `emit_c_source`

### Signatures

- [ ] Lowering methods take only the typed inputs required by the operation.
- [ ] There is no default `ctx` parameter.
- [ ] Example signatures:
      `function T.LalinCore.LitInt:typecheck_tree_literal() ... end`
      `function T.LalinBind.ValueRefName:typecheck_tree_ref(input) ... end`
      `function T.LalinTree.StmtReturnValue:typecheck_tree_stmt(input) ... end`
- [ ] The node is always `self`.
- [ ] Any non-node argument must be a named typed semantic product, not a bag of
      unrelated state.
- [ ] No lowering method reads or writes module-level mutable compiler state.
- [ ] No lowering method mutates `self`.
- [ ] No lowering method mutates any ASDL node.
- [ ] Structural changes use `asdl.with(node, overrides)` or construct a new
      typed node.
- [ ] Methods must not mutate generic context/state objects. State changes are
      represented by returning typed products.

### Return Shape

- [ ] Every lowering operation has one documented return shape.
- [ ] A representation-changing lowering returns the destination ASDL node or a
      typed result wrapper.
- [ ] Validation returns a typed validation report or appends typed diagnostics
      through the context and returns the original node where appropriate.
- [ ] Planning returns typed plan facts, typed rejects, or a typed plan result.
- [ ] Lowering methods must not return ambiguous `nil, reason` pairs unless the
      operation is explicitly an optional probe.
- [ ] Optional probes must be named as probes:
  - [ ] `try_plan_*`
  - [ ] `probe_*`
  - [ ] `classify_*`
- [ ] Required lowering failure must be a typed diagnostic or a hard internal
      compiler error with class and operation in the message.
- [ ] Do not mix boolean status, string reasons, and ASDL values in one return
      slot.
- [ ] Do not return one-element arrays or phase/stream wrappers such as
      `single(result)` from migrated semantic methods. Return the typed result
      directly.

### Diagnostics

- [ ] User/source errors produce typed diagnostics.
- [ ] Internal invariant failures use `error(...)`.
- [ ] Diagnostic construction belongs near the semantic operation that detects
      the problem.
- [ ] Diagnostics must include:
  - [ ] operation name
  - [ ] source class
  - [ ] source origin/span when available
  - [ ] expected semantic form
  - [ ] actual semantic form
- [ ] Lowering must not silently fall back to generic behavior when a typed
      method is missing.
- [ ] Missing method is a compiler bug, not a recoverable user error.

### Dispatch

- [ ] Dispatch is method lookup on the ASDL class.
- [ ] No new external `by_class` dispatch tables.
- [ ] No new `rules.lua` files.
- [ ] No generated giant `if cls == ... elseif ...` chains.
- [ ] No selector-method detours:
  - [ ] no `node:*_kind()` methods used to choose a later branch
  - [ ] no `node:*_handler()` methods used to choose a later table entry
  - [ ] no `node:*_relation()` methods used to call a generic runner
  - [ ] no `Rules:run(...)`, relation/input/output wrappers, or compatibility
        runners for newly migrated operations
- [ ] Sum-type routing should be expressed by installing methods on every
      concrete member class that supports the operation.
- [ ] If an operation is illegal for a class, install no method and let the
      required-call helper report a precise missing-method compiler error.
- [ ] If an operation is legal but semantically rejected for this node, return a
      typed reject/diagnostic from the method.

### Method Definition

- [x] Method definition is per ASDL context because schema classes are per
      context.
- [x] Direct method assignment uses normal Lua replacement semantics.
- [ ] Method modules must be named by semantic stage:
  - [ ] `tree_typecheck_methods.lua`
  - [ ] `tree_to_code_methods.lua`
  - [ ] `code_to_back_methods.lua`
  - [ ] `code_to_c_methods.lua`
  - [ ] `kernel_plan_methods.lua`
  - [ ] `schedule_plan_methods.lua`
  - [ ] `exec_plan_methods.lua`
  - [ ] `luajit_lower_methods.lua`
  - [ ] `c_emit_methods.lua`
- [x] Current typecheck method modules return a schema-context function, not a
      mutable global table.
- [x] Current typecheck method module shape:
      `return function(T) ... end`
- [x] Current typecheck method modules receive the schema context and assign
      methods directly.
- [ ] The module must not create a new schema context.

### Typed State Products

- [ ] Do not introduce generic stage context bags.
- [ ] Stage state, when needed, is represented as explicit typed ASDL products
      with narrow names and fields.
- [ ] Typed state products may contain environment, diagnostics, generated names,
      or target facts only when those fields are part of that product's precise
      semantic contract.
- [ ] Typed state products do not own per-class semantics.
- [ ] Do not add state-product helpers named like semantic lowering for one
      class.
- [x] No required-method lookup API remains in the ASDL runtime.

### Stage Boundaries

- [ ] Each lowering method crosses exactly one stage boundary.
- [ ] Do not lower `Tree -> Back` directly.
- [ ] Do not lower `Tree -> LuaJIT` directly.
- [ ] Do not lower `Code -> C source text` directly; go through C backend IR
      unless the method is explicitly an emitter for C IR.
- [ ] Valid stage boundaries:
  - [ ] parsed syntax to `LalinTree`
  - [ ] `LalinTree` typechecking
  - [ ] typed `LalinTree` to `LalinCode`
  - [ ] `LalinCode` facts/plans
  - [ ] `LalinCode` to `LalinBack`
  - [ ] `LalinCode` to `LalinC`
  - [ ] `LalinCode` plus plans to `LalinLuaJIT`
  - [ ] `LalinC` to C source
  - [ ] `LalinLuaJIT` to Lua source/artifact
- [ ] Backend artifact selection is orchestration, not a method on random
      syntax nodes.

### Fallbacks

- [ ] No hidden compatibility fallback.
- [ ] No BC fallback inside the MC path.
- [ ] MC can emit residuals; residuals are not BC fallback.
- [ ] Fallback must be a named, typed strategy in the plan if it exists at all.
- [ ] A missing stencil/artifact method must return typed reject or internal
      compiler error, not silently choose another backend.
- [ ] Any fallback path must be visible in facts and tests.

### Tests For Lowering Conventions

- [ ] Add tests that installing duplicate methods fails.
- [ ] Add tests that missing required method fails with class+operation.
- [ ] Add tests that method calls do not mutate source ASDL nodes.
- [ ] Add tests that method assignments are isolated across two schema contexts.
- [ ] Add tests that no new `*_rules.lua` files are introduced.
- [ ] Add tests that no new `by_class` tables are introduced in compiler code.
- [ ] Add tests that backend fallback decisions are represented as typed facts.

## Rule Table Migration

These are the current freeform rule/dispatch modules to eliminate or shrink.

- [x] `lua/lalin/tree_typecheck_rules.lua`
  - [x] Delete external expression/statement rule tables.
  - [x] Move literal/ref/expression-expected behavior onto ASDL methods.
  - [x] Move type-owned policy/canonicalization/layout helpers onto ASDL methods.
  - [x] Move module fact collection to explicit ASDL methods and
        `TypeModuleFacts`.
  - [x] Remove hidden raw fact fields from the typecheck driver.
  - [x] Move remaining statement/place/control behavior onto concrete ASDL methods.
  - [x] Reduce `tree_typecheck.lua` to stage entrypoints and typed orchestration.
- [x] `lua/lalin/tree_to_code_rules.lua`
  - [x] Move tree-to-code lowering for expressions onto expression classes.
  - [x] Move place lowering onto place classes.
  - [x] Move statement lowering onto statement classes.
  - [x] Delete external tree-to-code rule dispatch tables.
- [x] `lua/lalin/code_kernel_plan_rules.lua`
  - [x] Move kernel classification behavior onto relevant `LalinCode`,
        `LalinKernel`, and `LalinFlow` classes.
  - [x] Keep graph-wide analysis as orchestration only.
- [x] `lua/lalin/code_schedule_plan_rules.lua`
  - [x] Move schedule legality/selection behavior onto schedule/target/stencil
        classes.
- [x] `lua/lalin/code_lower_plan_rules.lua`
  - [x] Move lower-plan behavior onto lower-plan and exec strategy classes.
- [x] `lua/lalin/lower_strategy_emit_rules.lua`
  - [x] Move strategy emission behavior onto lower strategy classes.
- [x] `lua/lalin/exec_plan_rules.lua`
  - [x] Move exec fragment planning onto exec/stencil/residual classes.
- [x] `lua/lalin/luajit_lower_rules.lua`
  - [x] Add typed LuaJIT kernel and skeleton lowering selection ASDL.
  - [x] Add typed `StencilMachineSkeletonPlan` and skeleton reduction wrappers.
  - [x] Move LuaJIT kernel/skeleton lowering selection onto direct ASDL
        methods in `lua/lalin/luajit_lower.lua`.
  - [x] Delete `tests/code_ir/test_luajit_lower_rules.lua`.
  - [x] Add `tests/code_ir/test_luajit_lower_methods.lua`.
- [x] `lua/lalin/stencil_rules.lua`
  - [x] Move stencil-machine planning schema out of `LalinLuaJIT` and into
        `LalinStencilMachine`.
  - [x] Delete the public `stencil_rules` module/export name and relation
        runner surface.
  - [x] Replace legacy stencil selection `{ kind, vocab, op, info, args }`
        tables with `StencilMachineSelected` ASDL leaves.
  - [x] Replace selected-info bags with leaf-specific stencil-machine payload
        ASDL values.
  - [x] Split pure vocabulary legality from lowering behavior.
  - [x] Attach stencil expression/sink legality to stencil classes.
  - [x] Keep global saturation vocabulary as data, not rule-table control flow.
  - [x] Replace raw expression binding/seen tables with
        `StencilMachineExprBindings` and `StencilMachineExprFactInput`.
  - [x] Move stencil expression fact construction onto `KernelExpr` and
        `ValueExpr` ASDL leaf methods.
  - [x] Return typed `StencilMachineStorePlan` and
        `StencilMachineReducePlan` values instead of ad hoc plan tables.
  - [x] Return typed `StencilMachineIndexLane` values from stencil-machine
        index-lane selection instead of plain Lua tables.
  - [x] Add schedule leaf methods for vectorization facts so scalar schedules
        do not expose absent `facts` fields through method fallback.
  - [x] Add kernel-plan leaf methods for reject reporting so `KernelPlanned`
        is not probed for `KernelNoPlan` fields.

## Major Lowering Modules To Refactor Around Methods

- [ ] `lua/lalin/tree_typecheck.lua`
  - [ ] remains orchestration and context
  - [ ] stops owning per-class semantics
  - [x] Remove duplicate unsafe list helper that bypassed nil-tolerant
        collection.
  - [x] Move `TypeValueScope` and `TypeStmtInput` methods into
        `tree_typecheck_fact.lua`.
  - [x] Move contract typing onto `FuncContract` leaf methods.
  - [x] Add missing expression/index leaf methods in
        `tree_typecheck_expr.lua` for unary, logic, machine casts,
        address/deref/len, and index expressions.
  - [x] Move unary, binary, logic, deref, len, and index type behavior onto
        operator/type leaf methods.
  - [x] Remove dead operator/cast/atomic helper dispatch from the coordinator.
- [ ] `lua/lalin/tree_to_code.lua`
  - [x] remains module/function lowering driver
  - [x] delegates typed operations to node methods
  - [ ] Replace remaining `ctx`/`module_ctx` driver bags with precise typed
        Tree-to-Code ASDL input/state/result products.
        - [x] Added typed Tree-to-Code module facts/state fields, function
              registrations, variant definitions, local binding snapshots,
              block builders, and control-region state to the ASDL schema.
        - [x] Split constant Tree-to-Code module facts from phase-resolved
              module state: `TreeCodeModuleFacts` owns module name, layout
              environment, target, constant environment, and variant
              definitions; `TreeCodeModuleSigState`,
              `TreeCodeModuleRegistrationState`, and
              `TreeCodeModuleEmissionState` own signatures, registrations,
              externs, generated data, and counters.
        - [x] `build_module_parts` constructs separate module facts/signature/
              registration/emission ASDL products; function registrations and
              variant definitions use typed ASDL products instead of raw
              registration tables.
        - [x] Tree-to-Code function-local binding snapshots and local binding
              entries now use typed ASDL products.
        - [x] Function lowering now constructs `TreeCodeFuncFacts` and
              `TreeCodeFuncState` ASDL values; block assembly, counters,
              binding snapshots, locals, alpha scopes, and active control
              regions are changed through installed state/input methods instead
              of a raw driver table.
        - [x] Tree-to-Code mutable state products are not interned; function
              blocks, locals, counters, and generated module data no longer
              share empty ASDL collection tables across functions.
        - [x] Split `TreeCodeFuncState` into named binding, residence,
              emission, counter, alpha-renaming, and control-state ASDL
              products instead of top-level side maps and slots.
        - [x] Expression, place, and statement lowering leaf methods now receive
              typed `TreeCodeExprInput`, `TreeCodePlaceInput`, and
              `TreeCodeStmtInput` products instead of the function state object
              directly.
        - [x] Removed free helper lowering entrypoints such as `lower_expr`,
              `lower_place`, `lower_call`, `lower_stmt_if`,
              `lower_stmt_switch`, `lower_expr_if`, `lower_expr_switch`,
              `lower_control_region`, `lower_variant_binds`, and
              `lower_func`; call sites now invoke installed ASDL methods
              directly.
        - [ ] Convert remaining mutable state methods on `TreeCodeFuncState`
              and Tree-to-Code input products into typed state/result-returning
              methods instead of in-place updates.
- [x] `lua/lalin/code_to_back.lua`
  - [x] Finish the remaining `CodeInst.kind` / `CodeTerm.kind` wrapper schema
        debt: wrapper fields are now named `op`, and compiler consumers no
        longer reach through a generic `kind` field for Code IR instruction or
        terminator payloads.
  - [x] methodize type, place, expr, inst lowering
  - [x] Added explicit `CodeBack*` ASDL products for module facts, function
        facts, function state, instruction input, terminator input, place input,
        state result, and place result.
  - [x] Added typed Code-to-Back value/address/memory result products for
        helpers that produce Back values, addresses, or synthetic memory facts
        while threading `CodeBackFunctionState`.
  - [x] `CodeInst` lowering now delegates through `CodeInstOp` ASDL leaf
        methods; the central instruction-kind class ladder is removed.
  - [x] `CodeTerm` lowering now delegates through `CodeTermOp` ASDL leaf
        methods; the central terminator-kind class ladder is removed.
  - [x] `CodeDataInit`, `CodeGlobalRef`, and `CodeCallTarget` lowering now live
        on their concrete ASDL leaves.
  - [x] Removed the `ctx`/context adapter from `Code -> Back` semantic methods;
        instruction and terminator methods receive typed ASDL inputs and read
        module/function facts from `input.module` and `input.func`.
  - [x] `CodePlace` address and address-of lowering now use typed
        `CodeBackPlaceInput` and return `CodeBackPlaceResult` /
        `CodeBackStateResult` instead of receiving loose state/info arguments.
  - [x] Driver-local Code-to-Back orchestration table is named `lowering`; ASDL
        semantic methods only use `input.state` for `CodeBackFunctionState`.
  - [x] `CodeBackFunctionState` now carries named aggregate, closure,
        local-slot, and temporary-counter state products; module readonly
        lowering facts are carried by `CodeBackReadonlyProjection`.
  - [x] Renamed the last Code-to-Back `make_ctx` boundary to
        `make_lowering`; no `ctx` identifier remains in the file.
  - [x] Remove the temporary Code-to-Back builder adapter and replace command/
        scratch mutation with returned `CodeBackFunctionState` values.
        - [x] Deleted `code_back_lowering`, rawset state pollution, and generic
              `code_back_read`/`code_back_write_state` accessors.
        - [x] `CodeBackFunctionState` now owns named update methods for command
              append, aggregate value/local facts, closure-capture facts, and
              local stack slots; function/fragment drivers sync from
              `CodeBackStateResult` values.
        - [x] Direct semantic writes to `state.cmds`, aggregate scratch maps,
              closure-capture maps, and local stack-slot maps are removed.
        - [x] Temporary-value, address, and synthetic-memory helpers now return
              typed value/address/memory result products carrying the updated
              `CodeBackFunctionState`; direct `next_tmp` mutation is removed
              from semantic helpers.
  - [x] Move remaining helper class checks for memory facts, address bases,
        type properties, field refs, and lower covers onto ASDL leaf methods.
  - [x] Core literal, Code const, binary/unary/compare/cast/intrinsic, atomic
        ordering, and atomic RMW Back opcode selection live on ASDL leaf
        methods instead of helper dispatch.
  - [x] `CodePlace` address formation and address-of lowering delegate to
        concrete place methods instead of dispatching on place class.
  - [x] Move `CodeInstOp` lowering out of the instruction driver ladder and
        onto concrete instruction-kind methods.
  - [x] Move `CodeTermOp` lowering out of the terminator driver ladder and
        onto concrete terminator-kind methods.
- [ ] `lua/lalin/code_to_c.lua`
  - [ ] methodize C backend projection
- [ ] `lua/lalin/lower_to_back.lua`
  - [ ] methodize semantic-to-back lowering
- [ ] `lua/lalin/lower_to_c.lua`
  - [ ] methodize semantic-to-C lowering
- [ ] `lua/lalin/luajit_lower.lua`
  - [x] methodize kernel/skeleton stencil lowering selection
  - [x] remove remaining ad hoc stencil-machine input table from index-lane
        lowering
  - [ ] methodize remaining code/LJ/stencil lowering where class-specific
  - [ ] keep artifact selection orchestration separate
- [ ] `lua/lalin/luajit_emit.lua`
  - [ ] methodize LJ expression/place/stmt emission or create explicit emitter
        methods on LJ classes
- [ ] `lua/lalin/c_emit.lua`
  - [ ] methodize C AST emission or use explicit emitter methods on C classes
- [ ] `lua/lalin/c_validate.lua`
  - [ ] methodize class-specific validation
- [ ] `lua/lalin/code_validate.lua`
  - [ ] methodize class-specific validation
- [ ] `lua/lalin/kernel_validate.lua`
  - [ ] methodize class-specific validation

## Schema Method Work

- [x] ASDL classes are Lua tables that accept direct method assignment.
- [x] Sum parent class assignment propagates to member classes.
- [x] Sum parent classes provide nil-returning default methods to variants.
- [ ] Decide where semantic method modules are loaded:
  - [ ] during frontend/backend module require
  - [ ] explicitly through compiler initialization
- [x] Ensure multiple contexts keep method assignments isolated.
- [x] Ensure generated class builders remain pure and do not capture stale
      method state from another context.

## Tests To Rewrite

- [x] Delete `tests/pvm`.
- [x] Add `tests/asdl`:
  - [x] runtime basics
  - [x] direct class method assignment
  - [x] method dispatch failure diagnostics
  - [x] multiple context isolation
- [x] Rewrite rule tests as behavior tests:
  - [x] `tests/frontend/test_tree_typecheck_rules.lua`
  - [x] `tests/frontend/test_tree_to_code_methods.lua`
  - [x] `tests/code_ir/test_code_kernel_plan_methods.lua`
  - [x] `tests/code_ir/test_code_schedule_plan_methods.lua`
  - [x] `tests/code_ir/test_code_lower_plan_methods.lua`
  - [x] `tests/code_ir/test_lower_strategy_emit_methods.lua`
  - [x] `tests/code_ir/test_exec_plan_methods.lua`
  - [x] `tests/code_ir/test_luajit_lower_methods.lua`
- [ ] Keep end-to-end tests as the main safety net:
  - [ ] parsed source to artifact
  - [ ] DSL to artifact
  - [ ] MC backend
  - [ ] emit C path
  - [ ] bank generator/intern set
- [x] Remove tests that assert implementation shape of old dispatch tables.
- [x] Add tests that assert no PVM compiler surface:
  - [x] `require("lalin.pvm")` fails
  - [x] `require("lalin").pvm == nil`
  - [x] no `pvm.phase` in `lua/lalin`
  - [x] no `require("pvm")` in compiler code

## Documentation Rewrite

- [x] Update `AGENTS.md`.
- [x] Update `docs/ARCHITECTURE.md`.
- [ ] Update `docs/LANGUAGE_REFERENCE.md` only where implementation model leaks.
- [ ] Update `docs/DESIGN_BIBLE.md` or mark old PVM theory as retired.
- [ ] Update `docs/LLPVM_GUIDE.md` only if LLPVM naming changes.
- [x] Update `tests/README.md`.
- [x] Remove references to:
  - [ ] PVM compiler phases
  - [x] PVM erase migration
  - [x] `lalin.pvm`
  - [x] top-level `pvm` compatibility
- [x] Add a concise architecture section:
  - [x] ASDL runtime
  - [x] typed semantic methods
  - [x] compiler orchestration
  - [x] backend artifact selection

## Verification Gates

- [x] `rg -n 'require\\("lalin\\.pvm"\\)|require\\('\\''lalin\\.pvm'\\''\\)' lua tests tools docs`
      returns nothing outside this checklist.
- [x] `rg -n 'require\\("pvm"\\)|require\\('\\''pvm'\\''\\)' lua/lalin lua/llpvm tests tools`
      returns nothing outside UI/mlui/retired surfaces tracked above.
- [x] `rg -n 'pvm\\.phase|phase\\(' lua/lalin` has no PVM recording-phase hits.
- [x] `rg -n 'M\\.pvm|\\.pvm\\b' lua/lalin docs tests` has no Lalin public
      API hits outside this checklist and the separately tracked LLPVM member
      surface.
- [x] `rg -n '_rules' lua/lalin` only shows files that are intentionally still
      waiting in the migration checklist.
- [x] `luajit tests/run.lua asdl`
- [x] `luajit tests/run.lua frontend`
- [x] `luajit tests/run.lua code_ir`
- [x] `luajit tests/run.lua c_backend`
- [x] `luajit tests/run.lua schema`
- [x] `luajit tests/run.lua runtime`
- [x] `luajit tests/run.lua tooling`
- [x] `luajit tests/run.lua`
- [ ] Slow binary gate when needed:
  - [ ] `LALIN_RUN_SLOW=1 luajit tests/run.lua code_ir`

## Suggested Rewrite Order

- [x] 1. Freeze the target API in `lalin.asdl`.
- [x] 2. Replace compiler `lalin.pvm` imports with `lalin.asdl` imports and sane
      local names.
- [x] 3. Delete PVM erase and PVM phase tests.
- [x] 4. Remove `M.pvm` and public PVM docs.
- [ ] 5. Isolate or retire UI/top-level `pvm` usage.
- [x] 6. Add ASDL direct method support.
- [x] 7. Finish `tree_typecheck.lua` method rewrite after deleting `tree_typecheck_rules.lua`.
- [x] 8. Migrate `tree_to_code_rules.lua`.
- [x] 9. Migrate code/kernel/schedule/lower/exec rule modules.
- [ ] 10. Migrate LuaJIT/C/backend lowering emitters.
- [x] 11. Delete rule modules as each reaches zero real ownership.
- [ ] 12. Run the full verification gates and update architecture docs.
