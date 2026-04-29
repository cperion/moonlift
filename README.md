# moonlift

Current Moonlift compiler/runtime workspace.

This directory is the promoted ASDL/PVM implementation formerly developed as
`moonlift2/`. The older Moonlift implementations have been moved under
`archive/moonlift_legacy_2026_04_26/`. Moonlift now owns its PVM/ASDL support
libraries internally under `lua/moonlift/` and exposes them as `moonlift.pvm`,
`moonlift.triplet`, `moonlift.asdl_context`, `moonlift.asdl_parser`,
`moonlift.asdl_lexer`, and `moonlift.quote`.

Moonlift is built around:

```text
stable spines
  + phase facets
  + explicit facts
  + explicit decisions/proofs/rejects
  + flat backend commands
```

## Current contents

- `lua/moonlift/pvm.lua`, `triplet.lua`, `asdl_context.lua`, `asdl_parser.lua`,
  `asdl_lexer.lua`, `quote.lua`
  - Internal Moonlift PVM/ASDL/quote support libraries. Root-level files with
    the same names, plus `moonlift.lua`, are compatibility shims only.
- `lua/moonlift/std.lua`, `lua/moonlift/builtins.lua`
  - Public standard-library facade. `require("moonlift").json` exposes the
    indexed-tape JSON library/projection path; `require("moonlift").builtins`
    exposes builtin Moonlift library sources/compilation hooks.
- `lua/moonlift/asdl.lua`
  - ASDL2 schema draft organized by explicit abstraction/layer modules:
    - `Moon2Core` — shared atoms, ids, scalar kinds, operators, intrinsics
    - `Moon2Back` — lowest flat executable backend command/fact layer, now with
      the first fact-rich backend schema slice for canonical target facts,
      address/provenance, memory access facts, alias relations, and split
      arithmetic semantic domains
    - `Moon2Type` — reusable language type spine
    - `Moon2Open` — open-code slots, fragments, fills, validation, rewrite facts
    - `Moon2Bind` — bindings, value refs, residence decisions, env facets
    - `Moon2Sem` — semantic facts/classes/decisions, layout and const values
    - `Moon2Tree` — common source/typed/open/sem/code recursive spines, now centered on jump-first `Control*` block regions and named `JumpArg` values instead of old loop/`next` primitives
    - `Moon2Vec` — vector/code-shape fact gathering, alias/dependence facts, proofs, decisions, IR
    - `Moon2Host` — hosted-value API construction issues plus explicit host layout/view/access/exposure facts
- `lua/moonlift/ast.lua`
  - Public ASDL-backed source constructor facade exposed as `require("moonlift.ast")`
    and `require("moonlift").ast`.  It binds to an existing compiler context with
    `ast.new(T)` / `ast.Define(T)` or provides a standalone default context for
    hosted code generation.  The LuaLS annotations on each constructor document
    the user-authored fields of the corresponding `Moon2Core` / `Moon2Type` /
    `Moon2Tree` source node; derived typed/semantic/backend fields remain
    excluded and are produced only by later PVM phases.
- `ASDL2_REFACTOR_MAP.md`
  - Historical/lossless refactor map that guided the ASDL2 promotion into the
    current `lua/moonlift/asdl.lua` schema.
- `FILE_NAMING.md`
  - File naming discipline: implementation files mirror ASDL modules, type
    families, phase verbs, facts, and decisions.
- `LANGUAGE_REFERENCE.md`
  - Complete single-file Moonlift language reference: `.mlua` hosting, Lua
    metaprogramming, monomorphic object code, hosted declarations, `as(T,
    value)`, typed regions, emits, jumps, switches, fragments, views, host ABI,
    and builder API.
- `SOURCE_GRAMMAR.md`
  - Jump-first Moonlift source grammar draft.  Moonlift does not inherit the
    old `for`/`while`/`loop`/`next` syntax as a primitive; authored control flow
    is based on typed blocks, named typed `jump` arguments, and `yield` /
    `return` exits.
- `HOST_VALUE_API_DESIGN.md`
  - Design target and implementation checklist for Terra-like hosted value
    niceties: ASDL-backed type/struct/expression/function/module/region values,
    direct builders, recursive draft structs, Lua-hosted templates over explicit
    type slots/fills, and reflection through explicit PVM phase decisions.
- `HOST_VIEW_ZERO_COPY_ABI_DESIGN.md`
  - Full design and checklist for `.mlua` as the integrated hosted language:
    top-level structs, name-first per-target-facet exposes, regions, loops,
    methods, functions, Moonlift `view(T)` semantics, `Moon2Host`
    layout/access/exposure facts, and zero-copy
    Lua/Terra/C boundary descriptors. The first PVM phase set is now
    implemented in `mlua_parse.lua`, `mlua_source_normalize.lua`,
    `mlua_region_typecheck.lua`, `mlua_loop_expand.lua`,
    `mlua_host_pipeline.lua`, `host_decl_values.lua`,
    `host_decl_parse.lua`, `host_layout_resolve.lua`, `host_view_abi_plan.lua`,
    `host_access_plan.lua`, the host emit-plan phases, and
    `tree_field_resolve.lua`. `host_quote.lua` is the LuaJIT-first hosted-island
    bridge for runnable `.mlua` files: ordinary Lua syntax is left to LuaJIT,
    while only Moonlift islands such as `struct`, `expose`, `func`, `module`,
    module-local regions, counted-loop sugar, and typed antiquote splices are
    rewritten to ASDL-producing calls. Each loaded chunk gets a `HostRuntime`
    with one ASDL context and an accumulated `HostDecl` fact stream. Lua methods
    use ordinary top-level Lua `function Type:name(...)` and are recorded by the
    hosted runtime after LuaJIT assignment; Moonlift methods use
    `func Type:name(...)`.
- `LSP_INTEGRATION_DESIGN.md`, `LSP_INTEGRATION_CHECKLIST.md`
  - Complete ASDL/PVM design and detailed work checklist for integrating the
    `.mlua` language server into the canonical Moonlift schema. The design makes
    LSP results downstream of `MluaParseResult`, `MluaHostPipelineResult`,
    source anchors, and existing compiler facts; lexical island recognition is
    only a source-map layer.
- `SCAN_FUSOR_DESIGN.md`
  - Complete design proposal for a `Moon2Scan` ASDL parser/lexer/scanner fusor:
    parser-combinator hosted builders, explicit input/output/diagnostic/recovery
    values, token materialization policy, fusion facts/rejects/decisions,
    lowering to `Moon2Open.RegionFrag`, domain targets such as JSON projection,
    CSV/schema parsing, logs, protocols, source parsers, and a phased
    implementation plan.
- `lua/moonlift/source_text_apply.lua`, `source_position_index.lua`,
  `source_anchor_index.lua`, `editor_workspace_apply.lua`,
  `editor_transition.lua`, `mlua_document_parts.lua`,
  `mlua_island_parse.lua`, `mlua_document_parse.lua`,
  `mlua_document_analysis.lua`, `editor_diagnostic_facts.lua`,
  `editor_symbol_facts.lua`, `editor_binding_facts.lua`, `editor_definition.lua`,
  `editor_references.lua`, `editor_rename.lua`, `editor_document_highlight.lua`,
  `editor_subject_at.lua`, `editor_hover.lua`, `editor_completion_context.lua`,
  `editor_completion_items.lua`, `editor_signature_help.lua`,
  `editor_semantic_tokens.lua`,
  `editor_folding_ranges.lua`, `editor_selection_ranges.lua`,
  `editor_inlay_hints.lua`, `editor_code_actions.lua`, `lsp_payload_adapt.lua`,
  `lsp_capabilities.lua`, `rpc_json_decode.lua`,
  `rpc_json_encode.lua`, `rpc_lsp_decode.lua`, `rpc_lsp_encode.lua`,
  `rpc_out_commands.lua`, `rpc_stdio_loop.lua`, `lsp.lua`
  - Integrated LSP/source-map implementation chunks: canonical `Moon2Source`
    document/edit/range/anchor values, UTF-16-aware position indexes, pure
    workspace `Apply(state,event)->state`, `.mlua` document segmentation into Lua
    opaque spans and hosted islands, island/document parsing through the existing
    `.mlua` parser, host-pipeline-backed document analysis that now also runs
    module open validation, typecheck, control facts, vector decisions/rejects,
    and backend validation where meaningful, plus editor facts for diagnostics,
    document/workspace symbols, binding-backed definition/
    references/highlights/rename, subject lookup, hover, completion, signature
    help, semantic tokens, folding ranges, selection ranges, parameter inlay
    hints, and diagnostic-origin-backed code actions, plus stdio JSON-RPC/
    LSP transport over flat `Moon2Rpc.OutCommand` values. The segmenter
    mirrors `host_quote.lua` island boundaries and produces `IslandText` content
    identities without source offsets so moved islands can keep semantic cache
    identity.
- `IMPLEMENTATION_CHECKLIST.md`
  - Bottom-up implementation checklist derived from the ASDL layers.
- `lua/moonlift/project_asdl.lua`, `project_ready_facts.lua`, `project_report.lua`
  - ASDL-backed task/project model with ready/blocked/done/deferred facts and
    reports.
- `lua/moonlift/core_scalar.lua`
  - `Moon2Core.Scalar` family/bit-width classification facts.
- `lua/moonlift/core_operator.lua`
  - Explicit op/intrinsic class decisions for core unary/binary/compare/
    intrinsic variants.
- `lua/moonlift/back_program.lua`
  - Pure construction conveniences for flat `Moon2Back.BackProgram` values:
    `empty`, `program`, `singleton`, `append`, `extend`, `concat`, and `cmds`.
    These helpers copy command arrays and do not hide semantic decisions.
- `lua/moonlift/back_command_tape.lua`
  - Deterministic `BackCommandTape` encoding of `Moon2Back.BackProgram` command
    streams.  The tape is an encoding of the ASDL stream, not a hidden backend
    IR.
- `lua/moonlift/back_target_model.lua`
  - Canonical executable target-model helpers: default Cranelift/native
    `BackTargetModel`, plus derived `Moon2Host.HostTargetModel` and
    `Moon2Vec.VecTargetModel` facets.
- `lua/moonlift/back_inspect.lua`
  - ASDL-backed backend inspection reports for command counts, target models,
    address/provenance and pointer-offset formation facts, memory facts, alias
    relations, and int/float semantic facts.
- `lua/moonlift/back_diagnostics.lua`
  - Combined backend/vector diagnostics with optional JIT disassembly capture for
    benchmark kernels. Current benchmark notes live in `BENCHMARK_RESULTS.md`.
- `lua/moonlift/vec_inspect.lua`
  - ASDL-backed vector inspection reports for loop legality and explicit vector
    schedules.
- `lua/moonlift/back_validate.lua`
  - First `Moon2Back` implementation slice: gathers flat backend program facts
    and returns an ASDL `BackValidationReport`. It now also validates the first
    fact-rich backend slice: explicit address/provenance load/store commands,
    `BackMemoryInfo` access modes/alignment/dereference coverage, and relational
    alias access references.
- `lua/moonlift/back_jit.lua`
  - Direct `Moon2Back.BackProgram` execution through deterministic
    `BackCommandTape` transport into the retained Rust/Cranelift backend.  This
    is the active executable backend boundary and removes the former
    `Moon2Back -> MoonliftBack` bridge from the compile path.  Active Lua→Rust
    compilation now uses one `moonlift_jit_compile_tape` call instead of
    per-command FFI replay.  The Rust tape decoder reconstructs executable
    `BackCmd` values from the ASDL tape, preserving memory, arithmetic, vector,
    address-formation, and schedule-selected command facts that Cranelift can
    consume and ignoring only validation/scheduling evidence that has no direct
    Cranelift representation.
- `lua/moonlift/type_classify.lua`
  - `Moon2Type.Type -> Moon2Type.TypeClass` classification.
- `lua/moonlift/type_to_back_scalar.lua`
  - Direct scalar/pointer/function type classification to `Moon2Back.BackScalar`
    result values.
- `lua/moonlift/type_size_align.lua`
  - Type memory-layout result facts for scalars, pointers, descriptors, arrays,
    closures, and named layouts.
- `lua/moonlift/type_abi_classify.lua`
  - Explicit ABI decisions for ignore/direct/indirect/descriptor/unknown type
    passing classes.
- `lua/moonlift/type_func_abi_plan.lua`
  - Function-level executable ABI plans. This is the single source of truth for
    expanding internal `view(T)` params to `(data: ptr, len: index, stride:
    index)` backend values, assigning deterministic argument bindings/value ids,
    and using out-descriptor pointers for `view(T)` returns.
- `lua/moonlift/open_facts.lua`
  - Walks open sets/tree use sites to `Moon2Open.MetaFact` streams.
- `lua/moonlift/open_validate.lua`
  - Converts unresolved open facts to `Moon2Open.ValidationReport` issues.
- `lua/moonlift/open_expand.lua`
  - Fills open slots/fragments/modules through explicit `Moon2Open.ExpandEnv`
    and `SlotBinding` ASDL values.
- `lua/moonlift/open_rewrite.lua`
  - Applies `Moon2Open.RewriteSet` across type/tree/module spines.
- `lua/moonlift/bind_residence_gather.lua`
  - Gathers `Moon2Bind.ResidenceFact` values from binding/tree use sites.
- `lua/moonlift/bind_residence_decide.lua`
  - Converts residence fact sets to `ResidencePlan` decisions.
- `lua/moonlift/bind_machine_binding.lua`
  - Converts residence decisions to executable machine-binding facts.
- `lua/moonlift/sem_layout_resolve.lua`
  - Resolves `FieldByName` to representation-aware `FieldByOffset` values
    through explicit layout envs.
- `lua/moonlift/sem_const_eval.lua`
  - Evaluates the supported const subset into `ConstValue` / `ConstClass`
    and const statement result ASDL values.
- `lua/moonlift/sem_switch_decide.lua`
  - Produces `SwitchDecision` values from switch key sets.
- `lua/moonlift/sem_call_decide.lua`
  - Produces `CallTarget` values for direct, extern, indirect, closure, and
    unresolved calls.
- `lua/moonlift/parse.lua`
  - Fast hand-written lexer/Pratt parser that emits `Moon2Parse.ParseResult` and
    `Moon2Tree.Module(ModuleSurface)` with surface refs/headers only.  It covers
    function/extern/const/static items, source memory contracts/parameter
    modifiers, plus the initial jump-first statement and expression subset.
- `lua/moonlift/tree_expr_type.lua`
  - Types expression spines from headers, refs, call targets, and structural
    expression forms.
- `lua/moonlift/tree_place_type.lua`
  - Types place spines from headers, refs, derefs, fields, and index bases.
- `lua/moonlift/tree_stmt_type.lua`
  - Produces statement environment-effect ASDL values.
- `lua/moonlift/tree_module_type.lua`
  - Gathers module item/type/value entries into `Moon2Bind.Env`.
- `lua/moonlift/tree_typecheck.lua`
  - Resolves surface value names against explicit `Moon2Bind.Env` scopes, checks
    expression/place/statement/control/function/module types, rewrites headers to
    typed tree nodes, and returns explicit `TypeIssue` reports.
- `lua/moonlift/tree_control_facts.lua`
  - Gathers jump-first control-region facts for labels, params, named jump
    args, yields, returns, and backedges; performs initial label and named jump
    signature validation decisions.
- `lua/moonlift/tree_contract_facts.lua`
  - Converts typed source contracts (`bounds`, `disjoint`, `noalias`,
    `readonly`, `writeonly`) to binding-backed `ContractFact` values consumed by
    vector safety decisions.
- `lua/moonlift/tree_to_back.lua`
  - Lowers manually constructed typed tree functions to `Moon2Back.BackProgram`
    for scalar literal/ref/binary/compare/select/return slices, typed pointer
    and contiguous/strided/window view construction/indexed loads/stores plus
    `len(view)` lowering. Scalar/tree lowering now emits the first fact-rich
    backend command slice for memory and scalar arithmetic: `CmdLoadInfo` /
    `CmdStoreInfo` with explicit `BackAddress` and `BackMemoryInfo`,
    `CmdPtrOffset` for pointer byte offsets, and split `CmdIntBinary` /
    `CmdBitBinary` / `CmdShift` / `CmdRotate` / `CmdFloatBinary` commands
    instead of generic scalar `CmdBinary`. The executable view ABI is now
    `data: ptr, len: index,
    stride: index`; exported view-parameter functions get descriptor-pointer
    wrappers, exported `view(T)` returns use an out descriptor, and bool storage
    fields lower through explicit storage encode/decode. It delegates jump-first `ControlStmtRegion` /
    `ControlExprRegion` lowering to `tree_control_to_back.lua`. It now also
    consumes `VecKernelPlan` for source-kernel auto-vectorization of canonical
    element-typed integer map/reduce kernels, including `i32` sum/dot/fill/copy/
    add/sub/scale/bitwise/in-place/axpy shapes plus `i64`, `u32`, and `u64`
    sum/map families supported by the target facts.
- `lua/moonlift/vec_loop_facts.lua`
  - Gathers `VecLoopFacts` from jump-first control-region backedges and block
    params for the canonical counted-loop shape; indexed view/raw-address loads
    and indexed stores become explicit `VecMemoryBase` / `VecMemoryAccess` /
    `VecStoreFact` values. Initial alias/dependence facts are derived from memory
    base, access pattern, and lane-index evidence. Unsupported shapes produce
    explicit reject/domain/source ASDL values.
- `lua/moonlift/vec_loop_decide.lua`
  - Produces `VecLoopDecision` values from loop facts and target models, with
    explicit `VecLegality` and `VecSchedule` facets for legality and schedule
    policy.
- `lua/moonlift/vec_kernel_plan.lua`
  - Converts typed control regions plus target-supported element shapes into
    explicit element-typed `VecKernelPlan` ASDL values for source-kernel
    vectorization. The current generic kernel expression/store/reduction plan
    covers signed/unsigned 32/64-bit integer map/reduction families where the
    target advertises the needed vector ops, including add/mul/bitwise reduction
    identities as explicit ASDL values. Integer compare/select kernels are now
    modeled explicitly as `VecKernelMaskExpr` compare masks feeding
    `VecKernelExprSelect`, with compare/select and mask logic (`and`/`or`/`not` over comparison masks) support advertised by target
    facts rather than hidden backend peepholes. Kernel plans also carry an
    explicit `VecKernelCounter` decision (`i32` or `index`) so backend lowering
    does not rediscover counter policy from source bindings.
- `lua/moonlift/vec_kernel_safety.lua`
  - Separates vector kernel safety classification from shape recognition. It
    derives `VecKernelMemoryUse`, bounds proofs/assumptions, alias proofs/
    assumptions, and same-index in-place proofs into `VecKernelSafetyDecision`
    values. Binding-backed contracts can now turn raw-pointer vector kernels
    from assumption-backed into `VecKernelSafetyProven` plans, and a counted
    loop over `len(view)` proves bounds for same-view accesses or other views
    connected by `same_len` contracts.
- `lua/moonlift/vec_kernel_to_back.lua`
  - Lowers `VecKernelPlan` values to vector-shaped `Moon2Back` function command
    plans, including vector compare/select and scalar-tail select lowering,
    keeping vector kernel backend emission out of generic tree lowering.  Vector
    kernel loads/stores now use the first fact-rich backend slice:
    `BackAddress` + `BackMemoryInfo` + `CmdLoadInfo` / `CmdStoreInfo`, scalar
    loop arithmetic uses split `CmdIntBinary` / `CmdBitBinary` commands where
    applicable, and vector arithmetic/bitwise ops use split `CmdVecBinary`
    rather than generic vector-shaped `CmdBinary`. The obsolete generic
    executable `CmdBinary`, `CmdLoad`, and `CmdStore` variants are now removed
    from active `Moon2Back.Cmd`; remaining load/store execution goes through
    fact-rich `CmdLoadInfo` / `CmdStoreInfo`. Vector-memory facts now preserve
    access IDs, known/assumed alignment, and proven/assumed bounds evidence as
    `BackMemoryInfo` where the vector layer has that evidence. Explicit
    `VecSchedule` lanes/unroll/interleave/accumulator policy is consumed
    directly; the active map/reduce lowering expands positive integer schedules
    into explicit vector groups, reduction lowering emits multiple vector
    accumulators when requested, vector-kernel alignment evidence lowers into
    `BackAlignment`, and vector-kernel alias decisions lower into
    `BackAliasFact` scope/relation facts.
- `lua/moonlift/vec_to_back.lua`
  - Lowers selected `Moon2Vec` block/cmd/function specs to executable
    `Moon2Back` programs, including vector load/splat/add/extract slices.
- `lua/moonlift/host_quote.lua`
  - First hosted-syntax layer. It recognizes Moonlift `func ... end` and
    `module ... end` keyword forms inside an outer Lua chunk, uses root
    `quote.lua` to hygienically emit normal Lua, and returns compilable
    Moonlift function/module quote values. It also supports narrow staged
    antiquote with `@{lua_expr}` for scalar literal/source/type splices, hosted
    `region -> T` / `entry` control syntax, and `.mlua` loading through
    `Host.loadfile` / `Host.dofile`; `moonlift/run_mlua.lua`
    is a small hosted-file runner. This proves the custom-keyword direction
    without forking LuaJIT: hosted syntax is a frontend over the existing
    parser/ASDL/compiler path.
- `lua/moonlift/host.lua`, `host_session.lua`, `host_issue_values.lua`,
  `host_type_values.lua`, `host_struct_values.lua`, `host_template_values.lua`,
  `host_fragment_values.lua`, `host_expr_values.lua`, `host_place_values.lua`,
  `host_func_values.lua`, `host_region_values.lua`, `host_module_values.lua`
  - Initial ASDL-backed hosted value API. Types, fields, structs/unions/enums,
    recursive draft/seal structs, expressions, functions, and modules are
    Terra-like Lua values that lower to explicit `Moon2Type` / `Moon2Tree` ASDL.
    The public `host.lua` facade is thin; semantic construction lives in the
    precise value files. Current tests cover type/struct/draft/function ASDL
    construction plus typecheck/backend validation for direct-builder scalar,
    conditional, pointer-index store/load, Lua-hosted struct-template,
    expression fragment/`emit_expr`, Lua-hosted expression-fragment template,
    explicit host issues, reflection, JIT execution, pointer load/address lowering, struct
    field store/load lowering, and jump/emit continuation-region functions.
- `Moon2Open.ContSlot` / `Moon2Tree.StmtJumpCont`
  - Continuation parameters are now represented explicitly in ASDL. Region
    fragments can contain jumps to continuation slots; fills bind those slots to
    concrete block labels or enclosing continuation slots, and `open_expand.lua`
    rewrites those jumps into ordinary `StmtJump` nodes before typecheck/backend
    lowering. Hosted
    syntax can create `region name(runtime; cont: cont(...))` fragment values
    with entry/internal blocks and fuse them with either
    `emit fragment(...; cont = block)` for known hosted fragment variables or
    explicit `emit @{fragment}(...; cont = block)`. Direct hosted builders can
    also fill an emitted fragment continuation with an enclosing fragment
    continuation slot, represented as `SlotValueContSlot`, so staged dispatch
    regions can forward exits without adapter blocks when the protocols match.
    Expansion rebases fragment labels and adds the fragment blocks to the
    surrounding control region. Hosted `expr name(...) -> T ... end` fragments
    are also supported and lower through `ExprUseExprFrag`.
- `lua/moonlift/json_codegen.lua`
  - Single public JSON extraction path built on the generic indexed-tape
    representation. `json_codegen.project(fields)` now uses the same reusable
    `JsonDocDecoder` path as generic document access: bytes are decoded to the
    compact tape, indexed into parent/child/sibling/key arrays, and projected
    fields are read through low-level Moonlift helpers. The output surfaces stay
    convenient — raw `int32_t` buffers, Lua tables for small projected results,
    and reusable buffer-backed views — but the runtime representation is one
    low-level indexed document path. Missing projected fields default to
    zero/false and reused outputs are overwritten deterministically. The current
    generic/project raw-key lookup intentionally does not claim escaped-key
    semantic equality; escaped-key-aware extraction belongs in a future query
    kernel over the same indexed tape. There is no custom region builder API, no
    JSON compiler ASDL, no generated Moonlift source string projection path, and
    no Rust JSON runtime. `Projector:view_layout_facts(T)` exports the same
    buffer layout as `Moon2Host` ASDL facts (`HostTypeLayout`, `HostAccessPlan`,
    `HostViewPlan`), keeping host exposure policy explicit without making JSON a
    compiler concept.
- `lua/moonlift/value_proxy.lua`, `lua/moonlift/buffer_view.lua`, and `lua/moonlift/host_arena_abi.lua`
  - Provide the initial host-facing Moonlift value proxy/runtime ABI slice. A
    small Lua table shell hides an FFI `MoonliftValueRef`, optional typed
    pointer, and owner/session reference, while registered proxy families
    implement field/index/length/iterator and materialization behavior.
    `buffer_view.lua` is the generic buffer-backed table-shaped view layer for
    explicit structs and now also the bootstrap descriptor-backed zero-copy
    `view(T)` runtime: `define_view_from_host_descriptor` wraps `MoonView_T`
    descriptors with `data`, `len`, and element `stride` and exposes checked
    indexing plus direct `get_field(i)` accessors. `host_layout_facts.lua` lowers
    those record/view layouts to explicit `Moon2Host` ASDL fact streams and
    access/view plans; `host_arena_abi.lua` proves the related host-arena typed
    record path. A layout defines a C struct, fields, and type-local Lua methods;
    proxy field access mostly casts a pointer and reads a field. This is the
    bridge for exposing Moonlift-owned
    values to Lua without eager table rebuilding. The performance plan is in
    `HOST_EXPOSURE_PERFORMANCE_DESIGN.md`: proxy indexes/caches, reusable decode
    sessions, coarse native operations over hidden refs, and a separate native
    Lua-table builder for true eager table output. The lower-level ABI direction
    is in `HOST_ARENA_ABI_DESIGN.md`: a domain-neutral Rust HostArena with stable
    refs/pointers, generated layout facts, and Lua accessors that mostly cast
    pointers and read fields. The first Rust-owned slice lives in
    `moonlift/src/host_arena.rs` plus `lua/moonlift/host_arena_native.lua`:
    sessions allocate aligned typed records, initialize scalar fields by layout
    offsets, support batch record allocation, return stable refs/pointers, and
    reject stale refs after reset. There is deliberately no Rust-defined JSON
    arena, no Rust generic object/array/string graph builder, and no JSON-shaped
    runtime object model. Library domains such as JSON must emit low-level
    Moonlift code and explicit buffer/struct views; the retained JSON projection
    path no longer calls `host_arena_native` at all.
- `lua/moonlift/json_library.lua` and `lib/json.moon2`
  - Provide the first Moonlift builtin library slice as ordinary low-level
    Moonlift source: an allocation-free scalar JSON validator, tape decoder, and
    generic indexed-tape document path written in block/jump form. This
    intentionally does not add JSON concepts to the main compiler ASDL; JSON is a
    library-level byte parser built from existing Moonlift control and pointer
    primitives. `json_index_tape_scalar` turns the raw event tape into flat
    parent/child/sibling/key/end arrays, and the Lua `JsonDoc` wrapper keeps only
    source bytes plus those integer buffers. `JsonDocDecoder` provides reusable
    decode sessions so repeated generic parses do not allocate fresh FFI buffers.
    Generic field reads delegate to low-level Moonlift helpers
    (`json_find_field_raw_scalar`, `json_read_i32_scalar`,
    `json_read_bool_scalar`) and do not materialize Lua object graphs. This first
    generic lookup is an explicit raw-key fast path; escaped-key semantic lookup
    belongs in the next query-kernel layer. Slow eager
    object rebuild and lazy generic tape-view public APIs remain removed;
    user-facing extraction uses the same indexed document path above. The public
    standard-library surface is `require("moonlift").json` /
    `require("moonlift.std").json`, with convenience helpers such as
    `json.decode`, `json.get_i32`, `json.get_bool`, `json.project`, and
    `json.decode_project` layered over the same indexed document path.

## Source AST constructor API example

The minimal hosted generation layer is `moonlift.ast`: documented constructors
that return plain source ASDL nodes.  For example:

```lua
local ast = require("moonlift.ast")

return ast.module {
    ast.export_func {
        name = "add",
        params = {
            ast.param("a", ast.i32()),
            ast.param("b", ast.i32()),
        },
        ret = ast.i32(),
        body = {
            ast.return_(ast.add(ast.name("a"), ast.name("b"))),
        },
    },
}
```

This is intentionally not an extension framework: hosted Lua builds existing
ASDL values, and the normal PVM phases typecheck, lower, validate, and execute
those values.  If a future hosted library needs new meaning rather than new
spelling, that meaning must first become ASDL.

## Hosted value API example

The direct hosted value API in `moonlift.host` is the ASDL-backed counterpart to
hosted source quotes.  For example, this builder code:

```lua
local moon = require("moonlift.host")
local M = moon.module("Demo")
M:export_func("add", { moon.param("a", moon.i32), moon.param("b", moon.i32) }, moon.i32, function(fn)
    return fn:param("a") + fn:param("b")
end)
```

constructs the same kind of `Moon2Tree.FuncExport` ASDL that the source form
would parse to:

```moonlift
export func add(a: i32, b: i32) -> i32
    return a + b
end
```

The host API is intentionally a constructor layer over explicit ASDL values, not
a separate compiler IR. Moonlift source stays the closed object language; Lua is
where type/function/fragment templates live. Source-level generic syntax is not a
language goal.

## Design rule

ASDL2 is not allowed to lose information from the current rich ASDL.
Every old distinction must become one of:

- a spine node,
- a phase facet/header,
- a type-class / decision-class value,
- a fact/proof/reject value,
- a backend command payload,
- or an explicitly preserved legacy/sugar node.

## Intended future pipeline

```text
Moon2Tree.Module(ModuleSurface)
  -> typing / resolution facts
  -> Moon2Tree.Module(ModuleTyped)
  -> semantic facts + decisions
  -> Moon2Tree.Module(ModuleSem)
  -> control-graph facts, loop-recognition facts, memory/alias/dependence/vector/code-shape facts + decisions
  -> Moon2Vec / code-shaped IR
  -> Moon2Back.BackProgram
  -> Artifact
```

## Moonlift LSP

The LSP architecture is defined in `LSP_INTEGRATION_DESIGN.md`.

```text
.lua  -> lua_ls or other ordinary Lua tooling
.mlua -> moonlift-lsp, focused on Moonlift hosted islands and semantic facts
```

Run the current server from the repository root with:

```bash
luajit moonlift/lsp.lua
```

Programmatic embedding can use the package facade:

```lua
require("moonlift").lsp.run()
```

The language server is integrated as canonical ASDL/PVM compiler work, not as a
scanner-only sidecar. The current executable path supports initialize,
full-document sync, publish and pull diagnostics, document/workspace symbols, hover,
completion, definition, references, document highlights, prepare-rename/rename,
signature help, semantic tokens, folding ranges, selection ranges, parameter
inlay hints, fragment navigation/rename, and quick-fix code actions for selected host/binding diagnostics; other request families already
decode/encode through ASDL/RPC result shapes and return explicit empty/null
results until their editor semantic facts are implemented. LSP diagnostics,
symbols, hover, completion, navigation, rename, semantic tokens, and code
actions are downstream of `MluaParseResult`, `MluaHostPipelineResult`, source
anchors, scoped binding facts, and existing Moonlift compiler facts. Local and
parameter navigation uses explicit scope/resolution facts, including shadowing,
block/continuation parameters, jump-argument writes, and read/write highlight
roles. Unresolved value uses are published as anchored binding-resolution
diagnostics and have an origin-driven quick fix to insert a local declaration.
Type/backend diagnostics use stable variant-derived codes and messages; common
type errors are anchored to operator/keyword/name source facts when available.

## Validation

Current jump-first ASDL redesign note: `test_asdl_define.lua` validates the new
schema.  Old loop-constructor tests have been retired or rewritten to construct
`Control*Region` values.  `tree_control_to_back.lua` now lowers block params,
named jumps, yields, returns, and intra-region `if`/`switch` joins to flat
`Moon2Back` blocks.  Control facts validate labels, named jump signatures,
yield/result shape, and block termination. Vector loop recognition now feeds
source-kernel vector lowering for canonical integer map/reduce families over
signed and unsigned 32/64-bit elements, including proof-backed `view(i32)` sum
and map/copy kernels using `len(view): index` plus `same_len` contracts, and a broad
`i32`/`i64`/`u32`/`u64` constructed-view family (`sum`, `dot`, `copy`, `fill`,
`add`, `sub`, `scale`, selected bitwise maps/reductions, `inc`, `axpy`) over
local views constructed with `view(ptr, len)` or unit-stride `view(ptr, len, 1)`
when the construction aliases resolve to argument pointers/lengths. Contiguous/unit-stride constructed windows now vectorize through an explicit
`VecWindowRangeObligation` proof phase: full-range windows such as `view_window(v, 0, n)`
and affine literal shrink windows such as `view_window(v, 1, n - 1)`, `view_window(v, s, n - s)`
where `s` is a scalar alias for a non-negative literal, nested windows with accumulated literal
offsets, or `view_window(v, 0, n - k)` are compiler-proven from the base bounds. View parameters now participate through explicit
`VecKernelLenSource` values (`VecKernelLenView(view)`), so `len(view)`-based windows vectorize
without pretending the length is an ordinary scalar binding. General subwindows require
`window_bounds(base, base_len, start, len)` and otherwise produce `VecKernelSafetyRejected`.
Non-unit constructed-view strides still produce explicit vector rejects until gather/scatter
support exists. Lower loop facts classify constant stride as `VecAccessStrided` and the loop
decision phase rejects unsupported memory patterns explicitly. The kernel backend is lane-count
and element parameterized from `VecLoopDecision`; the current Cranelift JIT target
model advertises 128-bit shapes (`i32x4`, `u32x4`, `i64x2`, `u64x2`) as the
largest executable shapes after probing showed this backend rejects `i32x8` with
an unsupported SSA vector type.

From repo root:

```bash
luajit moonlift/test_asdl_define.lua
luajit moonlift/test_source_position_index.lua
luajit moonlift/test_source_text_apply.lua
luajit moonlift/test_source_anchor_index.lua
luajit moonlift/test_editor_workspace_apply.lua
luajit moonlift/test_mlua_document_parts.lua
luajit moonlift/test_mlua_island_parse.lua
luajit moonlift/test_mlua_document_parse.lua
luajit moonlift/test_mlua_document_analysis.lua
luajit moonlift/test_editor_diagnostic_facts.lua
luajit moonlift/test_editor_symbol_facts.lua
luajit moonlift/test_editor_subject_at.lua
luajit moonlift/test_editor_hover.lua
luajit moonlift/test_editor_completion_context.lua
luajit moonlift/test_editor_completion_items.lua
luajit moonlift/test_editor_signature_help.lua
luajit moonlift/test_editor_inlay_hints.lua
luajit moonlift/test_editor_binding_navigation.lua
luajit moonlift/test_editor_binding_scopes.lua
luajit moonlift/test_editor_semantic_tokens.lua
luajit moonlift/test_editor_structure_ranges.lua
luajit moonlift/test_editor_code_actions.lua
luajit moonlift/test_lsp_integrated.lua
luajit moonlift/test_lsp_diagnostic_pull.lua
luajit moonlift/test_lsp_unresolved_diagnostics.lua
luajit moonlift/test_lsp_navigation_tokens.lua
luajit moonlift/test_lsp_fragment_navigation.lua
luajit moonlift/test_lsp_code_actions.lua
luajit moonlift/test_lsp_signature_help.lua
luajit moonlift/test_back_validate.lua
luajit moonlift/test_back_add_i32.lua

# requires the current Rust backend shared library
cargo build --manifest-path moonlift/Cargo.toml
luajit moonlift/test_back_add_i32.lua
luajit moonlift/test_back_fact_rich_smoke.lua
luajit moonlift/test_back_branch_select.lua
luajit moonlift/test_back_call.lua
luajit moonlift/test_back_memory_data.lua
luajit moonlift/test_back_cast_intrinsic_switch.lua
luajit moonlift/test_back_extern_mem.lua
luajit moonlift/test_back_vector_smoke.lua
luajit moonlift/test_back_indirect_stmt.lua
luajit moonlift/test_back_zero_alias_ops.lua
luajit moonlift/test_project_report.lua
luajit moonlift/test_core_scalar.lua
luajit moonlift/test_core_operator.lua
luajit moonlift/test_type_classify.lua
luajit moonlift/test_type_to_back_scalar.lua
luajit moonlift/test_type_size_align.lua
luajit moonlift/test_type_abi_classify.lua
luajit moonlift/test_open_facts_validate.lua
luajit moonlift/test_open_expand.lua
luajit moonlift/test_open_rewrite.lua
luajit moonlift/test_bind_residence.lua
luajit moonlift/test_bind_residence_coverage.lua
luajit moonlift/test_sem_layout_resolve.lua
luajit moonlift/test_sem_const_eval.lua
luajit moonlift/test_sem_switch_call.lua
luajit moonlift/test_parse_typecheck.lua
luajit moonlift/test_parse_playground.lua
luajit moonlift/test_parse_kernels.lua
luajit moonlift/test_tree_type.lua
luajit moonlift/test_tree_typecheck.lua
luajit moonlift/test_tree_control_facts.lua
luajit moonlift/test_tree_to_back_add_select.lua
luajit moonlift/test_tree_to_back_counted_loop.lua
luajit moonlift/test_tree_to_back_while_expr_loop.lua
luajit moonlift/test_tree_to_back_control_multiblock.lua
luajit moonlift/test_vec_loop_facts_decide.lua
luajit moonlift/test_vec_kernel_plan.lua
luajit moonlift/test_vec_kernel_schedule_to_back.lua
luajit moonlift/test_vec_inspect.lua
luajit moonlift/test_vec_to_back.lua
luajit moonlift/test_host_quote.lua
luajit moonlift/test_host_quote_value_splice.lua
luajit moonlift/test_host_type_values.lua
luajit moonlift/test_host_struct_values.lua
luajit moonlift/test_host_struct_draft_values.lua
luajit moonlift/test_host_template_values.lua
luajit moonlift/test_host_fragment_values.lua
luajit moonlift/test_host_issue_values.lua
luajit moonlift/test_host_reflection.lua
luajit moonlift/test_host_func_values.lua
luajit moonlift/test_host_place_values.lua
luajit moonlift/test_host_region_values.lua
luajit moonlift/test_host_value_jit.lua
luajit moonlift/test_host_addr_load_jit.lua
luajit moonlift/test_host_field_jit.lua
luajit moonlift/test_host_patterns.lua
luajit moonlift/test_host_metaprogramming_patterns.lua
luajit moonlift/test_json_projection_view.lua
luajit moonlift/test_json_generic_doc.lua
luajit moonlift/test_continuation_slot_expand.lua
luajit moonlift/test_json_library.lua
```
